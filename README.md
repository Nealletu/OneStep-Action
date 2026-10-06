# OneStep Action

Native macOS menu bar global hotkey tool.

**Apple Silicon Mac only.**

## Requirements

- macOS 26.0+
- Apple Silicon (arm64)
- Xcode 26+ / Swift 6+

## Features (MVP)

- Global shortcuts via `CGEventTap` (no polling, no third-party frameworks)
- Actions: Lock Screen, Launch Application, Open URL, Shell Command
- Shortcut recorder (⌘ ⌥ ⇧ ⌃ + keys)
- Enable / disable, add / edit / delete
- Import / export shortcut config as JSON (import merges, skips duplicates/conflicts)
- Conflict detection with honest limits (never claims 100% third-party coverage)
- Accessibility permission flow
- Launch at Login via `SMAppService`
- Light / Dark, system localization (en / zh-Hans)
- Liquid Glass–friendly native SwiftUI UI (no custom fake glass)

## Build

```bash
cd /Users/imps/Desktop/onestep
xcodegen generate
xcodebuild -project OneStepAction.xcodeproj -scheme OneStepAction -configuration Release build
```

Verify ARM64-only:

```bash
file "build/Release/OneStep Action.app/Contents/MacOS/OneStep Action"
lipo -info "build/Release/OneStep Action.app/Contents/MacOS/OneStep Action"
```

## Run

1. Launch `OneStep Action.app`
2. Grant **Accessibility** when prompted
3. Menu bar → Shortcut Settings → add `⌘L` → Lock Screen
4. Press `⌘L` to lock

## Architecture

```
SwiftUI Views
    ↓
AppModel
    ↓
GlobalShortcutManager (CGEventTap)
    ↓
ShortcutBinding → ActionExecutor → Action
```

- UI never talks to CGEvent / shell directly
- Action is an enum — new actions do not require event-tap changes
- Conflict detector is separate and never overclaims

## Notes

- Lock Screen: macOS has no public lock API. Resolves `SACLockScreenImmediate` from `login.framework` via runtime `dlsym` (Hammerspoon/Raycast approach). Not ⌃⌘Q keystroke simulation. System `LockScreen.app` is ARD-only.
- App is not sandboxed (required for CGEventTap + user shell commands)
- No network, no account, no telemetry
