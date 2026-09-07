import AppKit
import SwiftUI

/// Narrow hardware boundary keeps recovery paths testable without touching monitors.
@MainActor struct AppModelServices {
    var displays: () -> [DisplayInfo] = { DisplayBackend.displays() }
    var profile: (DisplayInfo) -> BrightnessProfile? = { BrightnessProfile.forDisplay($0) }
    var brightness: (UInt32) async -> BrightnessStatus = { await HardwareService.shared.brightness(displayID: $0) }
    var setBrightness: (UInt32, Double) async throws -> Void = { try await HardwareService.shared.setBrightness(displayID: $0, value: $1) }
    var setMode: (UInt32, Int32) throws -> Void = { try DisplayBackend.setMode(displayID: $0, modeID: $1) }
    var save: (Preferences) throws -> Void = { try $0.save() }
}

@MainActor final class AppModel: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var brightness: [UInt32: Double] = [:]
    @Published var brightnessDetails: [UInt32: String] = [:]
    @Published var preferences = Preferences.load()
    @Published var brightnessProfiles: [UInt32: BrightnessProfile] = [:]
    @Published var matchingInProgress = false
    private var matchRequest = 0
    @Published var notice: String?
    @Published var pendingMode: (displayID: UInt32, original: Int32)?
    @Published var countdown = 15
    private var revertTimer: Timer?
    private var refreshObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var writeRevisions: [UInt32: Int] = [:]
    private var hasRefreshed = false
    private var pendingBrightnessWrites: Set<UInt32> = []
    private var brightnessTasks: [UInt32: Task<Void, Never>] = [:]
    private var knownDisplays: Set<String> = []
    private let services: AppModelServices
    init(services: AppModelServices? = nil, preferences: Preferences? = nil, observeSystem: Bool = true) {
        self.services = services ?? AppModelServices()
        if let preferences { self.preferences = preferences }
        refresh()
        guard observeSystem else { return }
        refreshObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                self?.refresh()
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self?.refresh(restoreAfterWake: true)
            }
        }
        screenWakeObserver = center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self?.refresh(restoreAfterWake: true)
            }
        }
    }
    func refresh(restoreAfterWake: Bool = false) {
        cancelMatchRequest()
        let newDisplays = services.displays()
        let removed = displays.filter { old in !newDisplays.contains { $0.id == old.id && $0.stableID == old.stableID } }
        for display in removed {
            brightnessTasks.removeValue(forKey: display.id)?.cancel()
            pendingBrightnessWrites.remove(display.id)
            writeRevisions[display.id, default: 0] += 1
            brightness.removeValue(forKey: display.id)
            brightnessDetails.removeValue(forKey: display.id)
        }
        if let pending = pendingMode, removed.contains(where: { $0.id == pending.displayID }) {
            revertTimer?.invalidate()
            revertTimer = nil
            pendingMode = nil
            notice = "Display disconnected during resolution preview. Reconnect it and check its resolution."
        }
        let incoming = Set(newDisplays.map(\.stableID)).subtracting(knownDisplays)
        // hasRefreshed remains true even when every display has disconnected.
        let reconnect = hasRefreshed && !incoming.isEmpty
        displays = newDisplays
        brightnessProfiles = Dictionary(uniqueKeysWithValues: newDisplays.compactMap { display in
            services.profile(display).map { (display.id, $0) }
        })
        recalculateVisualGains()
        knownDisplays = Set(newDisplays.map(\.stableID))
        hasRefreshed = true
        let connectedIDs = Set(newDisplays.map(\.id))
        brightness = brightness.filter { connectedIDs.contains($0.key) }
        brightnessDetails = brightnessDetails.filter { connectedIDs.contains($0.key) }
        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            for display in newDisplays {
                guard !Task.isCancelled else { return }
                let revision = self.writeRevisions[display.id, default: 0]
                let status = await self.services.brightness(display.id)
                guard !Task.isCancelled, self.refreshGeneration == generation else { return }
                guard self.displays.contains(where: { $0.id == display.id && $0.stableID == display.stableID }),
                      self.writeRevisions[display.id, default: 0] == revision,
                      !self.pendingBrightnessWrites.contains(display.id) else { continue }
                if let value = status.value { self.brightness[display.id] = value }
                self.brightnessDetails[display.id] = status.value == nil && self.brightness[display.id] != nil
                    ? "Last known brightness · " + status.detail : status.detail
            }
        }
        if (reconnect || restoreAfterWake) && preferences.restoreOnReconnect && pendingMode == nil {
            let saved = preferences.lastDisplays.filter { restoreAfterWake || incoming.contains($0.stableID) }
            applySaved(saved)
        }
    }
    /// Completion reports the latest applied/failed batch; superseded writes are silent.
    func setBrightness(_ value: Double, for display: DisplayInfo, completion: ((Bool) -> Void)? = nil) {
        cancelMatchRequest()
        let connected = Set(displays.map(\.id))
        let available = brightness.filter {
            connected.contains($0.key) && (brightnessDetails[$0.key]?.hasPrefix("Last known") != true || $0.key == display.id)
        }
        let values: [UInt32: Double]
        if preferences.linkedBrightness && preferences.matchedBrightness {
            let profiles = brightnessProfiles.filter { available[$0.key] != nil }
            if profiles[display.id] != nil && profiles.count >= 2 {
                values = MatchedBrightness.targets(profiles: profiles, gains: matchGains, source: display.id, requested: value)
            } else {
                // An unknown monitor must not silently fall back to percentage matching.
                values = [display.id: value]
            }
        } else {
            values = LinkedBrightness.targets(current: available, source: display.id, requested: value, linked: preferences.linkedBrightness)
        }
        let targets = displays.filter { values[$0.id] != nil }
        guard !targets.isEmpty else { completion?(false); return }
        var remaining = targets.count
        var succeeded = true
        for target in targets {
            guard let value = values[target.id] else { continue }
            queueBrightness(value, for: target) { success in
                succeeded = succeeded && success
                remaining -= 1
                if remaining == 0 { completion?(succeeded) }
            }
        }
    }
    var matchableDisplays: [DisplayInfo] {
        displays.filter { brightnessProfiles[$0.id] != nil && brightness[$0.id] != nil && brightnessDetails[$0.id]?.hasPrefix("Last known") != true }
    }
    var matchReference: DisplayInfo? {
        matchableDisplays.first(where: \.isBuiltin) ?? matchableDisplays.first(where: \.isMain) ?? matchableDisplays.first
    }
    private var matchGains: [UInt32: Double] {
        Dictionary(uniqueKeysWithValues: displays.map { ($0.id, MatchedBrightness.validGain(preferences.brightnessMatchGains[$0.stableID])) })
    }
    private func cancelMatchRequest() {
        matchRequest += 1
        matchingInProgress = false
    }
    var matchUnavailableReason: String? {
        if matchingInProgress { return "Brightness matching is already in progress." }
        if !pendingBrightnessWrites.isEmpty { return "Wait for the current brightness adjustment to finish, then try Match again." }
        if displays.count < 2 { return "Connect a second display to match brightness." }
        if matchableDisplays.count < 2 { return "Matching needs two supported displays with current brightness readings. Move the Mac brightness away from its minimum or maximum, then refresh. Some external displays do not provide a supported profile." }
        return nil
    }
    var canStartBrightnessMatch: Bool { matchUnavailableReason == nil }
    func matchBrightness() {
        if let reason = matchUnavailableReason {
            notice = reason
            return
        }
        matchRequest += 1
        let request = matchRequest
        matchingInProgress = true
        let candidates = matchableDisplays
        Task { [weak self] in
            guard let self else { return }
            defer { if self.matchRequest == request { self.matchingInProgress = false } }
            var fresh: [UInt32: Double] = [:]
            for display in candidates {
                let status = await self.services.brightness(display.id)
                guard self.matchRequest == request else { return }
                guard let value = status.value else {
                    self.notice = "Could not read \(display.name). Try refreshing before matching."
                    return
                }
                fresh[display.id] = value
            }
            guard let reference = self.matchReference, let level = fresh[reference.id] else { return }
            let profiles = Dictionary(uniqueKeysWithValues: candidates.compactMap { display in
                services.profile(display).map { (display.id, $0) }
            })
            self.brightnessProfiles = profiles
            self.recalculateVisualGains()
            let values = MatchedBrightness.targets(profiles: profiles, gains: self.matchGains, source: reference.id, requested: level)
            guard values.count >= 2 else {
                self.notice = "These displays do not have a shared estimated brightness range."
                return
            }
            let oldMatched = self.preferences.matchedBrightness
            let oldLinked = self.preferences.linkedBrightness
            self.preferences.matchedBrightness = true
            self.preferences.linkedBrightness = true
            guard self.save() else {
                self.preferences.matchedBrightness = oldMatched
                self.preferences.linkedBrightness = oldLinked
                return
            }
            var remaining = values.count
            var succeeded = true
            for display in candidates {
                guard let value = values[display.id] else { continue }
                self.queueBrightness(value, for: display) { success in
                    succeeded = succeeded && success
                    remaining -= 1
                    guard remaining == 0, self.matchRequest == request else { return }
                    if succeeded {
                        if self.save() { self.notice = "Matched estimated brightness using \(reference.name). Fine-tune if the screens still look different." }
                    } else {
                        self.preferences.matchedBrightness = false
                        self.preferences.linkedBrightness = false
                        self.save()
                    }
                }
            }
        }
    }
    func setLinkedBrightness(_ enabled: Bool) {
        cancelMatchRequest()
        preferences.linkedBrightness = enabled
        save()
    }
    func useOrdinaryLinking() {
        cancelMatchRequest()
        preferences.matchedBrightness = false
        preferences.linkedBrightness = true
        save()
    }
    func beginMatchTuning() {
        cancelMatchRequest()
        preferences.linkedBrightness = false
        save()
    }
    func tuneBrightness(_ value: Double, for display: DisplayInfo) {
        cancelMatchRequest()
        queueBrightness(value, for: display)
    }
    var canSaveVisualMatch: Bool { matchableDisplays.count >= 2 && pendingBrightnessWrites.isEmpty }
    private func recalculateVisualGains() {
        guard let reference = displays.first(where: { $0.stableID == preferences.brightnessMatchReference }) else { return }
        let levels = Dictionary(uniqueKeysWithValues: displays.compactMap { display in
            preferences.brightnessMatchLevels[display.stableID].map { (display.id, $0) }
        })
        guard let gains = MatchedBrightness.calibratedGains(profiles: brightnessProfiles, levels: levels, reference: reference.id) else { return }
        for display in displays {
            if let gain = gains[display.id] { preferences.brightnessMatchGains[display.stableID] = gain }
        }
    }
    @discardableResult func saveVisualMatch() -> Bool {
        guard canSaveVisualMatch, let reference = matchReference else { return false }
        let profiles = brightnessProfiles.filter { brightness[$0.key] != nil }
        guard let gains = MatchedBrightness.calibratedGains(profiles: profiles, levels: brightness, reference: reference.id) else {
            notice = "Raise the darkest display before saving a visual match."
            return false
        }
        preferences.brightnessMatchLevels = Dictionary(uniqueKeysWithValues: matchableDisplays.compactMap { display in
            brightness[display.id].map { (display.stableID, $0) }
        })
        preferences.brightnessMatchReference = reference.stableID
        preferences.brightnessMatchGains = Dictionary(uniqueKeysWithValues: displays.compactMap { display in
            gains[display.id].map { (display.stableID, $0) }
        })
        preferences.matchedBrightness = true
        preferences.linkedBrightness = true
        guard save() else { return false }
        notice = "Visual match saved. Linked adjustments now use your calibration."
        return true
    }
    private func queueBrightness(_ value: Double, for display: DisplayInfo, completion: ((Bool) -> Void)? = nil) {
        guard value.isFinite, displays.contains(where: { $0.id == display.id && $0.stableID == display.stableID }) else { completion?(false); return }
        let bounded = min(1, max(0, value))
        pendingBrightnessWrites.insert(display.id)
        brightness[display.id] = bounded
        writeRevisions[display.id, default: 0] += 1
        let revision = writeRevisions[display.id, default: 0]
        brightnessTasks[display.id]?.cancel()
        brightnessTasks[display.id] = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(100))
                try await self.services.setBrightness(display.id, bounded)
                guard self.writeRevisions[display.id] == revision else { return }
                self.pendingBrightnessWrites.remove(display.id)
                self.brightnessTasks[display.id] = nil
                self.brightnessDetails[display.id] = display.isBuiltin ? "Built-in hardware brightness" : "DDC hardware brightness"
                self.remember()
                completion?(true)
            } catch is CancellationError {
                // A newer slider value owns this display now.
            } catch {
                guard self.writeRevisions[display.id] == revision else { return }
                self.pendingBrightnessWrites.remove(display.id)
                self.brightnessTasks[display.id] = nil
                self.brightness.removeValue(forKey: display.id)
                self.brightnessDetails[display.id] = "Brightness unavailable after failed adjustment"
                if self.preferences.matchedBrightness && self.preferences.linkedBrightness {
                    self.preferences.matchedBrightness = false
                    self.preferences.linkedBrightness = false
                    self.save()
                }
                self.notice = "\(display.name): \(error.localizedDescription)"
                self.refresh()
                completion?(false)
            }
        }
    }
    func changeMode(_ mode: Int32, for display: DisplayInfo) {
        guard mode != display.currentModeID else { return }
        guard pendingMode == nil else { return }
        do {
            try services.setMode(display.id, mode)
            pendingMode = (display.id, display.currentModeID)
            countdown = 15
            refresh()
            revertTimer?.invalidate()
            revertTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.countdown -= 1
                    if self.countdown <= 0 { self.revertMode() }
                }
            }
            if let revertTimer { RunLoop.main.add(revertTimer, forMode: .common) }
        } catch { notice = error.localizedDescription }
    }
    func keepMode() {
        revertTimer?.invalidate(); revertTimer = nil; pendingMode = nil; remember()
    }
    func revertMode() {
        guard let pending = pendingMode else { return }
        revertTimer?.invalidate(); revertTimer = nil; pendingMode = nil
        do { try services.setMode(pending.displayID, pending.original) }
        catch { notice = "Could not restore display mode: \(error.localizedDescription)" }
        refresh()
    }
    func makeMain(_ display: DisplayInfo) {
        do { try DisplayBackend.setMain(displayID: display.id); refresh() }
        catch { notice = error.localizedDescription }
    }
    func snapshot() -> [SavedDisplay] {
        displays.compactMap { display in
            guard let mode = display.modes.first(where: { $0.id == display.currentModeID }) else { return nil }
            return SavedDisplay(stableID: display.stableID, brightness: brightness[display.id], width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, refreshRate: mode.refreshRate)
        }
    }
    @discardableResult func remember() -> Bool {
        // Preserve disconnected monitors, and never replace a saved value with an
        // unknown reading while the asynchronous hardware refresh is in flight.
        var saved = Dictionary(preferences.lastDisplays.map { ($0.stableID, $0) }, uniquingKeysWith: { _, latest in latest })
        for var item in snapshot() {
            let displayID = displays.first { $0.stableID == item.stableID }?.id
            if item.brightness == nil || displayID.map({ pendingBrightnessWrites.contains($0) || brightnessDetails[$0]?.hasPrefix("Last known") == true }) == true {
                item.brightness = saved[item.stableID]?.brightness
            }
            saved[item.stableID] = item
        }
        preferences.lastDisplays = saved.values.sorted { $0.stableID < $1.stableID }
        return save()
    }
    @discardableResult func save() -> Bool {
        do { try services.save(preferences); return true }
        catch { notice = "Could not save preferences: \(error.localizedDescription)"; return false }
    }
    func savePreset(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        preferences.presets.append(DisplayPreset(name: String(clean.prefix(40)), displays: snapshot())); save()
    }
    func deletePreset(_ preset: DisplayPreset) { preferences.presets.removeAll { $0.id == preset.id }; save() }
    func applyPreset(_ preset: DisplayPreset) {
        cancelMatchRequest()
        applySaved(preset.displays, presetName: preset.name)
    }
    private func applySaved(_ saved: [SavedDisplay], presetName: String? = nil) {
        let targets = saved.compactMap { item -> (DisplayInfo, Double)? in
            guard let display = displays.first(where: { $0.stableID == item.stableID }), let value = item.brightness, value.isFinite else { return nil }
            return (display, min(1, max(0, value)))
        }
        guard !targets.isEmpty else {
            if presetName != nil { notice = "No connected displays match this preset’s saved brightness values." }
            return
        }
        // Mark every target before asynchronous reads can publish older values.
        var revisions: [UInt32: Int] = [:]
        for (display, _) in targets {
            brightnessTasks[display.id]?.cancel()
            brightnessTasks[display.id] = nil
            writeRevisions[display.id, default: 0] += 1
            pendingBrightnessWrites.insert(display.id)
            revisions[display.id] = writeRevisions[display.id]
        }
        Task { [weak self] in
            guard let self else { return }
            var errors: [String] = []
            var applied = 0
            for (display, value) in targets {
                guard self.writeRevisions[display.id] == revisions[display.id] else { continue }
                do {
                    try await self.services.setBrightness(display.id, value)
                    guard self.writeRevisions[display.id] == revisions[display.id] else { continue }
                    self.pendingBrightnessWrites.remove(display.id)
                    self.brightness[display.id] = value
                    // Invalidate reads that began while this write was in flight.
                    self.writeRevisions[display.id, default: 0] += 1
                    applied += 1
                } catch {
                    guard self.writeRevisions[display.id] == revisions[display.id] else { continue }
                    self.pendingBrightnessWrites.remove(display.id)
                    errors.append("\(display.name): \(error.localizedDescription)")
                }
            }
            let persisted = applied == 0 || self.remember()
            if !errors.isEmpty {
                self.notice = errors.joined(separator: "\n")
            } else if let presetName, applied > 0, persisted {
                self.notice = "Applied \(presetName) to \(applied) display\(applied == 1 ? "" : "s")."
            }
        }
    }
}
