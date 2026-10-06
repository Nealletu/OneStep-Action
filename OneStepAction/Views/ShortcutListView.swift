import SwiftUI

struct ShortcutListView: View {
    @Environment(AppModel.self) private var model
    @State private var editingBinding: ShortcutBinding?
    @State private var isPresentingAdd = false
    @State private var deleteConfirmID: UUID?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            VStack(spacing: 0) {
                if !model.accessibility.isTrusted {
                    PermissionBanner()
                }

                if model.store.bindings.isEmpty {
                    emptyState
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
            .navigationTitle(String(localized: "window.shortcuts"))
            .toolbar {
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAdd = true
                    } label: {
                        Label(String(localized: "common.add"), systemImage: "plus")
                    }
                    .help(String(localized: "help.addShortcut"))
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
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "empty.title"), systemImage: "keyboard")
        } description: {
            Text(String(localized: "empty.description"))
        } actions: {
            Button(String(localized: "common.add")) {
                isPresentingAdd = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
