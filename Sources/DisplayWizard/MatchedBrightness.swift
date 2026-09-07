import Foundation

/// Equalizes estimated luminance, not raw percentages. Visual gains refine the
/// estimate; a colorimeter would be needed for a measured physical match.
enum MatchedBrightness {
    static func validGain(_ value: Double?) -> Double {
        guard let value, value.isFinite, (0.05...20).contains(value) else { return 1 }
        return value
    }
    static func calibratedGains(profiles: [UInt32: BrightnessProfile], levels: [UInt32: Double], reference: UInt32) -> [UInt32: Double]? {
        guard let profile = profiles[reference], let level = levels[reference], level.isFinite, (0...1).contains(level) else { return nil }
        let referenceNits = profile.estimatedNits(level: level)
        guard referenceNits > 0 else { return nil }
        var result: [UInt32: Double] = [:]
        for (id, profile) in profiles {
            guard let level = levels[id], level.isFinite, (0...1).contains(level) else { continue }
            let nits = profile.estimatedNits(level: level)
            guard nits > 0, (0.05...20).contains(referenceNits / nits) else { return nil }
            result[id] = referenceNits / nits
        }
        return result.count >= 2 ? result : nil
    }
    static func targets(profiles: [UInt32: BrightnessProfile], gains: [UInt32: Double], source: UInt32, requested: Double) -> [UInt32: Double] {
        guard profiles.count >= 2, requested.isFinite, let reference = profiles[source] else { return [:] }
        let minimum = profiles.map { $0.value.minimumNits * validGain(gains[$0.key]) }.max() ?? 0
        let maximum = profiles.map { $0.value.maximumNits * validGain(gains[$0.key]) }.min() ?? 0
        guard maximum.isFinite, minimum.isFinite, maximum > minimum else { return [:] }
        let desired = reference.estimatedNits(level: min(1, max(0, requested))) * validGain(gains[source])
        let shared = min(maximum, max(minimum, desired))
        return profiles.mapValuesWithKey { id, profile in
            profile.level(forNits: shared / validGain(gains[id]))
        }
    }
}

private extension Dictionary {
    func mapValuesWithKey<T>(_ transform: (Key, Value) -> T) -> [Key: T] {
        Dictionary<Key, T>(uniqueKeysWithValues: map { ($0.key, transform($0.key, $0.value)) })
    }
}
