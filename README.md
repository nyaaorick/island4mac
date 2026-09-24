# Mac灵动岛 (Mac Dynamic Island)

A macOS menu bar app that turns the area around the MacBook notch into an interactive "Dynamic Island": now playing with lyrics, clipboard history, a drag-and-drop file shelf, calendar events and a scratchpad. It is based on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

## Features

- **Now playing**: track, artwork, playback controls and synced lyrics, both in the collapsed island and in the Music tab. Playback state comes from the system MediaRemote framework. Artwork and Apple Music lyrics fall back to AppleScript, and lyrics are also looked up on NetEase Cloud Music and LRCLIB.
- **Clipboard**: text, links, code and images you copy are kept (50 items for 24 hours by default), can be searched and filtered, and can be pasted back into the frontmost app.
- **Files shelf**: drag files onto the notch to park them. The shelf keeps security-scoped bookmarks and shows thumbnails and Quick Look previews.
- **Calendar**: upcoming events from EventKit, with a join button for online meetings.
- **Zone**: quick actions and a scratchpad.
- **Menu bar item** to show or hide the island, open Settings and quit.

## Requirements

- macOS 14.0 or later. The island sits under the notch on MacBooks that have one and at the top center of other screens.
- Xcode 26 or later to build.

## Build and run

Open the project, select the `Mac灵动岛` scheme, pick your team under Signing & Capabilities, and run:

```bash
open Mac灵动岛.xcodeproj
```

From the command line:

```bash
xcodebuild -project Mac灵动岛.xcodeproj -scheme Mac灵动岛 -destination 'platform=macOS' build
```

```bash
xcodebuild -project Mac灵动岛.xcodeproj -scheme Mac灵动岛 -destination 'platform=macOS' test
```

`build_test.sh` runs a clean Debug build and reports the warning count.

The unit tests in `Mac灵动岛Tests` are hosted by the app. When it runs as a test host, the app skips its launch setup (hotkeys, calendar access, clipboard polling and the menu bar item).

## Permissions

| Permission | Used for |
|---|---|
| Accessibility | Global keyboard shortcuts. Settings → General has a button to request it. |
| Calendar | Showing upcoming events. |
| Automation (Apple Events) | Reading lyrics and artwork from Music and Spotify, and pasting clipboard items through System Events. |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⇧⌘Space | Expand or collapse the island |
| ⌥⌘Space | Show or hide the island |
| ⌥⌘V | Open the island on the clipboard tab |

## Distribution

The app ships outside the Mac App Store. It is not sandboxed, because the MediaRemote framework and AppleScript control of other apps don't work in the sandbox. Sign it with a Developer ID certificate (Hardened Runtime is on) and notarize it. The entitlements are Apple Events and calendar access.

## Project layout

```text
Mac灵动岛/            App entry point (Mac灵动岛App.swift), Info.plist, entitlements, asset catalog
AppDelegate.swift     App delegate and AppIntegration, which starts the background managers
Controllers/          OverlayWindowController (the island panel) and StatusBarController (menu bar item)
State/                AppState, the shared UI state, plus interaction and visibility enums
Views/                NotchHomeView (root view) and the Music, Clipboard, Shelf, Calendar and Zone views
Views/Settings/       Settings tabs
Settings/             Settings window controller and the clipboard settings tab
Music/                MusicManager: playback state, controls, artwork and lyrics
Services/             Now playing (MediaRemote), lyrics, clipboard store, shelf persistence, thumbnails, Quick Look
Managers/             Clipboard polling, global hotkeys, drag detection, screens, analytics
Calendar/             EventKit access
Models/, ViewModels/  Now playing and shelf models and the shelf view model
Utilities/            Settings store (Defaults+Keys.swift), AppleScript, localization, logging and other helpers
Extensions/           Small AppKit and SwiftUI extensions
Mac灵动岛Tests/        Unit tests
docs/archive/         Notes from earlier development; kept for reference and mostly out of date
```

## How it starts

```text
Mac灵动岛App (@main)
├─ Settings scene → MainSettingsView
└─ AppDelegate.applicationDidFinishLaunching
   ├─ OverlayWindowController.shared   borderless panel at the notch hosting NotchHomeView
   │  ├─ AppState                       loads clipboard history, starts global drag detection
   │  └─ NowPlayingManager → MusicManager
   ├─ AppIntegration.start()            CalendarManager, ClipboardManager, HotKeyManager
   └─ StatusBarController               menu bar item
```

## Known limitations

- Starting with macOS 15.4, third-party apps can no longer read now-playing information through MediaRemote, so the music features may stay empty on current systems. boring.notch works around this with mediaremote-adapter.
- The AppIcon set has no images yet.
- Some settings aren't wired up yet and have no effect: the menu bar icon, shadow, lighting effect, gradient, colored spectrogram, music control slot limit and slider color toggles; "show calendar"; the shelf on/off toggle; the three gesture settings; showing on all displays; expanded drag detection; the settings icon in the notch; the idle face; notch height; and remembering the last tab.
- ⌥⌘L (position lock) and ⌥⌘M (move mode) are registered, but nothing reads the flags they toggle yet.

## License

No license file has been added yet. The project is derived from boring.notch, so check boring.notch's license terms before choosing one.
