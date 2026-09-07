import Foundation

struct SavedDisplay: Codable, Equatable {
    var stableID: String
    var brightness: Double?
    var width: Int
    var height: Int
    var pixelWidth: Int
    var refreshRate: Double
}
struct DisplayPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var displays: [SavedDisplay]
}
/// A resolution favorite survives reconnects and macOS mode-ID changes.
struct FavoriteResolution: Codable, Hashable {
    var width: Int
    var height: Int
    var isHiDPI: Bool

    init(width: Int, height: Int, isHiDPI: Bool) {
        self.width = width
        self.height = height
        self.isHiDPI = isHiDPI
    }
    init(mode: DisplayModeInfo) {
        self.init(width: mode.width, height: mode.height, isHiDPI: mode.isHiDPI)
    }
}

struct Preferences: Codable {
    var presets: [DisplayPreset] = []
    var restoreOnReconnect = false
    var lastDisplays: [SavedDisplay] = []
    var textSize: AppTextSize = .standard
    var linkedBrightness = false
    var matchedBrightness = false
    var brightnessMatchGains: [String: Double] = [:]
    var brightnessMatchLevels: [String: Double] = [:]
    var brightnessMatchReference: String?
    var favoriteResolutions: [String: [FavoriteResolution]] = [:]

    var brightnessLinkStatus: String {
        guard linkedBrightness else { return "Linking paused" }
        guard matchedBrightness else { return "Linked · percentage offsets" }
        return brightnessMatchGains.isEmpty ? "Matched · estimated brightness" : "Matched · visual calibration"
    }

    init() {}
    private enum CodingKeys: String, CodingKey {
        case textSize, presets, restoreOnReconnect, lastDisplays, linkedBrightness, favoriteResolutions, matchedBrightness, brightnessMatchGains, brightnessMatchLevels, brightnessMatchReference
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        textSize = (try? values.decodeIfPresent(AppTextSize.self, forKey: .textSize)) ?? .standard
        presets = try values.decodeIfPresent([DisplayPreset].self, forKey: .presets) ?? []
        restoreOnReconnect = try values.decodeIfPresent(Bool.self, forKey: .restoreOnReconnect) ?? false
        lastDisplays = try values.decodeIfPresent([SavedDisplay].self, forKey: .lastDisplays) ?? []
        linkedBrightness = try values.decodeIfPresent(Bool.self, forKey: .linkedBrightness) ?? false
        matchedBrightness = try values.decodeIfPresent(Bool.self, forKey: .matchedBrightness) ?? false
        brightnessMatchLevels = try values.decodeIfPresent([String: Double].self, forKey: .brightnessMatchLevels) ?? [:]
        brightnessMatchReference = try values.decodeIfPresent(String.self, forKey: .brightnessMatchReference)
        brightnessMatchGains = try values.decodeIfPresent([String: Double].self, forKey: .brightnessMatchGains) ?? [:]
        favoriteResolutions = try values.decodeIfPresent([String: [FavoriteResolution]].self, forKey: .favoriteResolutions) ?? [:]
    }

    static func load(from url: URL = fileURL) -> Preferences {
        guard let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return result
    }
    func save(to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DisplayWizard/preferences.json")
    }
}
