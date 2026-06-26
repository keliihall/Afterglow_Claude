import SwiftUI
import AppKit
import Combine
import ServiceManagement

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let model = UsageModel()
    private let settings = AppSettings.shared
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon — it's a desktop widget
        buildWindow()
        buildStatusItem()
        observeSettings()
        model.start()
        scheduleTimer()
    }

    // MARK: - Window

    private func buildWindow() {
        let hosting = NSHostingController(rootView: ContentView(model: model, settings: settings))
        hosting.sizingOptions = [.preferredContentSize]

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 168, height: 110),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = hosting
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true     // drag anywhere
        win.level = settings.alwaysOnTop ? .floating : .normal
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.delegate = self
        win.ignoresMouseEvents = false

        // Right-click anywhere → same control menu.
        hosting.view.menu = buildMenu()

        window = win
        win.orderFrontRegardless()
        // Defer positioning one tick so the SwiftUI preferredContentSize has
        // resolved (so bottom-right anchoring uses the real window size).
        DispatchQueue.main.async { [weak self] in self?.restorePosition() }
    }

    private func restorePosition() {
        let d = UserDefaults.standard
        if d.object(forKey: "winX") != nil, d.object(forKey: "winY") != nil {
            window.setFrameOrigin(NSPoint(x: d.double(forKey: "winX"), y: d.double(forKey: "winY")))
            // Recover if the saved spot is now off every screen (display change, unplug).
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
            if !onScreen { moveToBottomRight() }
        } else {
            moveToBottomRight()
        }
    }

    private func moveToBottomRight() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = window.frame.size
        let margin: CGFloat = 22
        window.setFrameOrigin(NSPoint(x: vf.maxX - size.width - margin,
                                      y: vf.minY + margin))
        savePosition()
    }

    private func savePosition() {
        let o = window.frame.origin
        UserDefaults.standard.set(Double(o.x), forKey: "winX")
        UserDefaults.standard.set(Double(o.y), forKey: "winY")
    }

    func windowDidMove(_ notification: Notification) { savePosition() }

    // MARK: - Status bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            var name = "gauge.medium"   // exists on macOS 13
            if #available(macOS 14.0, *) { name = "gauge.with.dots.needle.50percent" }
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "用量") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "余"      // never leave the item empty/unclickable
            }
        }
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(item("立即刷新", #selector(refreshNow), key: "r"))
        menu.addItem(.separator())

        menu.addItem(toggle("置顶显示", #selector(toggleTop), on: settings.alwaysOnTop))
        menu.addItem(toggle("毛玻璃背景", #selector(toggleFrosted), on: settings.frosted))

        let opacity = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for p in [0.5, 0.65, 0.8, 0.92, 1.0] {
            let mi = NSMenuItem(title: "\(Int(p * 100))%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = p
            mi.state = abs(settings.opacity - p) < 0.01 ? .on : .off
            sub.addItem(mi)
        }
        opacity.submenu = sub
        menu.addItem(opacity)

        let refresh = NSMenuItem(title: "刷新频率", action: nil, keyEquivalent: "")
        let rsub = NSMenu()
        for (label, secs) in [("30 秒", 30.0), ("1 分钟", 60.0), ("5 分钟", 300.0), ("15 分钟", 900.0)] {
            let mi = NSMenuItem(title: label, action: #selector(setRefresh(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = secs
            mi.state = abs(settings.refreshSeconds - secs) < 0.5 ? .on : .off
            rsub.addItem(mi)
        }
        refresh.submenu = rsub
        menu.addItem(refresh)
        menu.addItem(.separator())

        menu.addItem(toggle("开机自启动", #selector(toggleLogin), on: loginEnabled()))
        menu.addItem(item("重置到右下角", #selector(resetPosition)))
        menu.addItem(.separator())
        menu.addItem(item("退出", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        return mi
    }

    private func toggle(_ title: String, _ sel: Selector, on: Bool) -> NSMenuItem {
        let mi = item(title, sel)
        mi.state = on ? .on : .off
        return mi
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Rebuild whichever of our menus is opening (status bar or window
        // right-click) so checkmarks reflect live state.
        let fresh = buildMenu()
        menu.removeAllItems()
        for it in fresh.items { fresh.removeItem(it); menu.addItem(it) }
    }

    // MARK: - Actions

    @objc private func refreshNow() { model.refresh() }

    @objc private func toggleTop() {
        settings.alwaysOnTop.toggle()
        window.level = settings.alwaysOnTop ? .floating : .normal
    }

    @objc private func toggleFrosted() { settings.frosted.toggle() }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        if let p = sender.representedObject as? Double { settings.opacity = p }
    }

    @objc private func setRefresh(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? Double { settings.refreshSeconds = s }
    }

    @objc private func resetPosition() { moveToBottomRight(); window.orderFrontRegardless() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Launch at login

    private func loginEnabled() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("login item toggle failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Settings reactivity & timer

    private func observeSettings() {
        settings.$alwaysOnTop
            .receive(on: RunLoop.main)
            .sink { [weak self] on in self?.window.level = on ? .floating : .normal }
            .store(in: &cancellables)

        settings.$refreshSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleTimer() }
            .store(in: &cancellables)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(10, settings.refreshSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.model.refresh()
        }
    }
}
