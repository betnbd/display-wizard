import Foundation
import Testing
@testable import DisplayWizard

@MainActor private final class FakeDisplays {
    static let display = DisplayInfo(id: 1, stableID: "test-display", name: "Test display", isBuiltin: true, isMain: true, rotation: 0, modes: [DisplayModeInfo(id: 1, width: 100, height: 100, pixelWidth: 200, pixelHeight: 200, refreshRate: 60)], currentModeID: 1)
    var connected = [display]
    var level: Double? = 0.4
    var fails = false
    var writes: [Double] = []
    var modes: [Int32] = []
    var saved: Preferences?
    var services: AppModelServices {
        AppModelServices(displays: { self.connected }, profile: { _ in BrightnessProfile(minimumNits: 0, maximumNits: 500, sourceDescription: "Test") }, brightness: { _ in BrightnessStatus(value: self.level, isHardware: true, detail: "Test read") }, setBrightness: { _, value in
            self.writes.append(value)
            if self.fails { throw DisplayBackendError.unavailable("Simulated failure") }
            self.level = value
        }, setMode: { _, mode in self.modes.append(mode) }, save: { self.saved = $0 })
    }
    func model(_ preferences: Preferences = Preferences()) async -> AppModel {
        let model = AppModel(services: services, preferences: preferences, observeSystem: false)
        await Task.yield()
        return model
    }
}

@MainActor struct AppModelRecoveryTests {
    @Test func disconnectedWriteIsCancelledAndCannotBlockFutureMatch() async throws {
        let fake = FakeDisplays()
        let model = await fake.model()
        model.setBrightness(0.8, for: FakeDisplays.display)
        fake.connected = []
        model.refresh()
        try await Task.sleep(for: .milliseconds(160))
        #expect(fake.writes.isEmpty)
        #expect(model.brightness.isEmpty)
        #expect(model.matchUnavailableReason == "Connect a second display to match brightness.")
    }

    @Test func failedWriteDropsOptimisticValueAndDisablesMatchedLink() async throws {
        let fake = FakeDisplays()
        var preferences = Preferences()
        preferences.linkedBrightness = true
        preferences.matchedBrightness = true
        let model = await fake.model(preferences)
        fake.fails = true
        fake.level = nil
        model.setBrightness(0.9, for: FakeDisplays.display)
        try await Task.sleep(for: .milliseconds(180))
        #expect(model.brightness[1] == nil)
        #expect(!model.preferences.matchedBrightness)
        #expect(!model.preferences.linkedBrightness)
        #expect(model.notice?.contains("Simulated failure") == true)
        #expect(fake.saved?.lastDisplays.first?.brightness != 0.9)
    }

    @Test func wakeRestorationRequiresOptInAndUsesSavedBrightness() async throws {
        let fake = FakeDisplays()
        var preferences = Preferences()
        preferences.lastDisplays = [SavedDisplay(stableID: "test-display", brightness: 0.7, width: 100, height: 100, pixelWidth: 200, refreshRate: 60)]
        preferences.restoreOnReconnect = false
        let model = await fake.model(preferences)
        model.refresh(restoreAfterWake: true)
        await Task.yield()
        #expect(fake.writes.isEmpty)
        model.preferences.restoreOnReconnect = true
        model.refresh(restoreAfterWake: true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(fake.writes == [0.7])
        #expect(model.brightness[1] == 0.7)
    }

    @Test func resolutionPreviewRevertsAndDisconnectClearsTimer() async {
        let fake = FakeDisplays()
        let model = await fake.model()
        model.changeMode(2, for: FakeDisplays.display)
        #expect(model.pendingMode?.original == 1)
        model.revertMode()
        #expect(fake.modes == [2, 1])
        #expect(model.pendingMode == nil)
        model.changeMode(3, for: FakeDisplays.display)
        fake.connected = []
        model.refresh()
        #expect(model.pendingMode == nil)
        model.revertMode()
        #expect(fake.modes == [2, 1, 3])
    }

    @Test func matchWhileWritingExplainsWhyItCannotStart() async {
        let fake = FakeDisplays()
        let model = await fake.model()
        model.setBrightness(0.5, for: FakeDisplays.display)
        model.matchBrightness()
        #expect(model.notice?.contains("Wait for the current brightness adjustment") == true)
        #expect(!model.matchingInProgress)
        fake.connected = []
        model.refresh()
    }
}
