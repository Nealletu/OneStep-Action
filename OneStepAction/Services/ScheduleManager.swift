import AppKit
import Foundation

/// Schedules due tasks: single-shot Timer to the nearest fire time, skip misses.
@MainActor
@Observable
final class ScheduleManager {
    /// Fire window: a wake-up later than this counts as missed and is skipped (no catch-up).
    private static let tolerance: TimeInterval = 60

    private let taskStore: ScheduledTaskStore
    private let shortcutStore: ShortcutStore
    private var timer: Timer?
    /// Last expected fire time actually run per task — prevents a periodic task from
    /// firing twice when another task's trigger lands within the same 60s window.
    private var lastFired: [UUID: Date] = [:]

    init(taskStore: ScheduledTaskStore, shortcutStore: ShortcutStore) {
        self.taskStore = taskStore
        self.shortcutStore = shortcutStore
    }

    func start() {
        reschedule()
    }

    /// Re-arm the timer to the earliest upcoming fire among enabled tasks.
    /// - Parameter base: Reference time for "next fire". Callers that just finished a
    ///   fire() pass its start time so tasks that became due *during* execution are
    ///   picked up by the follow-up timer instead of being pushed to tomorrow.
    func reschedule(base: Date = Date()) {
        timer?.invalidate()
        timer = nil

        let next = taskStore.tasks
            .filter(\.isEnabled)
            .compactMap { $0.rule.nextFire(after: base) }
            .min()

        guard let next else { return }
        let timer = Timer(
            timeInterval: max(next.timeIntervalSinceNow, 0.1),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fire()
            }
        }
        // .common so a fire during modal panels / menu tracking still runs.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() async {
        let fireStart = Date()
        let windowStart = fireStart.addingTimeInterval(-Self.tolerance)
        var failures: [String] = []

        for task in taskStore.tasks where task.isEnabled {
            guard let expected = task.rule.nextFire(after: windowStart) else {
                // nextFire == nil for `.once` means its target is older than the
                // tolerance window — it missed for good; retire it instead of
                // leaving a permanently dead "enabled" row in the list.
                if case .once = task.rule {
                    taskStore.delete(id: task.id)
                }
                continue
            }
            // Not due yet, or already fired for this expected time (another task's
            // trigger brought us back inside the same window).
            guard expected <= fireStart,
                  expected > (lastFired[task.id] ?? .distantPast)
            else { continue }
            lastFired[task.id] = expected

            for bindingID in task.bindingIDs {
                guard let binding = shortcutStore.binding(forID: bindingID) else {
                    continue // Deleted shortcut — skip it.
                }
                if !task.includeDisabled, !binding.isEnabled {
                    continue // Member disabled and the task doesn't opt in.
                }
                do {
                    try await ActionExecutor.execute(binding.action, bindings: shortcutStore.bindings)
                } catch {
                    NSLog("OneStep: scheduled task \(task.id) failed: \(error.localizedDescription)")
                    failures.append("\(task.displayName): \(error.localizedDescription)")
                }
            }

            if case .once = task.rule {
                taskStore.delete(id: task.id)
            }
        }

        // Re-arm before alerting: a failure alert can stay up for minutes and the
        // run loop must already know about tasks that became due during execution.
        reschedule(base: fireStart)
        if !failures.isEmpty {
            presentFailureAlert(failures.joined(separator: "\n"))
        }
    }

    /// Same presentation as GlobalShortcutManager — the main window may be closed when a task fires.
    private func presentFailureAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.actionFailed.title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
