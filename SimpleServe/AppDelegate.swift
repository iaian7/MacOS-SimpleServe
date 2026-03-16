import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let simpleServeServerStatusDidChange = Notification.Name("simpleServeServerStatusDidChange")
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var contextMenu: NSMenu!
    var eventMonitor: Any?
    var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    let siteManager = SiteManager.shared
    let appSettings = AppSettings()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupContextMenu()

        if appSettings.globalServerEnabled {
            siteManager.startAllServices()
        } else {
            siteManager.checkServerStatus()
        }

        updateActivationPolicy()

        // Re-draw the status-bar icon whenever any AppSettings value changes
        // (e.g. menuBarIcon Picker). Using objectWillChange + asyncAfter lets
        // the @AppStorage write commit before we read the new value, and avoids
        // the cross-process task-port error caused by driving NSStatusItem
        // updates directly from a SwiftUI hosting context.
        appSettings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Schedule after the current run loop so @AppStorage has flushed
                DispatchQueue.main.async { self?.updateIcon() }
            }
            .store(in: &cancellables)

        // Show spinner when services are starting (launch) or restarting; restore icon when done.
        siteManager.$serverStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                NotificationCenter.default.post(name: .simpleServeServerStatusDidChange, object: nil)
            }
            .store(in: &cancellables)

        // First launch only: open settings so the user can verify components.
        if !appSettings.hasCompletedSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openSettingsWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dismissAllUI()
        showBusyIcon()
        siteManager.stopAllServices()
    }

    /// Dismisses popover and windows so the menu bar icon remains visible during service shutdown.
    private func dismissAllUI() {
        popover.performClose(nil)
        settingsWindow?.orderOut(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettingsWindow() }
        return true
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: appSettings.menuBarIconEnum.rawValue,
                                   accessibilityDescription: "SimpleServe")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil  // Reset so left-click works again
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 400)
        popover.behavior = .transient
        popover.animates = true

        let contentView = ContentView()
            .environmentObject(siteManager)
            .environmentObject(appSettings)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.delegate = self
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Right-Click Menu

    private func setupContextMenu() {
        contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ","))
        contextMenu.addItem(NSMenuItem.separator())
        contextMenu.addItem(NSMenuItem(title: "Quit SimpleServe", action: #selector(quitApp), keyEquivalent: "q"))

        for item in contextMenu.items {
            item.target = self
        }
    }

    @objc func openSettingsWindow() {
        if settingsWindow == nil || settingsWindow?.isVisible == false {
            let settingsView = SettingsView()
                .environmentObject(siteManager)
                .environmentObject(appSettings)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "SimpleServe Settings"
            window.contentViewController = NSHostingController(rootView: settingsView)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        // Mark setup as done the first time settings is ever shown.
        appSettings.hasCompletedSetup = true
        settingsWindow?.level = popover.isShown ? .popUpMenu : .normal
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Activation Policy

    func updateActivationPolicy() {
        NSApp.setActivationPolicy(.accessory)
        statusItem?.isVisible = true
    }

    func updateIcon() {
        let name: String
        if siteManager.serverStatus == .unknown {
            name = "arrow.triangle.2.circlepath"
        } else {
            name = appSettings.menuBarIconEnum.rawValue
        }
        statusItem?.button?.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: "SimpleServe"
        )
        // Dim the icon when the server is globally disabled
        statusItem?.button?.alphaValue = appSettings.globalServerEnabled ? 1.0 : 0.4
    }

    /// Shows the loading/waiting icon. Used when quitting so the user sees feedback during stop.
    private func showBusyIcon() {
        statusItem?.button?.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "SimpleServe"
        )
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        settingsWindow?.level = .normal
    }
}
