import AppKit
import SwiftUI

/// Brief keyboard feedback that never activates the app or intercepts input.
@MainActor final class BrightnessHUD {
    static let shared = BrightnessHUD()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func showError(message: String, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let content = AnyView(HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 23)).foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).lineLimit(3)
        }.padding(18).frame(width: 280, height: 100)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.97), in: RoundedRectangle(cornerRadius: 18))
            )
        present(content, on: screen)
    }

    func show(displayName: String, value: Double, on screen: NSScreen?) {
        guard value.isFinite, let screen = screen ?? NSScreen.main else { return }
        let bounded = min(1, max(0, value))
        present(AnyView(BrightnessHUDView(name: displayName, value: bounded)), on: screen)
    }

    private func present(_ content: AnyView, on screen: NSScreen) {
        dismissTask?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: content)
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 140, y: frame.minY + min(100, frame.height * 0.15)))
        panel.orderFrontRegardless()
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) }
            catch { return }
            self?.panel?.orderOut(nil)
            self?.panel?.contentView = nil
            self?.panel = nil
            self?.dismissTask = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct BrightnessHUDView: View {
    let name: String
    let value: Double
    private let mint = Color(nsColor: .controlAccentColor)
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill").font(.system(size: 21)).foregroundStyle(mint)
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Spacer(minLength: 4)
                Text("\(Int((value * 100).rounded()))%").font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.15))
                    .overlay(alignment: .leading) { Capsule().fill(mint).frame(width: geometry.size.width * value) }
            }.frame(height: 5)
        }
        .padding(20)
        .frame(width: 280, height: 100)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.97), in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }

        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) brightness \(Int((value * 100).rounded())) percent")
    }
}
