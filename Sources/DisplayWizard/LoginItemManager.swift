import AppKit
import Combine
import ServiceManagement

/// The system registration is the source of truth; no duplicate preference is saved.
@MainActor final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var statusText = ""
    private var lastError: String?

    private init() { refresh() }

    func refresh(clearError: Bool = true) {
        if clearError { lastError = nil }
        let status = SMAppService.mainApp.status
        // Pending registration remains switchable off; the detail makes clear
        // that macOS approval is still needed before automatic launch works.
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
        if let lastError { statusText = lastError; return }
        switch status {
        case .enabled: statusText = "Starts quietly in the menu bar when you sign in."
        case .notRegistered: statusText = "Start Display Wizard automatically when you sign in."
        case .requiresApproval: statusText = "Allow Display Wizard in macOS Login Items to finish enabling it."
        case .notFound: statusText = "Launch at login is available from the installed app."
        @unknown default: statusText = "Check macOS Login Items for the current status."
        }
    }

    func setEnabled(_ requested: Bool) {
        lastError = nil
        do {
            let service = SMAppService.mainApp
            if requested {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            lastError = "Could not change launch at login: \(error.localizedDescription)"
        }
        refresh(clearError: false)
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
