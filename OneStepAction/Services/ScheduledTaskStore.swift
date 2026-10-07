import Foundation

/// Persists scheduled tasks. Same UserDefaults + Codable approach as ShortcutStore.
@MainActor
@Observable
final class ScheduledTaskStore {
    private static let storageKey = "onestep.scheduledTasks.v1"

    private(set) var tasks: [ScheduledTask] = []

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            tasks = []
            return
        }
        do {
            tasks = try JSONDecoder().decode([ScheduledTask].self, from: data)
        } catch {
            // Do not silently discard a corrupt payload — surface empty state and keep raw data intact.
            tasks = []
            NSLog("OneStep: failed to decode scheduled tasks: \(error)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(tasks)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            NSLog("OneStep: failed to encode scheduled tasks: \(error)")
        }
    }

    func add(_ task: ScheduledTask) {
        tasks.append(task)
        save()
    }

    func update(_ task: ScheduledTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
        save()
    }

    func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isEnabled = enabled
        save()
    }

    func task(forID id: UUID) -> ScheduledTask? {
        tasks.first { $0.id == id }
    }
}
