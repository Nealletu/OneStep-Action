import Foundation

/// 触发规则：一次性 / 每天 / 每周固定时间。
enum ScheduleRule: Codable, Hashable, Sendable {
    case once(Date)
    case daily(hour: Int, minute: Int)
    /// weekday 使用 Calendar 惯例：1 = 周日 … 7 = 周六。
    case weekly(weekday: Int, hour: Int, minute: Int)

    /// 严格晚于 `date` 的下一次触发时刻；一次性任务已过则返回 nil（错过即作废）。
    func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case let .once(target):
            return target > date ? target : nil
        case let .daily(hour, minute):
            return calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute),
                matchingPolicy: .nextTime
            )
        case let .weekly(weekday, hour, minute):
            return calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                matchingPolicy: .nextTime
            )
        }
    }

    /// 规则携带的时、分（用于统一展示时间）。
    var hourMinute: (hour: Int, minute: Int) {
        switch self {
        case let .once(date):
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0, comps.minute ?? 0)
        case let .daily(hour, minute):
            return (hour, minute)
        case let .weekly(_, hour, minute):
            return (hour, minute)
        }
    }
}

/// 一条定时任务：在规则时间点按顺序执行一组已有快捷键。
struct ScheduledTask: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String?
    /// 绑定的快捷键 id，按顺序执行；执行时已被删除的 id 跳过。
    var bindingIDs: [UUID]
    var rule: ScheduleRule
    var isEnabled: Bool
    /// 触发时是否也执行已禁用（isEnabled == false）的成员快捷键。
    var includeDisabled: Bool

    init(
        id: UUID = UUID(),
        name: String? = nil,
        bindingIDs: [UUID],
        rule: ScheduleRule,
        isEnabled: Bool = true,
        includeDisabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bindingIDs = bindingIDs
        self.rule = rule
        self.isEnabled = isEnabled
        self.includeDisabled = includeDisabled
    }

    // Custom decoder: `includeDisabled` was added later and is absent from
    // already-persisted tasks — default it instead of failing the whole store load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        bindingIDs = try container.decode([UUID].self, forKey: .bindingIDs)
        rule = try container.decode(ScheduleRule.self, forKey: .rule)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        includeDisabled = try container.decodeIfPresent(Bool.self, forKey: .includeDisabled) ?? false
    }
}

// MARK: - Display

extension ScheduledTask {
    /// 时间部分，如 "09:30"。
    var timeText: String {
        let (hour, minute) = rule.hourMinute
        return String(format: "%02d:%02d", hour, minute)
    }

    /// 完整规则文案，如 "每天 09:30" / "每星期一 09:30" / "2026年10月8日 09:30"。
    var ruleText: String {
        switch rule {
        case let .once(date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        case .daily:
            return "\(String(localized: "schedule.daily")) \(timeText)"
        case let .weekly(weekday, _, _):
            let weekdayText = Calendar.current.weekdaySymbols[weekday - 1]
            return String(format: String(localized: "schedule.weekly"), weekdayText) + " \(timeText)"
        }
    }

    /// 主标题：用户命名优先，否则用规则文案。
    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return ruleText
    }

    var countText: String {
        String(format: String(localized: "schedule.bindingCount"), bindingIDs.count)
    }
}
