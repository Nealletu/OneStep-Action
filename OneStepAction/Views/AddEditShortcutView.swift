import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AddEditShortcutMode {
    case add
    case edit(ShortcutBinding)
}

struct AddEditShortcutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let mode: AddEditShortcutMode

    @State private var actionKind: ActionKind = .systemEvent
    @State private var systemEvent: SystemEvent = .lockScreen
    @State private var chainIDs: [UUID] = []
    @State private var chainIncludeDisabled = false
    @State private var customName = ""
    @State private var keyCode: UInt16?
    @State private var modifiers: UInt64 = 0
    @State private var appPath = ""
    @State private var appName = ""
    @State private var appBundleID = ""
    @State private var urlString = ""
    @State private var shellCommand = ""
    @State private var isEnabled = true
    @State private var conflict: ShortcutConflictResult?
    @State private var isRecording = false

    enum ActionKind: String, CaseIterable, Identifiable {
        case systemEvent
        case launchApplication
        case openURL
        case shellCommand
        case chain

        var id: String { rawValue }

        var label: String {
            switch self {
            case .systemEvent: return String(localized: "action.systemEvent")
            case .launchApplication: return String(localized: "type.app")
            case .openURL: return String(localized: "type.url")
            case .shellCommand: return String(localized: "type.shell")
            case .chain: return String(localized: "action.chain")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            Form {
                Picker(String(localized: "field.action"), selection: $actionKind) {
                    ForEach(ActionKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                actionFields

                Section {
                    ShortcutRecorderView(
                        keyCode: $keyCode,
                        modifiers: $modifiers,
                        isRecording: $isRecording
                    )
                    .frame(height: 36)
                } header: {
                    Text(String(localized: "field.shortcut"))
                }

                if let conflict {
                    ConflictStatusView(result: conflict)
                }

                Toggle(String(localized: "field.enabled"), isOn: $isEnabled)

                TextField(String(localized: "field.customName"), text: $customName)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "common.save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: hydrate)
        .onChange(of: keyCode) { _, _ in reevaluateConflict() }
        .onChange(of: modifiers) { _, _ in reevaluateConflict() }
    }

    private var title: String {
        switch mode {
        case .add: return String(localized: "add.title")
        case .edit: return String(localized: "edit.title")
        }
    }

    private var canSave: Bool {
        guard let keyCode, KeyCodeMapper.isRecordable(keyCode: keyCode, modifiers: modifiers) else {
            return false
        }
        if case .knownConflict = conflict?.level {
            return false
        }
        switch actionKind {
        case .systemEvent:
            return true
        case .chain:
            return chainIDs.contains { id in
                chainAvailableBindings.contains { $0.id == id }
            }
        case .launchApplication:
            return !appPath.isEmpty || !appBundleID.isEmpty || !appName.isEmpty
        case .openURL:
            return !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .shellCommand:
            return !shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Bindings eligible for chaining: aggregates cannot nest other aggregates,
    /// and the shortcut being edited must not select itself (it would replace its
    /// own action with a chain that skips itself — a silent dead key).
    private var chainAvailableBindings: [ShortcutBinding] {
        let editingID: UUID? = {
            if case let .edit(binding) = mode { return binding.id }
            return nil
        }()
        return model.store.bindings.filter {
            if case .chain = $0.action { return false }
            return $0.id != editingID
        }
    }

    private func toggleChainSelection(_ id: UUID) {
        if let index = chainIDs.firstIndex(of: id) {
            chainIDs.remove(at: index)
        } else {
            chainIDs.append(id)
        }
    }

    @ViewBuilder
    private var actionFields: some View {
        switch actionKind {
        case .systemEvent:
            Picker(String(localized: "field.event"), selection: $systemEvent) {
                // Second-level menu for the system-event kind (lock / display / sleep).
                Text(String(localized: "action.lockScreen")).tag(SystemEvent.lockScreen)
                Text(String(localized: "action.displaySleep")).tag(SystemEvent.displaySleep)
                Text(String(localized: "action.systemSleep")).tag(SystemEvent.systemSleep)
            }
            Text(systemEvent == .lockScreen
                ? String(localized: "hint.lockScreen")
                : String(localized: "hint.sleepEvents"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .chain:
            Section {
                if chainAvailableBindings.isEmpty {
                    Text(String(localized: "schedule.noBindings"))
                        .foregroundStyle(.secondary)
                }
                ForEach(chainAvailableBindings) { binding in
                    Button {
                        toggleChainSelection(binding.id)
                    } label: {
                        HStack {
                            Text(ShortcutFormatter.display(for: binding))
                                .font(.body.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                                .frame(width: 88, alignment: .center)

                            Text(binding.displayName)

                            Spacer()

                            if chainIDs.contains(binding.id) {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(String(localized: "schedule.pickShortcuts"))
            } footer: {
                Text(String(localized: "chain.orderHint"))
            }

            Toggle(String(localized: "field.includeDisabled"), isOn: $chainIncludeDisabled)
        case .launchApplication:
            HStack {
                TextField(String(localized: "field.appPath"), text: $appPath)
                Button(String(localized: "common.browse")) {
                    pickApp()
                }
            }
            TextField(String(localized: "field.appName"), text: $appName)
            TextField(String(localized: "field.bundleID"), text: $appBundleID)
        case .openURL:
            TextField(String(localized: "field.url"), text: $urlString)
                .textContentType(.URL)
        case .shellCommand:
            TextEditor(text: $shellCommand)
                .font(.body.monospaced())
                .frame(height: 80)
            Text(String(localized: "hint.shell"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hydrate() {
        switch mode {
        case .add:
            actionKind = .systemEvent
            systemEvent = .lockScreen
            isEnabled = true
        case let .edit(binding):
            keyCode = binding.keyCode
            modifiers = binding.modifiers
            isEnabled = binding.isEnabled
            customName = binding.name ?? ""
            switch binding.action {
            case let .systemEvent(event):
                actionKind = .systemEvent
                systemEvent = event
            case let .chain(ids, includeDisabled):
                actionKind = .chain
                chainIDs = ids
                chainIncludeDisabled = includeDisabled
            case let .launchApplication(bundleID, name, path):
                actionKind = .launchApplication
                appBundleID = bundleID ?? ""
                appName = name
                appPath = path ?? ""
            case let .openURL(url):
                actionKind = .openURL
                urlString = url
            case let .shellCommand(cmd):
                actionKind = .shellCommand
                shellCommand = cmd
            }
        }
        reevaluateConflict()
    }

    private func reevaluateConflict() {
        guard let keyCode else {
            conflict = nil
            return
        }
        conflict = ShortcutConflictDetector.evaluate(
            keyCode: keyCode,
            modifiers: modifiers,
            existingBindings: model.store.bindings,
            excludingID: {
                if case let .edit(binding) = mode { return binding.id }
                return nil
            }()
        )
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            appPath = url.path
            if appName.isEmpty {
                appName = url.deletingPathExtension().lastPathComponent
            }
            if let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier, appBundleID.isEmpty {
                appBundleID = bid
            }
        }
    }

    private func save() {
        guard let keyCode else { return }

        let action: ShortcutAction
        switch actionKind {
        case .systemEvent:
            action = .systemEvent(systemEvent)
        case .chain:
            action = .chain(
                bindingIDs: chainIDs.filter { id in
                    chainAvailableBindings.contains { $0.id == id }
                },
                includeDisabled: chainIncludeDisabled
            )
        case .launchApplication:
            action = .launchApplication(
                bundleID: appBundleID.isEmpty ? nil : appBundleID,
                appName: appName.isEmpty ? (appPath as NSString).lastPathComponent : appName,
                appPath: appPath.isEmpty ? nil : appPath
            )
        case .openURL:
            action = .openURL(urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        case .shellCommand:
            action = .shellCommand(shellCommand)
        }

        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: UUID
        if case let .edit(binding) = mode {
            id = binding.id
        } else {
            id = UUID()
        }

        let binding = ShortcutBinding(
            id: id,
            keyCode: keyCode,
            modifiers: modifiers,
            action: action,
            isEnabled: isEnabled,
            name: name.isEmpty ? nil : name
        )

        model.addOrUpdate(binding)
        if model.lastActionError == nil {
            dismiss()
        }
    }
}
