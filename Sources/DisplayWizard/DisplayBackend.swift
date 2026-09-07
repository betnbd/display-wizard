import AppKit
import CoreGraphics
import Darwin
import IOKit.graphics

struct DisplayModeInfo: Identifiable, Hashable, Sendable {
    let id: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    var isHiDPI: Bool { pixelWidth > width }
    var label: String { "\(width) × \(height)" + (isHiDPI ? " · HiDPI" : "") }
}

struct DisplayInfo: Identifiable, Sendable {
    let id: UInt32
    let stableID: String
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let rotation: Double
    let modes: [DisplayModeInfo]
    let currentModeID: Int32
    // Oriented physical pixel dimensions from modes explicitly flagged native by macOS.
    var nativeWidth: Int? = nil
    var nativeHeight: Int? = nil
}

struct BrightnessStatus: Sendable {
    let value: Double?
    let isHardware: Bool
    let detail: String
}

enum DisplayBackendError: LocalizedError {
    case unavailable(String)
    case configuration(CGError)
    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .configuration(let code): return "macOS could not apply the display change (error \(code.rawValue))."
        }
    }
}

/// Display mutations are explicit; enumeration and brightness discovery are read-only.
/// Hardware brightness calls should run on a serial background queue to avoid blocking UI.
enum DisplayBackend {
    private final class DDCRanges: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: Double] = [:]
    }
    private static let ranges = DDCRanges()

    /// A monitor's VCP range is stable across mode changes; cache only after two
    /// matching reads so a transient reply cannot wildly change the slider scale.
    private static func brightnessMaximum(_ id: UInt32) throws -> Double {
        let key = stableID(id)
        ranges.lock.lock()
        let cached = ranges.values[key]
        ranges.lock.unlock()
        if let cached { return cached }
        var previous = try ddcNumber(id, operation: "max")
        for _ in 0..<3 {
            let next = try ddcNumber(id, operation: "max")
            if next == previous, next > 0, next <= 65535 {
                ranges.lock.lock()
                ranges.values[key] = next
                ranges.lock.unlock()
                return next
            }
            previous = next
        }
        throw DisplayBackendError.unavailable("The monitor returned an unstable brightness range. Try refreshing after it finishes changing modes.")
    }

    @MainActor static func displays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { id in
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
            let current = CGDisplayCopyDisplayMode(id)
            let currentID = current?.ioDisplayModeID ?? -1
            var candidates = rawModes(id)
            if let current, !candidates.contains(where: { $0.ioDisplayModeID == currentID }) { candidates.append(current) }
            // Keep distinct pixel density and refresh rates, preferring the active ID among duplicates.
            var unique: [String: CGDisplayMode] = [:]
            for mode in candidates where mode.width >= 640 && mode.height >= 480 || mode.ioDisplayModeID == currentID {
                let key = "\(mode.width):\(mode.height):\(mode.pixelWidth):\(mode.pixelHeight):\(Int((mode.refreshRate * 100).rounded()))"
                if unique[key] == nil || mode.ioDisplayModeID == currentID { unique[key] = mode }
            }
            // Scaled render buffers may exceed the physical panel. Only trust an
            // unambiguous native-mode flag; CoreGraphics already rotates dimensions.
            let nativeSizes = Set(candidates.filter { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }
                .map { "\($0.pixelWidth):\($0.pixelHeight)" })
            let native = nativeSizes.count == 1 ? candidates.first { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 } : nil
            let modes = unique.values.map { mode in
                DisplayModeInfo(id: mode.ioDisplayModeID, width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
            }.sorted { lhs, rhs in
                if lhs.width != rhs.width { return lhs.width < rhs.width }
                if lhs.height != rhs.height { return lhs.height < rhs.height }
                if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
                return lhs.refreshRate > rhs.refreshRate
            }
            return DisplayInfo(id: id, stableID: stableID(id), name: screen?.localizedName ?? (CGDisplayIsBuiltin(id) != 0 ? "Built-in display" : "External display"), isBuiltin: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0, rotation: CGDisplayRotation(id), modes: modes, currentModeID: currentID, nativeWidth: native?.pixelWidth, nativeHeight: native?.pixelHeight)
        }.sorted { lhs, rhs in lhs.isBuiltin != rhs.isBuiltin ? lhs.isBuiltin : lhs.id < rhs.id }
    }

    static func stableID(_ id: UInt32) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func rawModes(_ id: UInt32) -> [CGDisplayMode] {
        CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
    }

    /// CoreGraphics sentinel IDs can report truthy status for invalid displays.
    /// Explicit membership prevents sentinels reaching any mutation API.
    private static func isConnected(_ id: UInt32) -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains(id)
    }

    static func setMode(displayID: UInt32, modeID: Int32) throws {
        guard isConnected(displayID) else { throw DisplayBackendError.unavailable("This display is disconnected. Reconnect it and try again.") }
        let availableModes = rawModes(displayID)
        guard let current = CGDisplayCopyDisplayMode(displayID), availableModes.contains(where: { $0.ioDisplayModeID == current.ioDisplayModeID }) else {
            throw DisplayBackendError.unavailable("The current custom resolution cannot be restored safely by macOS. Choose a standard resolution in System Settings before changing it here.")
        }
        guard let mode = availableModes.first(where: { $0.ioDisplayModeID == modeID }) else { throw DisplayBackendError.unavailable("This resolution is no longer available. Choose another display mode.") }
        try configure { config in CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil) }
    }

    static func setMain(displayID: UInt32) throws {
        guard isConnected(displayID), CGDisplayIsActive(displayID) != 0 else { throw DisplayBackendError.unavailable("Only an active display can be the main display.") }
        let origin = CGDisplayBounds(displayID).origin
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { throw DisplayBackendError.unavailable("Could not read the display arrangement.") }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { throw DisplayBackendError.unavailable("Could not read the display arrangement.") }
        try configure { config in
            for id in ids.prefix(Int(count)) {
                let old = CGDisplayBounds(id).origin
                let result = CGConfigureDisplayOrigin(config, id, Int32(old.x - origin.x), Int32(old.y - origin.y))
                if result != .success { return result }
            }
            return .success
        }
    }

    private static func configure(_ change: (CGDisplayConfigRef?) -> CGError) throws {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { throw DisplayBackendError.configuration(begin) }
        let result = change(config)
        guard result == .success else { CGCancelDisplayConfiguration(config); throw DisplayBackendError.configuration(result) }
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else { throw DisplayBackendError.configuration(complete) }
    }

    static func brightness(displayID: UInt32) -> BrightnessStatus {
        guard isConnected(displayID) else { return BrightnessStatus(value: nil, isHardware: false, detail: "Display disconnected") }
        if CGDisplayIsBuiltin(displayID) != 0 {
            do {
                let value: Float = try withDisplayServices { handle in
                    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
                    guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { throw DisplayBackendError.unavailable("Built-in brightness is unavailable on this macOS version.") }
                    var result: Float = 0
                    guard unsafeBitCast(symbol, to: Get.self)(displayID, &result) == 0 else { throw DisplayBackendError.unavailable("macOS could not read this display’s brightness.") }
                    return result
                }
                return BrightnessStatus(value: min(1, max(0, Double(value))), isHardware: true, detail: "Built-in hardware brightness")
            } catch { return BrightnessStatus(value: nil, isHardware: false, detail: error.localizedDescription) }
        }
        do {
            let maximum = try brightnessMaximum(displayID)
            let started = Date()
            var lastError: Error = DisplayBackendError.unavailable("The monitor returned an invalid brightness reading.")
            // Mode changes can briefly corrupt DDC replies. Retry short failures,
            // but don't repeatedly wait for a helper that has already timed out.
            for attempt in 0..<3 {
                do {
                    let current = try ddcNumber(displayID, operation: "get")
                    guard current >= 0, current <= maximum else { throw DisplayBackendError.unavailable("The monitor returned an invalid brightness reading.") }
                    return BrightnessStatus(value: current / maximum, isHardware: true, detail: "DDC hardware brightness")
                } catch { lastError = error }
                if Date().timeIntervalSince(started) > 1 || attempt == 2 { break }
                Thread.sleep(forTimeInterval: 0.15)
            }
            throw lastError
        } catch { return BrightnessStatus(value: nil, isHardware: false, detail: error.localizedDescription) }
    }

    static func setBrightness(displayID: UInt32, value: Double) throws {
        guard value.isFinite else { throw DisplayBackendError.unavailable("Brightness must be a finite number.") }
        guard isConnected(displayID) else { throw DisplayBackendError.unavailable("This display is disconnected.") }
        let bounded = min(1, max(0, value))
        if CGDisplayIsBuiltin(displayID) != 0 {
            try withDisplayServices { handle in
                typealias Set = @convention(c) (UInt32, Float) -> Int32
                guard let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { throw DisplayBackendError.unavailable("Built-in brightness is unavailable on this macOS version.") }
                guard unsafeBitCast(symbol, to: Set.self)(displayID, Float(bounded)) == 0 else { throw DisplayBackendError.unavailable("macOS could not change this display’s brightness.") }
            }
        } else {
            let maximum = try brightnessMaximum(displayID)
            guard maximum > 0 else { throw DisplayBackendError.unavailable("The monitor returned an invalid brightness range.") }
            _ = try runDDC(["display", "id=\(displayID)", "set", "luminance", String(Int((bounded * maximum).rounded()))])
        }
    }

    private static func withDisplayServices<T>(_ body: (UnsafeMutableRawPointer) throws -> T) throws -> T {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { throw DisplayBackendError.unavailable("Built-in brightness services are unavailable.") }
        defer { dlclose(handle) }
        return try body(handle)
    }

    private static func ddcNumber(_ id: UInt32, operation: String) throws -> Double {
        let output = try runDDC(["display", "id=\(id)", operation, "luminance"])
        guard let number = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else { throw DisplayBackendError.unavailable("This monitor did not respond to DDC. Enable DDC/CI in the monitor’s menu and check its cable.") }
        return number
    }

    private static func runDDC(_ arguments: [String]) throws -> String {
        let paths = [Bundle.main.resourceURL?.appendingPathComponent("m1ddc").path, "\(FileManager.default.currentDirectoryPath)/Vendor/m1ddc/m1ddc", "/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"].compactMap { $0 }
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw DisplayBackendError.unavailable("The DDC helper is missing. Rebuild or reinstall Display Wizard.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            // A stuck driver must not permanently occupy the brightness queue.
            usleep(50_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw DisplayBackendError.unavailable("The monitor took too long to respond. Check DDC/CI and reconnect its cable.")
        }
        guard process.terminationStatus == 0 else { throw DisplayBackendError.unavailable("This monitor did not respond to DDC. Enable DDC/CI in its menu and check the connection.") }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
