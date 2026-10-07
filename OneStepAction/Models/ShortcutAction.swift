import Foundation

/// Power-related system events exposed as actions.
enum SystemEvent: String, Codable, Hashable, Sendable {
    case lockScreen
    case displaySleep
    case systemSleep
}

/// Action attached to a global shortcut. New cases can be added without touching the event tap.
enum ShortcutAction: Hashable, Sendable {
    case systemEvent(SystemEvent)
    case launchApplication(bundleID: String?, appName: String, appPath: String?)
    case openURL(String)
    case shellCommand(String)
    /// Aggregate: run the referenced bindings in order. `bindingIDs` order is execution order.
    /// `includeDisabled` decides whether disabled member shortcuts are still run.
    case chain(bindingIDs: [UUID], includeDisabled: Bool)
}

// MARK: - Display

extension ShortcutAction {
    var defaultName: String {
        switch self {
        case let .systemEvent(event):
            switch event {
            case .lockScreen:
                return String(localized: "action.lockScreen")
            case .displaySleep:
                return String(localized: "action.displaySleep")
            case .systemSleep:
                return String(localized: "action.systemSleep")
            }
        case let .launchApplication(_, appName, _):
            return String(localized: "action.launchApp.\(appName)")
        case let .openURL(url):
            return String(format: String(localized: "action.openURL"), url)
        case let .shellCommand(command):
            var trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 28 {
                trimmed = String(trimmed.prefix(28)) + "…"
            }
            return String(format: String(localized: "action.shell"), trimmed)
        case let .chain(bindingIDs, _):
            return String(format: String(localized: "action.chainName"), bindingIDs.count)
        }
    }

    var typeDisplayName: String {
        switch self {
        case .systemEvent:
            return String(localized: "type.system")
        case .launchApplication:
            return String(localized: "type.app")
        case .openURL:
            return String(localized: "type.url")
        case .shellCommand:
            return String(localized: "type.shell")
        case .chain:
            return String(localized: "type.chain")
        }
    }
}

// MARK: - Codable

extension ShortcutAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case bundleID
        case appName
        case appPath
        case url
        case command
        case bindingIDs
        case includeDisabled
    }

    private enum Kind: String, Codable {
        // Kept as the wire format for SystemEvent.lockScreen so existing
        // payloads (and older app versions reading this field) stay valid.
        case lockScreen
        case displaySleep
        case systemSleep
        case launchApplication
        case openURL
        case shellCommand
        case chain
        // Reserved for future extension (architecture allows it).
        case appleScript
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .lockScreen:
            self = .systemEvent(.lockScreen)
        case .displaySleep:
            self = .systemEvent(.displaySleep)
        case .systemSleep:
            self = .systemEvent(.systemSleep)
        case .launchApplication:
            self = .launchApplication(
                bundleID: try container.decodeIfPresent(String.self, forKey: .bundleID),
                appName: try container.decode(String.self, forKey: .appName),
                appPath: try container.decodeIfPresent(String.self, forKey: .appPath)
            )
        case .openURL:
            self = .openURL(try container.decode(String.self, forKey: .url))
        case .shellCommand:
            self = .shellCommand(try container.decode(String.self, forKey: .command))
        case .chain:
            self = .chain(
                bindingIDs: try container.decode([UUID].self, forKey: .bindingIDs),
                // Absent in payloads written before the switch existed → skip disabled members.
                includeDisabled: try container.decodeIfPresent(Bool.self, forKey: .includeDisabled) ?? false
            )
        case .appleScript:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "appleScript action is reserved and not implemented in MVP"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .systemEvent(event):
            // lockScreen keeps its legacy kind for backward compatibility.
            switch event {
            case .lockScreen:
                try container.encode(Kind.lockScreen, forKey: .kind)
            case .displaySleep:
                try container.encode(Kind.displaySleep, forKey: .kind)
            case .systemSleep:
                try container.encode(Kind.systemSleep, forKey: .kind)
            }
        case let .launchApplication(bundleID, appName, appPath):
            try container.encode(Kind.launchApplication, forKey: .kind)
            try container.encodeIfPresent(bundleID, forKey: .bundleID)
            try container.encode(appName, forKey: .appName)
            try container.encodeIfPresent(appPath, forKey: .appPath)
        case let .openURL(url):
            try container.encode(Kind.openURL, forKey: .kind)
            try container.encode(url, forKey: .url)
        case let .shellCommand(command):
            try container.encode(Kind.shellCommand, forKey: .kind)
            try container.encode(command, forKey: .command)
        case let .chain(bindingIDs, includeDisabled):
            try container.encode(Kind.chain, forKey: .kind)
            try container.encode(bindingIDs, forKey: .bindingIDs)
            try container.encode(includeDisabled, forKey: .includeDisabled)
        }
    }
}
