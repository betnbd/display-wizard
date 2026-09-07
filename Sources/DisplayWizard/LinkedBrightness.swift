import Foundation

/// Applies one bounded percentage-point offset so linked displays retain their
/// relative brightness, including when the brightest/dimmest reaches a limit.
enum LinkedBrightness {
    static func targets(current: [UInt32: Double], source: UInt32, requested: Double, linked: Bool) -> [UInt32: Double] {
        guard requested.isFinite, let sourceValue = current[source], sourceValue.isFinite else { return [:] }
        let available = current.filter { $0.value.isFinite && (0...1).contains($0.value) }
        guard available[source] != nil else { return [:] }
        let bounded = min(1, max(0, requested))
        guard linked else { return [source: bounded] }
        guard let minimum = available.values.min(), let maximum = available.values.max() else { return [:] }
        let delta = min(1 - maximum, max(-minimum, bounded - sourceValue))
        return available.mapValues { min(1, max(0, $0 + delta)) }
    }
}
