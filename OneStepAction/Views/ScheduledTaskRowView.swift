import SwiftUI

struct ScheduledTaskRowView: View {
    let task: ScheduledTask
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(task.timeText)
                .font(.body.monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 88, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayName)
                    .font(.body)
                Text(task.countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { task.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "common.edit"))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "common.delete"))
        }
        .padding(.vertical, 4)
        .opacity(task.isEnabled ? 1 : 0.55)
    }
}
