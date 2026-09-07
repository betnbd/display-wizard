import AppKit
import SwiftUI

/// A pull-down anchored below the trigger, never aligned to its first action.
struct AppMenuButton: NSViewRepresentable {
    let quit: () -> Void

    func makeNSView(context: Context) -> PullDownButton {
        let button = PullDownButton()
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "App menu")
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setAccessibilityLabel("App menu")
        button.toolTip = "App menu"
        button.target = button
        button.action = #selector(PullDownButton.showMenu)
        button.quit = quit
        return button
    }
    func updateNSView(_ button: PullDownButton, context: Context) { button.quit = quit }

    final class PullDownButton: NSButton {
        override var isFlipped: Bool { true }
        var quit: (() -> Void)?
        @objc func showMenu() {
            let menu = NSMenu()
            let about = NSMenuItem(title: "About Display Wizard…", action: #selector(showAbout), keyEquivalent: "")
            about.target = self
            menu.addItem(about)
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Quit Display Wizard", action: #selector(performQuit), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            // With a flipped view, positive Y is below the button. No positioning
            // item means the menu's top edge goes here rather than under the pointer.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 6), in: self)
        }
        @objc private func showAbout() {
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "Display Wizard",
                .credits: NSAttributedString(string: "Native display controls.\nExternal brightness powered by m1ddc (MIT).")
            ])
        }
        @objc private func performQuit() { quit?() }
    }
}
