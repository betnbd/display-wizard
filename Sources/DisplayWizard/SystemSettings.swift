import AppKit

@MainActor enum SystemSettings {
    static func openTextSize() {
        open("x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display")
    }
    static func openDisplays() {
        open("x-apple.systempreferences:com.apple.Displays-Settings.extension")
    }
    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
