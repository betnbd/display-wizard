import AppKit
import SwiftUI
import Carbon
import Darwin

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let viewSession = WizardViewSession()
    var hotkeys: [EventHotKeyRef?] = []
    var localKeyMonitor: Any?
    var outsideClickMonitor: Any?
    private var feedbackGeneration = 0
    private var memoryCleanup: DispatchWorkItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.target = self; button.action = #selector(togglePanel)
        }
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
        registerShortcuts()
        LoginItemManager.shared.refresh()
        if !launchedAtLogin { DispatchQueue.main.async { [weak self] in self?.showPanel() } }
    }
    private var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
            || event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
    func applicationDidBecomeActive(_ notification: Notification) { LoginItemManager.shared.refresh() }
    func applicationDidResignActive(_ notification: Notification) { popover.performClose(nil) }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else { showPanel() }
    }
    private func showPanel() {
        guard let button = statusItem.button else { return }
        memoryCleanup?.cancel()
        memoryCleanup = nil
        model.refresh()
        LoginItemManager.shared.refresh()
        // Reserve room below the dropdown for the Quit pull-down menu.
        let height = min(CGFloat(660), (button.window?.screen?.visibleFrame.height ?? 850) - 85)
        if popover.contentViewController == nil {
            popover.contentViewController = NSHostingController(rootView: WizardView(model: model, session: viewSession, height: height))
        }
        popover.contentSize = NSSize(width: 370, height: height)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        // Keep only the tiny editing session; release the hidden SwiftUI tree,
        // native menus, accessibility objects and backing layers.
        popover.contentViewController = nil
        // After autoreleased UI objects drain, return unused allocator pages.
        // Delay and cancellation avoid churning memory during quick reopenings.
        memoryCleanup?.cancel()
        let cleanup = DispatchWorkItem { _ = malloc_zone_pressure_relief(nil, 0) }
        memoryCleanup = cleanup
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: cleanup)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model.revertMode(); return .terminateNow }
    func registerShortcuts() {
        // Also handle focused-window events, including accessibility-delivered keys.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape), self?.popover.isShown == true {
                self?.model.revertMode()
                self?.popover.performClose(nil)
                return nil
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains([.control, .option]), !modifiers.contains(.command),
                  event.keyCode == UInt16(kVK_UpArrow) || event.keyCode == UInt16(kVK_DownArrow) else { return event }
            self?.adjustBrightness(event.keyCode == UInt16(kVK_UpArrow) ? 0.05 : -0.05)
            return nil
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            let direction = identifier.id == 1 ? 0.05 : -0.05
            Task { @MainActor in delegate.adjustBrightness(direction) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        for (id, key) in [(UInt32(1), UInt32(kVK_UpArrow)), (UInt32(2), UInt32(kVK_DownArrow))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x44575A44, id: id), GetApplicationEventTarget(), 0, &ref)
            if result == noErr { hotkeys.append(ref) } else { model.notice = "Brightness shortcut is already in use by another app." }
        }
    }
    func adjustBrightness(_ delta: Double) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        feedbackGeneration += 1
        let generation = feedbackGeneration
        guard let display = model.displays.first(where: { $0.id == id }), let value = model.brightness[display.id] else {
            BrightnessHUD.shared.showError(message: "Brightness is unavailable for this display.", on: screen)
            return
        }
        let label = model.preferences.linkedBrightness ? "Linked displays · \(display.name)" : display.name
        model.setBrightness(min(1, max(0, value + delta)), for: display, completion: { [weak self] success in
            guard let self, self.feedbackGeneration == generation else { return }
            if success, let applied = self.model.brightness[display.id] {
                BrightnessHUD.shared.show(displayName: label, value: applied, on: screen)
            } else {
                BrightnessHUD.shared.showError(message: self.model.notice ?? "Could not change brightness. Open Display Wizard for details.", on: screen)
            }
        })
    }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    // A build artifact and installed copy must not both control the hardware.
    if let identifier = Bundle.main.bundleIdentifier,
       let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
        existing.activate(options: [.activateAllWindows])
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
