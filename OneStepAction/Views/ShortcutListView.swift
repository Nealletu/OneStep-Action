import SwiftUI

struct ShortcutListView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedPane: ShortcutsPane? = .shortcuts
    @State private var editingBinding: ShortcutBinding?
    @State private var isPresentingAdd = false
    @State private var deleteConfirmID: UUID?
    @State private var editingTask: ScheduledTask?
    @State private var isPresentingAddSchedule = false
    @State private var deleteScheduleID: UUID?

    enum ShortcutsPane: String, CaseIterable, Identifiable, Hashable {
        case shortcuts
        case schedules

        var id: String { rawValue }

        var label: String {
            switch self {
            case .shortcuts: return String(localized: "window.shortcuts")
            case .schedules: return String(localized: "schedule.segment")
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        let pane = selectedPane ?? .shortcuts

        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedPane) {
                Label(String(localized: "window.shortcuts"), systemImage: "keyboard")
                    .tag(ShortcutsPane.shortcuts)
                Label(String(localized: "schedule.segment"), systemImage: "clock")
                    .tag(ShortcutsPane.schedules)
            }
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                if !model.accessibility.isTrusted {
                    PermissionBanner()
                }

                switch pane {
                case .shortcuts:
                    shortcutsPane
                case .schedules:
                    schedulesPane
                }
            }
            .navigationTitle(pane.label)
            .toolbar {
                if pane == .shortcuts {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.importShortcuts()
                        } label: {
                            Label(String(localized: "common.import"), systemImage: "square.and.arrow.down")
                        }
                        .help(String(localized: "help.import"))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.exportShortcuts()
                        } label: {
                            Label(String(localized: "common.export"), systemImage: "square.and.arrow.up")
                        }
                        .help(String(localized: "help.export"))
                        .disabled(model.store.bindings.isEmpty)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if pane == .shortcuts {
                            isPresentingAdd = true
                        } else {
                            isPresentingAddSchedule = true
                        }
                    } label: {
                        Label(String(localized: "common.add"), systemImage: "plus")
                    }
                    .help(pane == .shortcuts
                        ? String(localized: "help.addShortcut")
                        : String(localized: "help.addSchedule"))
                }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddEditShortcutView(mode: .add)
                .environment(model)
        }
        .sheet(item: $editingBinding) { binding in
            AddEditShortcutView(mode: .edit(binding))
                .environment(model)
        }
        .sheet(isPresented: $isPresentingAddSchedule) {
            AddEditScheduleView(mode: .add)
                .environment(model)
        }
        .sheet(item: $editingTask) { task in
            AddEditScheduleView(mode: .edit(task))
                .environment(model)
        }
        .confirmationDialog(
            String(localized: "confirm.deleteTitle"),
            isPresented: Binding(
                get: { deleteConfirmID != nil },
                set: { if !$0 { deleteConfirmID = nil } }
            )
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let id = deleteConfirmID {
                    model.delete(id: id)
                }
                deleteConfirmID = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                deleteConfirmID = nil
            }
        } message: {
            Text(String(localized: "confirm.deleteMessage"))
        }
        .confirmationDialog(
            String(localized: "confirm.deleteScheduleTitle"),
            isPresented: Binding(
                get: { deleteScheduleID != nil },
                set: { if !$0 { deleteScheduleID = nil } }
            )
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let id = deleteScheduleID {
                    model.deleteSchedule(id: id)
                }
                deleteScheduleID = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                deleteScheduleID = nil
            }
        } message: {
            Text(String(localized: "confirm.deleteScheduleMessage"))
        }
        .sheet(isPresented: $model.showPermissionSheet) {
            PermissionSheet()
                .environment(model)
        }
        .alert(
            String(localized: "alert.error"),
            isPresented: Binding(
                get: { model.lastActionError != nil },
                set: { if !$0 { model.clearActionError() } }
            )
        ) {
            Button(String(localized: "common.ok")) {
                model.clearActionError()
            }
        } message: {
            Text(model.lastActionError ?? "")
        }
    }

    // MARK: - Shortcuts pane

    @ViewBuilder
    private var shortcutsPane: some View {
        if model.store.bindings.isEmpty {
            emptyState(
                title: String(localized: "empty.title"),
                systemImage: "keyboard",
                description: String(localized: "empty.description"),
                action: { isPresentingAdd = true }
            )
        } else {
            List {
                ForEach(model.store.bindings) { binding in
                    ShortcutRowView(
                        binding: binding,
                        onToggle: { enabled in
                            model.setEnabled(enabled, id: binding.id)
                        },
                        onEdit: {
                            editingBinding = binding
                        },
                        onDelete: {
                            deleteConfirmID = binding.id
                        }
                    )
                    .contextMenu {
                        Button(String(localized: "common.edit")) {
                            editingBinding = binding
                        }
                        Button(String(localized: "common.delete"), role: .destructive) {
                            deleteConfirmID = binding.id
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Schedules pane

    @ViewBuilder
    private var schedulesPane: some View {
        if model.scheduledTasks.tasks.isEmpty {
            emptyState(
                title: String(localized: "schedule.empty.title"),
                systemImage: "clock",
                description: String(localized: "schedule.empty.description"),
                action: { isPresentingAddSchedule = true }
            )
        } else {
            List {
                ForEach(model.scheduledTasks.tasks) { task in
                    ScheduledTaskRowView(
                        task: task,
                        onToggle: { enabled in
                            model.setScheduleEnabled(enabled, id: task.id)
                        },
                        onEdit: {
                            editingTask = task
                        },
                        onDelete: {
                            deleteScheduleID = task.id
                        }
                    )
                    .contextMenu {
                        Button(String(localized: "common.edit")) {
                            editingTask = task
                        }
                        Button(String(localized: "common.delete"), role: .destructive) {
                            deleteScheduleID = task.id
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func emptyState(
        title: String,
        systemImage: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            Button(String(localized: "common.add"), action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
