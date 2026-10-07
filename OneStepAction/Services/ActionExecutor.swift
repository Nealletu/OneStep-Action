import AppKit
import Darwin
import Foundation

/// Executes ShortcutActions. Decoupled from the event tap / UI.
enum ActionExecutorError: LocalizedError {
    case invalidURL(String)
    case appNotFound(String)
    case lockScreenUnavailable(String)
    case shellFailed(exitCode: Int32, stderr: String)
    case chainFailed(String)
    case chainEmpty

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return String(format: String(localized: "error.invalidURL"), url)
        case let .appNotFound(name):
            return String(format: String(localized: "error.appNotFound"), name)
        case let .lockScreenUnavailable(detail):
            return String(format: String(localized: "error.lockScreen"), detail)
        case let .shellFailed(code, stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return String(format: String(localized: "error.shell"), code)
            }
            return String(format: String(localized: "error.shellDetail"), code, trimmed)
        case let .chainFailed(detail):
            return String(format: String(localized: "error.chainFailed"), detail)
        case .chainEmpty:
            return String(localized: "error.chainEmpty")
        }
    }
}

enum ActionExecutor {
    /// - Parameter bindings: Full binding list; required to resolve `.chain` entries.
    @MainActor
    static func execute(_ action: ShortcutAction, bindings: [ShortcutBinding] = []) async throws {
        switch action {
        case let .systemEvent(event):
            try await executeSystemEvent(event)
        case let .launchApplication(bundleID, appName, appPath):
            try await launchApplication(bundleID: bundleID, appName: appName, appPath: appPath)
        case let .openURL(raw):
            try openURL(raw)
        case let .shellCommand(command):
            try await runShell(command)
        case let .chain(bindingIDs, includeDisabled):
            try await executeChain(bindingIDs, includeDisabled: includeDisabled, bindings: bindings)
        }
    }

    // MARK: - System Events

    @MainActor
    private static func executeSystemEvent(_ event: SystemEvent) async throws {
        switch event {
        case .lockScreen:
            try lockScreen()
        case .displaySleep:
            // Verified via man pmset: immediate display sleep, no sudo required.
            try await runShell("/usr/bin/pmset displaysleepnow")
        case .systemSleep:
            try await runShell("/usr/bin/pmset sleepnow")
        }
    }

    // MARK: - Chain (aggregate)

    @MainActor
    private static func executeChain(
        _ ids: [UUID],
        includeDisabled: Bool,
        bindings: [ShortcutBinding]
    ) async throws {
        var failures: [String] = []
        var executed = 0
        for id in ids {
            guard let binding = bindings.first(where: { $0.id == id }) else {
                NSLog("OneStep: chain entry missing, skipped: \(id)")
                continue
            }
            if case .chain = binding.action {
                // Nested chains are excluded at save time; skip defensively.
                NSLog("OneStep: nested chain skipped: \(id)")
                continue
            }
            if !includeDisabled, !binding.isEnabled {
                NSLog("OneStep: chain entry disabled, skipped: \(id)")
                continue
            }
            executed += 1
            do {
                try await execute(binding.action, bindings: bindings)
            } catch {
                NSLog("OneStep: chain entry failed \(id): \(error.localizedDescription)")
                failures.append("\(binding.displayName): \(error.localizedDescription)")
            }
        }
        // Every referenced entry vanished (or was filtered) — surface it instead of
        // letting the key press look like a no-op.
        guard executed > 0 else {
            throw ActionExecutorError.chainEmpty
        }
        if !failures.isEmpty {
            throw ActionExecutorError.chainFailed(failures.joined(separator: "\n"))
        }
    }

    // MARK: - Lock Screen

    /// Locks the console session.
    ///
    /// macOS has **no public lock-screen API**. System `LockScreen.app` is an ARD overlay
    /// and cannot be launched as a normal app; `CGSession -suspend` was removed years ago.
    ///
    /// The de-facto approach used by Hammerspoon / Raycast-class tools is `SACLockScreenImmediate`
    /// from `login.framework`, resolved at runtime via `dlsym` (no compile-time private link).
    /// This is not keystroke simulation (⌃⌘Q).
    @MainActor
    private static func lockScreen() throws {
        typealias LockFn = @convention(c) () -> Void

        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            let detail = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            throw ActionExecutorError.lockScreenUnavailable(detail)
        }
        // Keep the handle loaded for process lifetime.
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            throw ActionExecutorError.lockScreenUnavailable("SACLockScreenImmediate not found")
        }
        let lock = unsafeBitCast(symbol, to: LockFn.self)
        lock()
    }

    // MARK: - Launch App

    @MainActor
    private static func launchApplication(bundleID: String?, appName: String, appPath: String?) async throws {
        if let appPath, !appPath.isEmpty {
            try await openApplication(URL(fileURLWithPath: appPath), appName: appName)
            return
        }

        if let bundleID, !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            try await openApplication(url, appName: appName)
            return
        }

        // Last resort: search common application locations by name.
        let candidatePaths = [
            "/Applications/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
        ]
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            try await openApplication(URL(fileURLWithPath: path), appName: appName)
            return
        }
        throw ActionExecutorError.appNotFound(appName)
    }

    /// Waits until the workspace finishes opening the app so chains run in true order.
    @MainActor
    private static func openApplication(_ url: URL, appName: String) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if error != nil {
                    NSLog("OneStep: open app failed for \(url.path)")
                    continuation.resume(throwing: ActionExecutorError.appNotFound(appName))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Open URL

    @MainActor
    private static func openURL(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmed
        if !trimmed.lowercased().hasPrefix("http://"), !trimmed.lowercased().hasPrefix("https://"),
           !trimmed.contains("://") {
            candidate = "https://\(trimmed)"
        }
        guard let url = URL(string: candidate), url.scheme != nil else {
            throw ActionExecutorError.invalidURL(raw)
        }
        guard NSWorkspace.shared.open(url) else {
            throw ActionExecutorError.invalidURL(raw)
        }
    }

    // MARK: - Shell

    private static func runShell(_ command: String) async throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ActionExecutorError.shellFailed(exitCode: -1, stderr: "Empty command")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", trimmed]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw ActionExecutorError.shellFailed(exitCode: -1, stderr: error.localizedDescription)
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ActionExecutorError.shellFailed(exitCode: process.terminationStatus, stderr: stderr)
        }
    }
}
