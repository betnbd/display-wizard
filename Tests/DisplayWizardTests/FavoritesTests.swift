import Foundation
import Testing
@testable import DisplayWizard

struct FavoritesTests {
    @Test func oldPreferencesMigrateWithoutLosingSavedData() throws {
        let oldJSON = """
        {"presets":[{"id":"00000000-0000-0000-0000-000000000001","name":"Evening","displays":[]}],"restoreOnReconnect":true,"lastDisplays":[{"stableID":"dell","brightness":0.32,"width":1692,"height":3008,"pixelWidth":3384,"refreshRate":120}]}
        """
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(oldJSON.utf8))
        #expect(preferences.presets.first?.name == "Evening")
        #expect(preferences.lastDisplays.first?.brightness == 0.32)
        #expect(preferences.restoreOnReconnect)
        #expect(!preferences.linkedBrightness)
        #expect(preferences.favoriteResolutions.isEmpty)
    }

    @Test func favoritesAndLinkPreferencePersistPerDisplay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        var preferences = Preferences()
        preferences.linkedBrightness = true
        preferences.favoriteResolutions = ["dell": [FavoriteResolution(width: 1692, height: 3008, isHiDPI: true)], "builtin": [FavoriteResolution(width: 1512, height: 982, isHiDPI: true)]]
        try preferences.save(to: url)
        let loaded = Preferences.load(from: url)
        #expect(loaded.linkedBrightness)
        #expect(loaded.favoriteResolutions == preferences.favoriteResolutions)
    }

    @Test func favoriteMatchingIgnoresIDsAndPreservesRefreshRate() {
        let modes = [
            DisplayModeInfo(id: 42, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 120),
            DisplayModeInfo(id: 50, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60),
            DisplayModeInfo(id: 51, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 120),
            DisplayModeInfo(id: 52, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 120)
        ]
        let display = DisplayInfo(id: 5, stableID: "dell", name: "Dell", isBuiltin: false, isMain: false, rotation: 0, modes: modes, currentModeID: 42)
        let favorite = FavoriteResolution(width: 2560, height: 1440, isHiDPI: true)
        let unavailable = FavoriteResolution(width: 5000, height: 3000, isHiDPI: true)
        let saved = [favorite, unavailable, favorite]
        #expect(ModeChoices.favorites(saved, for: display).map(\.id) == [51])
        #expect(saved.count == 3)
    }

    @Test func emptyJSONGetsAllPreferenceDefaults() throws {
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(preferences.presets.isEmpty && preferences.lastDisplays.isEmpty)
        #expect(!preferences.restoreOnReconnect && !preferences.linkedBrightness)
        #expect(preferences.favoriteResolutions.isEmpty)
    }
}
