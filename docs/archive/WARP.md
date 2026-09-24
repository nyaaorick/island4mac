# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

- Native macOS menu bar / notch overlay app built with Swift, SwiftUI, and AppKit.
- Xcode project: `Mac灵动岛.xcodeproj` with a single app target and product also named `Mac灵动岛`.
- No unit test targets or external package dependencies are currently defined.
- Several files and folders (for example ` Controllers`, ` MacNotchIslandApp.swift`, and `Views/ NotchOverlayView.swift`) intentionally have leading spaces in their names; include those spaces when referencing these paths in tools or commands.

## Build, Run, and Tooling

### Open the project

- Open in Xcode: `open 'Mac灵动岛.xcodeproj'`
- Or open the entire folder in Xcode: `xed .`

### Build and run (via Xcode GUI)

- Select the `Mac灵动岛` scheme (it matches the app target name) and use Xcode's standard **Run** action to build and launch the app.
- The app is implemented as a menu bar / overlay utility: it does not create a normal main window; its main functionality appears as a small overlay near the notch plus a status bar item.

### Build from the command line (requires full Xcode)

If full Xcode is installed (not just Command Line Tools), you can build with:

- `xcodebuild -project 'Mac灵动岛.xcodeproj' -scheme 'Mac灵动岛' -configuration Debug -destination 'platform=macOS' build`

Adjust the configuration or destination as needed. If the scheme or target is renamed, update the `-scheme` argument accordingly.

### Linting and formatting

- There is no SwiftLint, swift-format, or other lint/format configuration checked into the repo.
- Use Xcode's built-in formatting and warnings, or any local tools you prefer; there is no project-specific lint command to run.

### Testing

- The Xcode project currently has no test targets defined, and there are no test source files in the repository.
- As a result, there is no project-specific "run tests" or "run a single test" command yet.
- When tests are added in the future, they should be run via Xcode's **Test** action or `xcodebuild test` with the appropriate scheme and destination.

## High-Level Architecture

### Entry point and lifecycle

- ` MacNotchIslandApp.swift`
  - Declares the `@main` SwiftUI `App` type `MacNotchIslandApp`.
  - Uses `@NSApplicationDelegateAdaptor(AppDelegate.self)` to delegate application lifecycle and main behavior to `AppDelegate`.
  - Defines only a `Settings` scene with an `EmptyView` of zero size, because the app is designed to run without a traditional main window.

- `AppDelegate.swift`
  - Owns a single shared `AppState` instance (`private let appState = AppState()`).
  - Creates and holds an `OverlayWindowController` that hosts the SwiftUI overlay UI.
  - On `applicationDidFinishLaunching`:
    - Sets `NSApp.setActivationPolicy(.accessory)` so the app behaves like a menu bar utility and does not appear in the Dock.
    - Instantiates `OverlayWindowController(appState:)` and immediately calls `show()` to display the overlay near the notch.
    - Subscribes to `NSApplication.didChangeScreenParametersNotification` to reposition the overlay if displays or resolutions change.
  - On `applicationWillTerminate`, removes notification observers.
  - Implements `applicationSupportsSecureRestorableState` and returns `true`.

### Global state and localization

- `State/AppState.swift`
  - Central observable model (`final class AppState: ObservableObject`) for the overlay's UI and behavior.
  - Defines:
    - `OverlayMode` enum (`compact` / `expanded`) to control the visual density of the island.
    - `Payload` enum (`none`, `file(URL)`, `url(URL)`, `text(String)`, `clipboard(String)`) representing what the island is currently showing.
  - Published properties:
    - `overlayMode: OverlayMode` – controls compact versus expanded layout.
    - `payload: Payload` – the current content.
    - `hint: String?` – transient hint or status text.
    - `lastCopiedAt: Date?` – timestamp used to decide when to temporarily show a "copied" hint.
  - Update APIs (intended for controllers/managers to call):
    - `updateClipboard(text:)`, `updateFile(url:)`, `updateURL(_:)`, `updateText(_:)`, `clear()`, `markCopied()`.
    - Each method sets the `payload`, adjusts `overlayMode`, and sets or clears hints as appropriate.
  - Derived, localized UI text:
    - `localizedTitle`, `localizedSubtitle`, `localizedPrimaryButton`, `localizedSecondaryButton`, `localizedHint`, and `payloadSummary` compute strings from `payload` and `lastCopiedAt` using localized string keys.
  - Uses a small helper `L(_ key: String) -> String` which simply calls `NSLocalizedString(key, comment: "")`.

- `SupportingFiles/Localizable.strings (English)` and `SupportingFiles/Localizable.strings (Chinese)`
  - Contain parallel localized strings for all of the keys used by `AppState` and the overlay view.
  - Keys include high-level titles (`title_drop_here`, `title_file`, `title_url`, `title_text`, `title_clipboard`), subtitles, button labels (`btn_primary`, `btn_open`, `btn_copy`), and hints (`hint_drop_received`, `hint_clipboard_updated`, `hint_copied`).
  - When changing UI copy or adding new visible text, prefer to add keys here and reference them via `NSLocalizedString` or the `L` helper in `AppState`.

### Overlay window and status bar integration

