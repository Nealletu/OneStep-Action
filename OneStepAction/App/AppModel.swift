import AppKit
import Carbon.HIToolbox
import Foundation
import UniformTypeIdentifiers

/// App-level state wired to services.
@MainActor
@Observable
final class AppModel {
    let store = ShortcutStore()
    let scheduledTasks = ScheduledTaskStore()
    let accessibility = AccessibilityManager()
    let loginItem = LaunchAtLoginManager()

    private(set) var shortcutManager: GlobalShortcutManager!
    private(set) var scheduleManager: ScheduleManager!
    private(set) var lastActionError: String?

    var showPermissionSheet = false

    init() {
        shortcutManager = GlobalShortcutManager { [weak self] binding in
            self?.noteTriggered(binding)
        }
        scheduleManager = ScheduleManager(taskStore: scheduledTasks, shortcutStore: store)
        // Start event tap at launch — not only after the settings window opens.
        Task { @MainActor [weak self] in
            self?.bootstrap()
        }
    }

    func bootstrap() {
        scheduleManager.start()
        accessibility.refresh()
        if !accessibility.isTrusted {
            showPermissionSheet = true
        }
        accessibility.startMonitoring { [weak self] in
            // Permission granted later (System Settings) → register hotkeys.
            self?.syncShortcuts()
        }
        syncShortcuts()
    }

    func syncShortcuts() {
        guard accessibility.isTrusted else {
            shortcutManager.stop()
            return
        }
        shortcutManager.apply(bindings: store.bindings)
    }

    func addOrUpdate(_ binding: ShortcutBinding) {
        let existingInternal = store.hasInternalConflict(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers,
            excludingID: binding.id
        )
        if existingInternal {
            lastActionError = String(localized: "conflict.internal")
            return
        }

        if store.binding(forID: binding.id) != nil {
            store.update(binding)
        } else {
            store.add(binding)
        }
        syncShortcuts()
    }

    func delete(id: UUID) {
        store.delete(id: id)
        syncShortcuts()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        store.setEnabled(enabled, id: id)
        syncShortcuts()
    }

    // MARK: - Scheduled tasks

    func addOrUpdateSchedule(_ task: ScheduledTask) {
        if scheduledTasks.task(forID: task.id) != nil {
            scheduledTasks.update(task)
        } else {
            scheduledTasks.add(task)
        }
        scheduleManager.reschedule()
    }

    func deleteSchedule(id: UUID) {
        scheduledTasks.delete(id: id)
        scheduleManager.reschedule()
    }

    func setScheduleEnabled(_ enabled: Bool, id: UUID) {
        scheduledTasks.setEnabled(enabled, id: id)
        scheduleManager.reschedule()
    }

    private func noteTriggered(_ binding: ShortcutBinding) {
        NSLog("OneStep: shortcut triggered \(ShortcutFormatter.display(for: binding))")
    }

    func clearActionError() {
        lastActionError = nil
    }

    // MARK: - Import / Export

    func exportShortcuts() {
        guard !store.bindings.isEmpty else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store.bindings)

            let panel = NSSavePanel()
            panel.title = String(localized: "help.export")
            panel.prompt = String(localized: "common.export")
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            panel.nameFieldStringValue = "onestep-shortcuts-\(Self.exportDateFormatter.string(from: Date())).json"

            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        } catch {
            lastActionError = String(format: String(localized: "error.export"), error.localizedDescription)
        }
    }

    func importShortcuts() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "help.import")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let incoming = try JSONDecoder().decode([ShortcutBinding].self, from: data)
            guard !incoming.isEmpty else {
                lastActionError = String(localized: "import.empty")
                return
            }
            let stats = store.merge(incoming)
            syncShortcuts()
            if stats.duplicates + stats.conflicts > 0 {
                lastActionError = String(
                    format: String(localized: "import.result"),
                    stats.imported,
                    stats.duplicates,
                    stats.conflicts
                )
            }
        } catch {
            lastActionError = String(format: String(localized: "error.import.invalid"), error.localizedDescription)
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
