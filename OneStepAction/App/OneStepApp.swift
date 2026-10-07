import AppKit
import SwiftUI

@main
struct OneStepApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(model)
        } label: {
            Image(systemName: "command")
        }
        .menuBarExtraStyle(.menu)

        Window(String(localized: "window.shortcuts"), id: "main") {
            ShortcutListView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 320)
                .onAppear {
                    // Settings window open → appear in Dock and ⌘Tab.
                    appDelegate.enterRegularMode()
                    // bootstrap already ran at launch; refresh permission UI only.
                    model.bootstrap()
                }
        }
        .defaultSize(width: 760, height: 520)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var willCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar resident: hide Dock icon and stay out of ⌘Tab until a window opens.
        NSApp.setActivationPolicy(.accessory)

        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.restoreAccessoryModeIfNeeded(closing: note.object as? NSWindow)
        }
    }

    deinit {
        if let willCloseObserver {
            NotificationCenter.default.removeObserver(willCloseObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Show in Dock / ⌘Tab while the user is configuring shortcuts.
    func enterRegularMode() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreAccessoryModeIfNeeded(closing: NSWindow?) {
        // Wait until the close animation finishes before counting remaining windows.
        DispatchQueue.main.async {
            let stillOpen = NSApp.windows.contains { window in
                window !== closing
                    && window.isVisible
                    && window.canBecomeKey
                    && window.level == .normal
                    && window.className != "NSStatusBarWindow"
            }
            if !stillOpen {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
