import SwiftUI

struct WizardSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var login = LoginItemManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Button("System text size…") { SystemSettings.openTextSize() }
                    .wizardFont(size: 13, weight: .medium).controlSize(.large)
                Text("Opens macOS Accessibility → Display. Text size affects supported apps and system features.")
                    .wizardFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Wizard text size").wizardFont(size: 12, weight: .medium)
                    Picker("Display Wizard text size", selection: $model.preferences.textSize) {
                        ForEach(AppTextSize.allCases, id: \.self) { size in Text(size.title).tag(size) }
                    }.pickerStyle(.segmented).labelsHidden().controlSize(.large)
                        .onChange(of: model.preferences.textSize) { _, _ in model.save() }
                    Text("Only changes text in this app.").wizardFont(size: 11).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.wizardFont(size: 13)
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                .wizardFont(size: 13).controlSize(.large).frame(minHeight: 36)
            if login.needsApproval {
                Button("Allow in Login Items…") { login.openSettings() }.wizardFont(size: 11)
            }
            Text(login.statusText).wizardFont(size: 11).foregroundStyle(.secondary)
            Divider()
            Toggle("Restore brightness on wake & reconnect", isOn: $model.preferences.restoreOnReconnect).wizardFont(size: 13).controlSize(.large).frame(minHeight: 36).onChange(of: model.preferences.restoreOnReconnect) { _, _ in model.remember() }
            Text("Restores saved brightness after sleep or reconnecting a display while the app is running.").wizardFont(size: 11).foregroundStyle(.secondary)
            Divider()
            Text("Keyboard: ⌃⌥↑ / ↓ adjusts the display under your pointer, or supported displays together when linked. Shortcuts work while the app is running.").wizardFont(size: 11).foregroundStyle(.secondary)
            Button("Open macOS Display Settings") { SystemSettings.openDisplays() }.wizardFont(size: 13).controlSize(.large)
        }.padding(14).background(surface, in: RoundedRectangle(cornerRadius: 12)).onAppear { login.refresh() }
    }
}
