import SwiftUI
import AppKit

// Explicit alias avoids the new SDK macro requiring full Xcode.

@MainActor final class WizardViewSession: ObservableObject {
    @Published var presetName = ""
    @Published var addingPreset = false
    @Published var showSettings = false
    @Published var showMatchTuning = false
}

struct WizardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var session: WizardViewSession
    var height: CGFloat = 660
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(session.showSettings ? "Settings" : "Your displays").wizardFont(size: 12, weight: .semibold).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.displays.count) connected").wizardFont(size: 11).foregroundStyle(.secondary)
                        Button { model.refresh() } label: {
                            Image(systemName: "arrow.clockwise").frame(width: 32, height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Refresh displays").accessibilityLabel("Refresh displays")
                    }
                    if !session.showSettings {
                        VStack(alignment: .leading, spacing: 8) {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { linkToggle; Spacer(minLength: 0); matchButton }
                                VStack(alignment: .leading, spacing: 8) { linkToggle; matchButton }
                            }
                            if model.preferences.linkedBrightness || model.preferences.matchedBrightness || session.showMatchTuning {
                                HStack {
                                    Text(model.preferences.brightnessLinkStatus).wizardFont(size: 11).foregroundStyle(.secondary)
                                    Spacer()
                                    if model.preferences.matchedBrightness || session.showMatchTuning {
                                    Button(session.showMatchTuning ? "Done" : "Fine-tune") {
                                        if !session.showMatchTuning { model.beginMatchTuning() }
                                        session.showMatchTuning.toggle()
                                    }.wizardFont(size: 11).buttonStyle(.plain).padding(6).contentShape(Rectangle())
                                    }
                                }
                            }
                            if session.showMatchTuning { matchTuning }
                        }
                    }
                    if session.showSettings {
                        WizardSettingsView(model: model)
                    } else {
                        ForEach(model.displays) { display in DisplayCard(model: model, display: display) }
                        presets
                    }
                    if model.displays.isEmpty {
                        ContentUnavailableView("No displays found", systemImage: "display", description: Text("Connect a display, then refresh."))
                    }

                }.padding(16)
            }
            if let notice = model.notice {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").foregroundStyle(accent)
                    Text(notice).wizardFont(size: 12).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { model.notice = nil } label: {
                        Image(systemName: "xmark").frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }.padding(12).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.pendingMode != nil {
                VStack(spacing: 10) {
                    Text("Keep this display mode? Reverting in \(model.countdown)s").wizardFont(size: 12, weight: .medium)
                    HStack {
                        Button("Revert") { model.revertMode() }.wizardFont(size: 12).controlSize(.large).keyboardShortcut(.cancelAction)
                        Button("Keep changes") { model.keepMode() }.wizardFont(size: 12).controlSize(.large).buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.white)
                    }
                }.padding(14).frame(maxWidth: .infinity).background(accent.opacity(0.12))
            }
            footer
        }
        .environment(\.wizardTextScale, model.preferences.textSize.factor)
        .frame(width: 370, height: height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .accentColor(accent)
    }
    private var linkToggle: some View {
        Toggle(isOn: Binding(get: { model.preferences.linkedBrightness }, set: { model.setLinkedBrightness($0) })) {
            Label("Link brightness", systemImage: "link").wizardFont(size: 12, weight: .medium)
        }.toggleStyle(.switch).controlSize(.regular).fixedSize().frame(minHeight: 36)
            .help(model.preferences.matchedBrightness ? "Linked controls match estimated brightness, using your saved visual calibration." : "Move displays by the same percentage-point offset.")
    }
    private var matchButton: some View {
        Button { model.matchBrightness() } label: {
            Label(model.matchingInProgress ? "Matching…" : "Match", systemImage: "equal.circle")
                .wizardFont(size: 12, weight: .medium).padding(.horizontal, 8).frame(minHeight: 36).contentShape(Rectangle())
        }.buttonStyle(.bordered)
            .help("Match estimated SDR brightness, then link it. Requires two supported displays. If unavailable, move MacBook brightness away from its minimum or maximum and refresh.")
    }
    private var matchTuning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare the same white content on both screens. Adjust the other display until it looks like your reference, then save.")
                .wizardFont(size: 11).foregroundStyle(.secondary)
            if let reference = model.matchReference {
                Text("Reference: \(reference.name)").wizardFont(size: 11, weight: .medium)
                ForEach(model.matchableDisplays.filter { $0.id != reference.id }) { display in
                    VStack(spacing: 6) {
                        HStack {
                            Text(display.name).lineLimit(1)
                            Spacer()
                            Text("\(Int(((model.brightness[display.id] ?? 0) * 100).rounded()))%")
                        }.wizardFont(size: 11)
                        Slider(value: Binding(get: { model.brightness[display.id] ?? 0 }, set: { model.tuneBrightness($0, for: display) }), in: 0...1)
                            .accessibilityLabel("Fine-tune \(display.name) brightness")
                    }
                }
            }
            Button("Save visual match") { if model.saveVisualMatch() { session.showMatchTuning = false } }
                .wizardFont(size: 12).controlSize(.large).disabled(!model.canSaveVisualMatch)
            Button("Use ordinary linking") {
                model.useOrdinaryLinking()
                session.showMatchTuning = false
            }.wizardFont(size: 11).buttonStyle(.plain).frame(minHeight: 30)
        }.padding(12).background(surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                if model.preferences.presets.isEmpty { Text("No saved presets") }
                ForEach(model.preferences.presets) { preset in
                    Button(preset.name) { model.applyPreset(preset) }
                }
                Divider()
                Button("Save current brightness…") { session.addingPreset = true }
                if !model.preferences.presets.isEmpty {
                    Menu("Delete preset") {
                        ForEach(model.preferences.presets) { preset in
                            Button(preset.name) { model.deletePreset(preset) }
                        }
                    }
                }
            } label: {
                Label("Brightness presets", systemImage: "sun.horizon")
                    .wizardFont(size: 12).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).accessibilityLabel("Brightness presets")
            if session.addingPreset {
                TextField("Preset name", text: $session.presetName).wizardFont(size: 12).textFieldStyle(.roundedBorder).onSubmit(savePreset)
                HStack {
                    Button("Cancel") { session.addingPreset = false; session.presetName = "" }.wizardFont(size: 12).controlSize(.large)
                    Spacer()
                    Button("Save", action: savePreset).wizardFont(size: 12).controlSize(.large).disabled(session.presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    private func savePreset() { model.savePreset(name: session.presetName); session.presetName = ""; session.addingPreset = false }
    private var footer: some View {
        HStack {
            HStack(spacing: 5) { Circle().fill(accent).frame(width: 5, height: 5); Text("Display Wizard").wizardFont(size: 10).foregroundStyle(.secondary) }
            Spacer()
            Button { session.showSettings.toggle() } label: { Label(session.showSettings ? "Displays" : "Settings", systemImage: session.showSettings ? "display" : "gearshape").wizardFont(size: 13, weight: .medium).foregroundStyle(session.showSettings ? accent : .primary).padding(.horizontal, 12).frame(height: 38).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle()) }.buttonStyle(.plain).help(session.showSettings ? "Back to displays" : "Settings").accessibilityLabel(session.showSettings ? "Back to displays" : "Settings")
            AppMenuButton { model.revertMode(); NSApp.terminate(nil) }.frame(width: 38, height: 38)
        }.padding(.horizontal, 16).padding(.vertical, 14).overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }
}