- ` Controllers/ OverlayWindowController.swift`
  - Owns and configures the actual `NSWindow` that displays the SwiftUI notch overlay.
  - Wraps a custom nested `PassthroughWindow` subclass of `NSWindow` with:
    - `canBecomeKey` and `canBecomeMain` returning `true` so the overlay can accept focus and interactions.
    - Borderless, transparent window style, with `.statusBar` level and `collectionBehavior` including `.canJoinAllSpaces` and `.fullScreenAuxiliary` to keep it visible across spaces and alongside full-screen apps.
    - `ignoresMouseEvents = false` so the overlay can be interacted with and accept drag/drop.
  - Initializes by:
    - Creating the window with a fixed `width` and `height` tuned for a notch-like island.
    - Creating a `NotchOverlayView()` and injecting `appState` as an `environmentObject`.
    - Hosting the SwiftUI view in an `NSHostingView` and assigning it as `contentView`.
    - Calling `positionAtNotch()` once to move the window to the top center of the main screen.
  - Public API:
    - `show()` – positions the window and orders it front / key, activating the app.
    - `hide()` – hides the window.
    - `showTemporarily(seconds:)` – shows the window and schedules an auto-hide after a delay via a `DispatchWorkItem`.
    - `positionAtNotch()` – computes a rect centered horizontally at the top of `NSScreen.main`, offset slightly downward to visually align with the menu bar / notch.
  - Internally manages `autoHideWorkItem` to cancel or schedule auto-hiding behavior.

- ` Controllers/StatusBarController.swift`
  - Manages the NSStatusBar item and menu for the app.
  - Holds references to `AppState`, `OverlayWindowController`, and the `NSStatusItem` created from `NSStatusBar.system`.
  - In `setup()`:
    - Configures the status bar button (currently with the simple text icon `"◎"`).
    - Wires button action and menu items (Toggle/Show/Hide/Quit) to Objective‑C `@objc` methods that call into the overlay controller.
  - Exposes simple actions that delegate to `overlayController` (`onToggle`, `onShow`, `onHide`, `onQuit`).
  - Note: `StatusBarController` expects `overlayController` to provide a `toggle()` method; at present `OverlayWindowController` implements `show()`, `hide()`, and `showTemporarily()` but not `toggle()`, so this API should be kept in sync during future edits.

### Clipboard and hotkey managers

- `Managers/ClipboardManager.swift`
  - Periodically polls `NSPasteboard.general` for changes and updates `AppState` whenever the clipboard text changes.
  - Internal state:
    - Keeps track of the last `changeCount` observed.
    - Holds an optional repeating `Timer` scheduled at 0.6‑second intervals.
  - `start()` sets up the timer (cancelling any existing timer first) and calls a private `tick()` method each time.
  - `tick()` compares `NSPasteboard.general.changeCount` to the cached value; if they differ and there is a non-empty string for type `.string`, it calls `appState.updateClipboard(text:)` on the main queue.
  - `stop()` invalidates and clears the timer.

- `Managers/HotKeyManager.swift`
  - Watches for a global keyboard shortcut and forwards it to the overlay controller.
  - Holds `AppState`, `OverlayWindowController`, and the opaque `monitor` handle returned by `NSEvent.addGlobalMonitorForEvents(matching:)`.
  - `start()`:
    - Removes any existing monitor, then registers a global monitor for `.keyDown` events.
    - When it sees Option + Space (modifierFlags contains `.option` and `keyCode == 49`), it calls `overlayController.toggle()`.
  - `stop()` removes the global event monitor if present.
  - When modifying the hotkey, adjust the key-detection logic here; keep in mind that key codes are hardware-specific, while modifier flags are bitmasks.

### SwiftUI overlay view

- `Views/ NotchOverlayView.swift`
  - SwiftUI view representing the content of the notch overlay.
  - Injected with `@EnvironmentObject private var appState: AppState` in `OverlayWindowController`.
  - Uses multiple `NSLocalizedString` calls for localized UI strings (titles, button labels, hints).
  - Layout:
    - `HStack` with a leading status `Circle`, vertical stack of main title and subtitle text, spacer, and trailing `HStack` of two `Button`s.
    - Styled with `.ultraThinMaterial` background, rounded corners, stroke border, and shadow to emulate a macOS "island".
  - Behavior and computed properties:
    - `isExpanded` is derived via reflection from `appState.overlayMode` to avoid compile-time coupling to a specific enum name; it treats any mode whose string description contains "expanded" as expanded.
    - `mainTitle` prefers any hint stored on `appState` (via reflection) and falls back to a localized "drop here" title.
    - `subTitle` prefers a `clipboardText` string on `appState` (if present) and otherwise falls back to localized support text.
    - `canOpenSomething` and `canCopySomething` check the derived `clipboardText` string to enable/disable the Open/Copy buttons.
    - `primaryOpenAction()` attempts to treat the clipboard text as a URL and open it via `NSWorkspace.shared.open`, then sets a localized "drop received" hint on `appState` via a reflective helper.
    - `copyAction()` writes the derived clipboard text back to the pasteboard and sets a localized "copied" hint.
  - Reflection helpers (`readStringProperty(named:)` and `setStringProperty(named:value:)`) are intentionally defensive: they allow the view to compile and run even if `AppState` evolves. When the data model stabilizes, consider replacing these with direct properties and explicit methods on `AppState`.

### Other SwiftUI views

- `Mac灵动岛/ContentView.swift`
  - Default SwiftUI template view created by Xcode (simple `Hello, world!` preview).
  - Currently not referenced by the main app (the app only uses a zero-sized `Settings` scene with `EmptyView`).
  - It is safe to ignore for runtime behavior; it can be repurposed later if you introduce a settings window or other configuration UI.
