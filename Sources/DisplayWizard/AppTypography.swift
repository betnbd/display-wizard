import SwiftUI

/// App-only reading size; system text settings are managed by macOS.
enum AppTextSize: String, Codable, CaseIterable {
    case standard, larger, largest
    var title: String { self == .standard ? "Default" : (self == .larger ? "Larger" : "Largest") }
    var factor: CGFloat { self == .standard ? 1 : (self == .larger ? 1.18 : 1.36) }
}

private struct WizardTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}
extension EnvironmentValues {
    var wizardTextScale: CGFloat {
        get { self[WizardTextScaleKey.self] }
        set { self[WizardTextScaleKey.self] = newValue }
    }
}
private struct WizardFont: ViewModifier {
    @Environment(\.wizardTextScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}
extension View {
    func wizardFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(WizardFont(size: size, weight: weight, design: design))
    }
}

// Explicit alias avoids an SDK macro requiring full Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>
let accent = Color(nsColor: .controlAccentColor)
let surface = Color(nsColor: .controlBackgroundColor)
