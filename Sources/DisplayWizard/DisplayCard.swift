import SwiftUI
import AppKit

struct DisplayCard: View {
    @ObservedObject var model: AppModel
    let display: DisplayInfo
    private var currentMode: DisplayModeInfo? { display.modes.first { $0.id == display.currentModeID } }
    private var favorites: [FavoriteResolution] { model.preferences.favoriteResolutions[display.stableID] ?? [] }
    private var currentIsFavorite: Bool { currentMode.map { favorites.contains(FavoriteResolution(mode: $0)) } ?? false }
    private func toggleCurrentFavorite() {
        guard let currentMode else { return }
        let favorite = FavoriteResolution(mode: currentMode)
        var updated = favorites
        if updated.contains(favorite) { updated.removeAll { $0 == favorite } }
        else { updated.append(favorite) }
        model.preferences.favoriteResolutions[display.stableID] = updated
        model.save()
    }
    private var scalingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Display scale").wizardFont(size: 12, weight: .medium).help("1× uses native pixels. Higher scales make the interface larger. Approximate values reflect available macOS modes.")
                Spacer(minLength: 8)
                if let currentMode {
                    Text(ModeChoices.scaleLabel(currentMode, for: display)).wizardFont(size: 12, weight: .semibold).foregroundStyle(accent)
                }
            }
            let choices = ModeChoices.scalePresets(display)
            if !choices.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(choices.count, model.preferences.textSize == .standard ? 5 : 3)), spacing: 8) {
                    ForEach(choices) { mode in
                        let selected = mode.id == display.currentModeID
                        Button { model.changeMode(mode.id, for: display) } label: {
                            Text(ModeChoices.scaleLabel(mode, for: display))
                                .wizardFont(size: 11, weight: selected ? .semibold : .medium)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(selected ? accent.opacity(0.18) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? accent : Color.primary.opacity(0.07), lineWidth: 1) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(selected ? accent : .primary)
                            .accessibilityLabel("\(display.name) scale \(ModeChoices.scaleLabel(mode, for: display))")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .help(ModeChoices.exactLabel(mode, for: display))
                    }
                }
            }
        }
    }
    private var optionsMenu: some View {
        Menu {
            if let currentMode { Text(ModeChoices.exactLabel(currentMode, for: display)) }
            Menu("Exact resolutions") {
                ForEach(ModeChoices.grouped(display)) { mode in
                    Button("\(mode.id == display.currentModeID ? "✓ " : "")\(ModeChoices.exactLabel(mode, for: display))") { model.changeMode(mode.id, for: display) }
                }
            }
            Menu("Favorites") {
                Button(currentIsFavorite ? "Unfavorite current resolution" : "Favorite current resolution", action: toggleCurrentFavorite)
                    .disabled(currentMode == nil)
                let available = ModeChoices.favorites(favorites, for: display)
                if !available.isEmpty { Divider() }
                ForEach(available) { mode in
                    Button("\(mode.id == display.currentModeID ? "✓ " : "")\(ModeChoices.exactLabel(mode, for: display))") { model.changeMode(mode.id, for: display) }
                }
            }
            Menu("Refresh rate") {
                ForEach(display.modes.filter { $0.width == currentMode?.width && $0.height == currentMode?.height && $0.isHiDPI == currentMode?.isHiDPI }) { mode in
                    Button("\(mode.id == display.currentModeID ? "✓ " : "")\(ModeChoices.refreshLabel(mode.refreshRate))") { model.changeMode(mode.id, for: display) }
                }
            }
            Divider()
            if !display.isMain { Button("Make main display") { model.makeMain(display) } }
            Button("Rotation: \(Int(display.rotation))°…") {
                SystemSettings.openDisplays()
            }
        } label: {
            Image(systemName: "ellipsis").wizardFont(size: 16, weight: .semibold)
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("\(display.name) options").help("Resolution, favorites, refresh rate and display options")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display").wizardFont(size: 20, weight: .light).foregroundStyle(accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(display.name).wizardFont(size: 14, weight: .semibold).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(display.isBuiltin ? "Built-in" : "External")
                        Text("·")
                        Text(display.isMain ? "Main display" : (display.rotation == 90 || display.rotation == 270 ? "Portrait" : "Extended"))
                    }.wizardFont(size: 10).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                optionsMenu
            }
            VStack(spacing: 9) {
                HStack {
                    Text("Brightness").wizardFont(size: 12, weight: .medium)
                    Spacer()
                    Text(model.brightness[display.id].map { "\(Int(($0 * 100).rounded()))%" } ?? "Unavailable").wizardFont(size: 12, weight: .medium, design: .monospaced).foregroundStyle(model.brightness[display.id] == nil ? .secondary : accent)
                }
                HStack(spacing: 10) {
                    Image(systemName: "sun.min").wizardFont(size: 12).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { model.brightness[display.id] ?? 0 }, set: { model.setBrightness($0, for: display) }), in: 0...1).disabled(model.brightness[display.id] == nil).accessibilityLabel("\(display.name) brightness")
                    Image(systemName: "sun.max.fill").wizardFont(size: 13).foregroundStyle(.secondary)
                }
                if model.brightness[display.id] == nil || model.brightnessDetails[display.id]?.hasPrefix("Last known") == true { Text(model.brightnessDetails[display.id] ?? "Hardware brightness is unavailable.").wizardFont(size: 10).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            }
            scalingControls
        }.padding(16).background(surface, in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.065), lineWidth: 1) }
    }
}
