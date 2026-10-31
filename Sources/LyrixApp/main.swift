import AppKit
import SwiftUI
import Combine

@MainActor final class LyrixDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var overlay: NSPanel?
    private var settings: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Lyrix")
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Lyrix controls"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model, showOverlay: { [weak self] in self?.toggleOverlay() }, showSettings: { [weak self] in self?.openSettings() }))
        createOverlay()
        model.$preferences.sink { [weak self] prefs in
            DispatchQueue.main.async { self?.applyOverlay(prefs) }
        }.store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) } else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    private func createOverlay() {
        let rect = model.preferences.overlayFrame.map(NSRectFromString) ?? NSRect(x: 240, y: 240, width: 730, height: 250)
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.frame = NSRect(origin: .zero, size: rect.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.minSize = NSSize(width: 360, height: 160)
        panel.setFrameAutosaveName("LyrixOverlay")
        overlay = panel
        applyOverlay(model.preferences)
    }
    private func applyOverlay(_ prefs: Preferences) {
        guard let panel = overlay else { return }
        panel.level = prefs.alwaysOnTop ? .floating : .normal
        panel.ignoresMouseEvents = prefs.clickThrough
        if prefs.showOverlay {
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }), let screen = NSScreen.main {
                panel.setFrame(NSRect(x: screen.visibleFrame.midX - 365, y: screen.visibleFrame.minY + 80, width: 730, height: 250), display: true)
            }
            panel.orderFrontRegardless()
        } else { panel.orderOut(nil) }
    }
    private func toggleOverlay() { model.preferences.showOverlay.toggle() }
    private func openSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 440), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Lyrix Settings"; window.contentView = NSHostingView(rootView: SettingsView(model: model)); window.center(); settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let frame = overlay?.frame { model.preferences.overlayFrame = NSStringFromRect(frame) }
    }
}

@MainActor func launch() {
    let app = NSApplication.shared
    let delegate = LyrixDelegate()
    app.delegate = delegate
    app.run()
}
MainActor.assumeIsolated { launch() }
