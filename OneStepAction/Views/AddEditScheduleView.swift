import SwiftUI

enum AddEditScheduleMode {
    case add
    case edit(ScheduledTask)
}

struct AddEditScheduleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let mode: AddEditScheduleMode

    @State private var ruleKind: RuleKind = .once
    @State private var onceDate = Date().addingTimeInterval(3600)
    @State private var timeDate = Date()
    @State private var weekday = Calendar.current.component(.weekday, from: Date())
    /// 选择顺序即执行顺序。
    @State private var selectedIDs: [UUID] = []
    @State private var isEnabled = true
    @State private var includeDisabled = false
    @State private var customName = ""

    enum RuleKind: String, CaseIterable, Identifiable {
        case once
        case daily
        case weekly

        var id: String { rawValue }

        var label: String {
            switch self {
            case .once: return String(localized: "schedule.once")
            case .daily: return String(localized: "schedule.daily")
            case .weekly: return String(localized: "schedule.weeklyLabel")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            Form {
                Picker(String(localized: "schedule.rule"), selection: $ruleKind) {
                    ForEach(RuleKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                ruleFields

                Section {
                    if model.store.bindings.isEmpty {
                        Text(String(localized: "schedule.noBindings"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.store.bindings) { binding in
                        Button {
                            toggleSelection(binding.id)
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

                                if selectedIDs.contains(binding.id) {
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
                }

                Toggle(String(localized: "field.enabled"), isOn: $isEnabled)

                Toggle(String(localized: "field.includeDisabled"), isOn: $includeDisabled)

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
    }

    private var title: String {
        switch mode {
        case .add: return String(localized: "schedule.addTitle")
        case .edit: return String(localized: "schedule.editTitle")
        }
    }

    private var canSave: Bool {
        guard selectedIDs.contains(where: { model.store.binding(forID: $0) != nil }) else {
            return false
        }
        if ruleKind == .once {
            return onceDate > Date()
        }
        return true
    }

    @ViewBuilder
    private var ruleFields: some View {
        switch ruleKind {
        case .once:
            DatePicker(
                String(localized: "schedule.dateTime"),
                selection: $onceDate,
                in: Date()...Date.distantFuture
            )
        case .daily:
            DatePicker(
                String(localized: "schedule.time"),
                selection: $timeDate,
                displayedComponents: .hourAndMinute
            )
        case .weekly:
            Picker(String(localized: "schedule.weekday"), selection: $weekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                }
            }
            DatePicker(
                String(localized: "schedule.time"),
                selection: $timeDate,
                displayedComponents: .hourAndMinute
            )
        }
    }

    private func hydrate() {
        switch mode {
        case .add:
            ruleKind = .once
            isEnabled = true
            let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
            timeDate = Calendar.current.date(
                from: DateComponents(hour: comps.hour, minute: comps.minute)
            ) ?? Date()
        case let .edit(task):
            isEnabled = task.isEnabled
            includeDisabled = task.includeDisabled
            customName = task.name ?? ""
            selectedIDs = task.bindingIDs
            switch task.rule {
            case let .once(date):
                ruleKind = .once
                onceDate = date
            case let .daily(hour, minute):
                ruleKind = .daily
                timeDate = timeDate(withHour: hour, minute: minute)
            case let .weekly(weekdayValue, hour, minute):
                ruleKind = .weekly
                weekday = weekdayValue
                timeDate = timeDate(withHour: hour, minute: minute)
            }
        }
    }

    private func timeDate(withHour hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(hour: hour, minute: minute)
        ) ?? Date()
    }

    private func toggleSelection(_ id: UUID) {
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(id)
        }
    }

    private func save() {
        // canSave's time check is a render-time snapshot; re-check right before
        // writing so a stale sheet can't persist an already-past one-shot fire.
        if ruleKind == .once, onceDate <= Date() {
            return
        }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: timeDate)
        let rule: ScheduleRule
        switch ruleKind {
        case .once:
            rule = .once(onceDate)
        case .daily:
            rule = .daily(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        case .weekly:
            rule = .weekly(weekday: weekday, hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        }

        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: UUID
        if case let .edit(task) = mode {
            id = task.id
        } else {
            id = UUID()
        }

        let task = ScheduledTask(
            id: id,
            name: name.isEmpty ? nil : name,
            bindingIDs: selectedIDs.filter { model.store.binding(forID: $0) != nil },
            rule: rule,
            isEnabled: isEnabled,
            includeDisabled: includeDisabled
        )

        model.addOrUpdateSchedule(task)
        dismiss()
    }
}
