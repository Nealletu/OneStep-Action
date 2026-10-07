import AppKit
import CoreGraphics
import Foundation

/// Owns the CGEventTap that matches global shortcuts and fires actions.
/// Event tap is the only supported listening path (no polling).
///
/// Concurrency notes:
/// - The tap run-loop source is installed on the main run loop, so the C callback runs on main.
/// - `registrations` / tap refs are `nonisolated(unsafe)` because the C callback is not MainActor.
///   They are only mutated from MainActor methods.
final class GlobalShortcutManager {
    struct ActiveRegistration: Sendable {
        let bindingID: UUID
        let keyCode: UInt16
        let modifiers: UInt64
        let action: ShortcutAction
    }

    @MainActor private(set) var isRunning = false
    @MainActor private(set) var lastError: String?

    nonisolated(unsafe) private var registrations: [ActiveRegistration] = []
    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    /// Full binding list for resolving `.chain` actions. Same threading contract as
    /// `registrations`: only mutated from MainActor, read from the tap callback.
    nonisolated(unsafe) private var bindingsSnapshot: [ShortcutBinding] = []

    @MainActor private let onTriggered: @MainActor (ShortcutBinding) -> Void

    @MainActor
    init(onTriggered: @escaping @MainActor (ShortcutBinding) -> Void) {
        self.onTriggered = onTriggered
    }

    // MARK: - Lifecycle

    @MainActor
    func startIfNeeded() {
        guard !isRunning else {
            refreshTapIfNeeded()
            return
        }
        startEventTap()
    }

    @MainActor
    func stop() {
        removeTap()
        isRunning = false
        registrations = []
        bindingsSnapshot = []
    }

    /// Replace the full set of enabled bindings and (re)start the tap.
    @MainActor
    func apply(bindings: [ShortcutBinding]) {
        bindingsSnapshot = bindings
        registrations = bindings
            .filter(\.isEnabled)
            .map {
                ActiveRegistration(
                    bindingID: $0.id,
                    keyCode: $0.keyCode,
                    modifiers: $0.modifiers,
                    action: $0.action
                )
            }
        if isRunning {
            refreshTapIfNeeded()
        } else {
            startEventTap()
        }
    }

    // MARK: - Tap

    @MainActor
    private func startEventTap() {
        lastError = nil
        removeTap()

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: oneStepEventTapCallback,
            userInfo: refcon
        ) else {
            isRunning = false
            lastError = String(localized: "error.eventTap.create")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    @MainActor
    private func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    @MainActor
    private func refreshTapIfNeeded() {
        guard let tap = eventTap else {
            startEventTap()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Called from the C callback on the main run loop. Must stay fast.
    nonisolated func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = KeyCodeMapper.carbonModifiers(fromCGEventFlags: event.flags)
        guard keyCode != 0xFFFF else {
            return Unmanaged.passUnretained(event)
        }

        guard let match = registrations.first(where: {
            $0.keyCode == keyCode && $0.modifiers == modifiers
        }) else {
            return Unmanaged.passUnretained(event)
        }

        let action = match.action
        let bindings = bindingsSnapshot

        Task { @MainActor in
            await GlobalShortcutManager.performTriggeredAction(action, bindings: bindings)
        }

        // Consume the event so it does not reach the frontmost app.
        return nil
    }

    @MainActor
    private static func performTriggeredAction(_ action: ShortcutAction, bindings: [ShortcutBinding]) async {
        do {
            try await ActionExecutor.execute(action, bindings: bindings)
        } catch {
            NSLog("OneStep: action failed: \(error.localizedDescription)")
            presentFailureAlert(error.localizedDescription)
        }
    }

    @MainActor
    private static func presentFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.actionFailed.title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// True if CGEventTap can be created (used by diagnostics).
    @MainActor
    static func canCreateTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, _, _ in nil },
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }
}

/// C-compatible callback for CGEventTap.
private let oneStepEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handleEvent(type: type, event: event)
}
