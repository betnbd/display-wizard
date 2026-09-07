import Foundation
import Testing
@testable import DisplayWizard

struct AppTextSizeTests {
    @Test func oldAndUnknownPreferencesKeepDefaults() throws {
        for json in ["{}", "{\"textSize\":\"future-size\"}"] {
            let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
            #expect(preferences.textSize == .standard)
        }
    }
    @Test func readingSizePersistsWithoutChangingBrightnessOptions() throws {
        var preferences = Preferences()
        preferences.textSize = .largest
        preferences.linkedBrightness = true
        preferences.matchedBrightness = true
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored.textSize == .largest)
        #expect(restored.linkedBrightness && restored.matchedBrightness)
    }
}
