import Foundation

/// Resolution menus preserve the current refresh rate where possible.
enum ModeChoices {
    static func refreshLabel(_ value: Double) -> String {
        guard value > 0 else { return "Adaptive" }
        return abs(value - value.rounded()) < 0.01 ? "\(Int(value.rounded())) Hz" : String(format: "%.2f Hz", value)
    }

    static func grouped(_ display: DisplayInfo) -> [DisplayModeInfo] {
        let current = display.modes.first { $0.id == display.currentModeID }
        let groups = Dictionary(grouping: display.modes) { "\($0.width):\($0.height):\($0.isHiDPI)" }
        return groups.values.compactMap { modes in
            modes.min { lhs, rhs in
                if lhs.id == display.currentModeID { return true }
                if rhs.id == display.currentModeID { return false }
                let target = current?.refreshRate ?? 60
                return abs(lhs.refreshRate - target) < abs(rhs.refreshRate - target)
            }
        }.sorted { $0.width != $1.width ? $0.width < $1.width : $0.pixelWidth > $1.pixelWidth }
    }
    /// Scale is physical panel pixels per logical pixel, not render-buffer density.
    static func scale(_ mode: DisplayModeInfo, for display: DisplayInfo) -> Double? {
        guard let width = display.nativeWidth, let height = display.nativeHeight,
              width > 0, height > 0, mode.width > 0, mode.height > 0 else { return nil }
        let horizontal = Double(width) / Double(mode.width)
        let vertical = Double(height) / Double(mode.height)
        // Do not assign one scale to letterboxed or stretched aspect ratios.
        guard abs(horizontal / vertical - 1) < 0.015 else { return nil }
        return horizontal
    }

    static func scaleLabel(_ mode: DisplayModeInfo, for display: DisplayInfo) -> String {
        guard let value = scale(mode, for: display) else { return "\(mode.width) × \(mode.height)" }
        let rounded = (value * 100).rounded() / 100
        let number = String(format: "%.2f", rounded).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return (abs(value - rounded) > 0.0001 ? "≈" : "") + number + "×"
    }

    static func exactLabel(_ mode: DisplayModeInfo, for display: DisplayInfo) -> String {
        let resolution = "\(mode.width) × \(mode.height)"
        guard let value = scale(mode, for: display) else { return mode.label }
        let percent = value * 100
        let approximation = abs(percent - percent.rounded()) > 0.05 ? "≈" : ""
        return resolution + " (\(approximation)\(Int(percent.rounded()))%)" + (mode.isHiDPI ? " · HiDPI" : "")
    }

    /// Each benchmark selects a real available mode within 6%, retaining its
    /// actual scale label. Equal logical sizes prefer HiDPI, then active refresh.
    static func scalePresets(_ display: DisplayInfo) -> [DisplayModeInfo] {
        let candidates = grouped(display).filter { scale($0, for: display) != nil }
        var seen: Set<Int32> = []
        let choices = [1.0, 1.25, 1.5, 1.75, 2.0].compactMap { benchmark -> DisplayModeInfo? in
            let nearby = candidates.filter { abs(scale($0, for: display)! / benchmark - 1) <= 0.06 }
            guard let best = nearby.min(by: { lhs, rhs in
                let left = abs(scale(lhs, for: display)! - benchmark)
                let right = abs(scale(rhs, for: display)! - benchmark)
                if abs(left - right) > 0.00001 { return left < right }
                if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
                if lhs.id == display.currentModeID { return true }
                if rhs.id == display.currentModeID { return false }
                return lhs.id < rhs.id
            }), seen.insert(best.id).inserted else { return nil }
            return best
        }
        return choices.sorted { scale($0, for: display)! < scale($1, for: display)! }
    }

    static func favorites(_ favorites: [FavoriteResolution], for display: DisplayInfo) -> [DisplayModeInfo] {
        let grouped = grouped(display)
        // Unavailable favorites stay saved so they return with the same display
        // connection, but only currently selectable modes appear in the menu.
        var seen: Set<FavoriteResolution> = []
        return favorites.compactMap { favorite in
            guard seen.insert(favorite).inserted else { return nil }
            return grouped.first { FavoriteResolution(mode: $0) == favorite }
        }
    }

}
