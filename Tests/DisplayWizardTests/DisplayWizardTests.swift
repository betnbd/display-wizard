import Foundation
import Testing
@testable import DisplayWizard

struct PreferencesTests {
    @Test func roundTripPreservesPresetIdentityAndDisconnectedDisplay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/preferences.json")
        let connected = SavedDisplay(stableID: "display-one", brightness: 0.32, width: 1692, height: 3008, pixelWidth: 3384, refreshRate: 120)
        let disconnected = SavedDisplay(stableID: "display-two", brightness: nil, width: 1512, height: 982, pixelWidth: 3024, refreshRate: 60)
        let preset = DisplayPreset(name: "Evening 🌙", displays: [connected, disconnected])
        var preferences = Preferences()
        preferences.presets = [preset]
        preferences.restoreOnReconnect = true
        preferences.lastDisplays = [connected, disconnected]
        try preferences.save(to: url)
        let loaded = Preferences.load(from: url)
        #expect(loaded.presets == [preset])
        #expect(loaded.restoreOnReconnect)
        #expect(loaded.lastDisplays == [connected, disconnected])
    }

    @Test func missingAndInvalidPreferencesUseSafeDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Preferences.load(from: url).presets.isEmpty)
        try Data("invalid JSON".utf8).write(to: url)
        let loaded = Preferences.load(from: url)
        #expect(!loaded.restoreOnReconnect)
        #expect(loaded.lastDisplays.isEmpty)
    }

    @Test func atomicSaveReplacesPreviousPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        var preferences = Preferences()
        preferences.presets = [DisplayPreset(name: "Old", displays: [])]
        try preferences.save(to: url)
        preferences.presets = []
        preferences.restoreOnReconnect = true
        try preferences.save(to: url)
        #expect(Preferences.load(from: url).presets.isEmpty)
        #expect(Preferences.load(from: url).restoreOnReconnect)
    }
}

struct DisplayBackendTests {
    @Test func rejectsInvalidBrightnessBeforeHardwareAccess() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) { try DisplayBackend.setBrightness(displayID: UInt32.max, value: value) }
        }
    }

    @Test func disconnectedDisplayOperationsFailWithoutMutation() {
        #expect(throws: (any Error).self) { try DisplayBackend.setMode(displayID: UInt32.max, modeID: -1) }
        #expect(throws: (any Error).self) { try DisplayBackend.setMain(displayID: UInt32.max) }
        #expect(throws: (any Error).self) { try DisplayBackend.setBrightness(displayID: UInt32.max, value: 0.5) }
        #expect(DisplayBackend.brightness(displayID: UInt32.max).value == nil)
    }

    @Test @MainActor func connectedDisplayEnumerationInvariants() {
        let displays = DisplayBackend.displays()
        #expect(Set(displays.map(\.id)).count == displays.count)
        for display in displays {
            #expect(!display.stableID.isEmpty)
            #expect(!display.name.isEmpty)
            #expect(display.modes.contains { $0.id == display.currentModeID })
            #expect(Set(display.modes.map(\.id)).count == display.modes.count)
            for mode in display.modes {
                #expect(mode.width > 0 && mode.height > 0 && mode.pixelWidth > 0)
                #expect(mode.refreshRate >= 0)
            }
        }
    }

    @Test func hiDPILabelIsBasedOnPixelDensity() {
        let retina = DisplayModeInfo(id: 1, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60)
        let standard = DisplayModeInfo(id: 2, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60)
        #expect(retina.isHiDPI && retina.label.contains("HiDPI"))
        #expect(!standard.isHiDPI && !standard.label.contains("HiDPI"))
    }

    @Test func hardwareServicePropagatesErrorsAsynchronously() async {
        await #expect(throws: (any Error).self) { try await HardwareService.shared.setBrightness(displayID: UInt32.max, value: .nan) }
        let result = await HardwareService.shared.brightness(displayID: UInt32.max)
        #expect(result.value == nil)
    }
}

struct ModeChoicesTests {
    private func display(modes: [DisplayModeInfo], current: Int32) -> DisplayInfo {
        DisplayInfo(id: 42, stableID: "test", name: "Test", isBuiltin: false, isMain: false, rotation: 0, modes: modes, currentModeID: current)
    }
    private func mode(_ id: Int32, _ width: Int, _ refresh: Double, hiDPI: Bool = true) -> DisplayModeInfo {
        DisplayModeInfo(id: id, width: width, height: width * 9 / 16, pixelWidth: width * (hiDPI ? 2 : 1), pixelHeight: width * 9 / 16 * (hiDPI ? 2 : 1), refreshRate: refresh)
    }
    @Test func groupedPreservesCurrentRefreshRate() {
        let modes = [mode(1, 1920, 120), mode(2, 1920, 60), mode(3, 2560, 60), mode(4, 2560, 120)]
        let grouped = ModeChoices.grouped(display(modes: modes, current: 1))
        #expect(grouped.map(\.id) == [1, 4])
    }
}
