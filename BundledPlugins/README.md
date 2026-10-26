# Bundled plugins

The plugins that ship inside the app: `agents`, `clipboard`, `files` and `music`. They are ordinary IslandKit plugins, built with the app and updated with it. Users can turn them off under **Settings > Plugins** but can't remove them.

The first part covers what is different about a bundled plugin. The rest, from [Writing a plugin with IslandKit](#writing-a-plugin-with-islandkit) on, is the plugins repo's README (github.com/nyaaorick/island4mac-plugins), with only "this repo" and relative links reworded: keep the two the same when either changes.

## Where things are

```text
BundledPlugins/<id>/
  Sources/<Name>Plugin.swift   The IslandPlugin: what it shows, its preferences, taps. Kept thin
  Core/                        Its logic (stores, clients, monitors). Compiled into the plugin and into the app, so
                               MacDynamicIslandTests tests it. No SwiftUI, Settings or island types
  plugin.json                  Written by `<id> --describe`, never by hand
SharedCore/                    Protocol types the app and the plugins both use (PluginImage, PluginMedia), AppleScriptClient
```

IslandKit comes from the plugins repo as a local package (`../island4mac-plugins`), so clone both repos side by side.

## Building and running

There is no `island-plugin dev` for a bundled plugin. Build and run the app (Xcode, or `Launch.command`): the plugin targets build with it, their programs go into `Contents/Helpers/<id>` and their `plugin.json` into `Contents/Resources/Plugins/<id>`. The app finds them there before the plugins folder; an installed plugin with the same id is refused.

After changing anything that ends up in `plugin.json` (id, name, symbol, version, description, `@Preference`, `background`, `priority`, `lifecycle`, `acceptsDrops`), write it again:

```bash
build/Build/Products/Debug/MacDynamicIsland.app/Contents/Helpers/<id> --describe > BundledPlugins/<id>/plugin.json
```

`PluginTests.testEachBundledPluginDescribesItselfAsItsPluginJSON` fails when it is out of date.

## When it needs something new from the island

Add it in three places, in this order:

1. The app: `PluginMessage` / `PluginEvent`, the view that draws it, and `PluginManifest.supportedProtocol` if the protocol grows.
2. IslandKit in the plugins repo, and its README.
3. The bundled plugin.

The plugin must stay a plugin: it reaches the island only through the protocol, so the same feature works for anyone's plugin.

## Adding a bundled plugin

1. Write it as an IslandKit plugin in `BundledPlugins/<id>/`, with its logic in `Core/`.
2. In Xcode, add a macOS Command Line Tool target whose product is named after the id. Give it IslandKit, its `Sources/` and `Core/` folders and `SharedCore/`. Add `Core/` to the app target too (the tests are hosted by the app).
3. In the app target: make it depend on the new target, add its product to **Embed Helpers** (`Contents/Helpers`), and add a copy phase **Embed Bundled Plugin `<id>`** that copies its `plugin.json` to Resources at `Plugins/<id>`.
4. If it replaces a built-in tab, add it to `IslandTab.builtInTabsOfPlugins`. If it takes over old app settings, carry them over once in `AppIntegration.carrySettingsOver`.
5. Write its `plugin.json` with `--describe`, and run the tests.

## Writing a plugin with IslandKit

IslandKit is the Swift SDK in the plugins repo. You declare what the plugin shows; IslandKit runs it, shows the new `body` whenever your state changes and sends the island only what changed.

```swift
import IslandKit

@main
struct TimerPlugin: IslandPlugin {
    static let id = "timer"
    static let name = "Timer"
    static let symbol = "timer"
    static let version = "2.0.0"

    @State var end: Date? = nil
    @Stored("last-minutes") var lastMinutes: Int? = nil

    var body: some IslandContent {
        if let end {
            Countdown(to: end, total: 300, symbol: "timer")
            Alarm(at: end) {
                Island.popup("Time's up", symbol: "bell.fill")
                self.end = nil
            }
            Button("Stop", symbol: "stop.fill", confirm: "Stop the timer?") { self.end = nil }
        }
        Row("5 min", symbol: "play.circle") { end = Island.now.addingTimeInterval(300) }
    }
}
```

[`timer/` in the plugins repo](https://github.com/nyaaorick/island4mac-plugins/blob/main/timer/Sources/TimerPlugin.swift) is the complete version, with presets, a custom length, and pause and resume.

### Getting started

```bash
git clone https://github.com/nyaaorick/island4mac-plugins && cd island4mac-plugins
swift build -c release --product island-plugin     # the tool: .build/release/island-plugin
.build/release/island-plugin new my-plugin         # a package that builds and runs as it is
cd my-plugin && ../.build/release/island-plugin dev
```

`dev` builds the plugin, installs it into the app and turns it into a live preview. Every time you save, it builds and installs it again, and the app restarts it. Turn its tab on under **Settings > Tabs** to see it.

| Command | What it does |
|---|---|
| `island-plugin new <id> [--name] [--symbol]` | Creates a plugin package in `./<id>` |
| `island-plugin dev` | Builds, installs into the app, and does it again on every change |
| `island-plugin validate [--all]` | Builds and checks the id, name, symbol and version |
| `island-plugin build [--all]` | Builds it universal and signed into `build/<id>/` and `build/<id>.zip` |

You never write `plugin.json`: `build` and `dev` run your program with `--describe` and write it from your code.

### What a plugin can show

| Element | Shows |
|---|---|
| `Compact(symbol:text:progress:image:state:)` | Beside the notch while the island is collapsed. `progress` (0 to 1) draws a ring. One at a time; the last one in `body` wins |
| `Countdown(to:total:symbol:)` | A countdown beside the notch that the island runs itself. In place of a `Compact` |
| `Row(_:subtitle:symbol:image:state:detail:progress:id:actions:action:)` | A row in the plugin's tab. With an action it can be tapped. The subtitle shows up to 3 lines. `actions` are secondary actions (`RowAction("Delete", symbol: "trash", confirm: "Delete it?") { … }`), shown on hover and in its context menu; one with `confirm` asks first. `detail` is short text at the right edge (a time, a count); `progress` (0 to 1) a ring around the symbol. Up to 50 rows |
| `Section(_:symbol:detail:)` | A heading over the rows after it: a caption, never tapped |
| `Toggle(_:subtitle:symbol:isOn:id:set:)` | A row with a switch at its end. A tap on either hands `set` the other value; show it by changing what `isOn` is made from |
| `Card(_:subtitle:symbol:image:preview:file:state:id:actions:action:)` | A card: a row turned on its side, with a large `preview` (`.text(…)` or `.image(…)`). Cards sit in one row above the rows and scroll sideways. With a `file:` it drags out as that file. Up to 50. Older apps show them as rows |
| `Media(_:artist:album:artwork:app:playing:elapsed:at:duration:rate:lyrics:control:seek:)` | What plays, drawn with the island's own player (artwork, lyrics, progress, controls, spectrum) and beside the notch. Say where the track is (`elapsed` as of `at`); the island counts on by itself. `lyrics` are `LyricLine("…", at: seconds)`. Taps come back to `control` (`.playPause`, `.next`, `.previous`) and `seek` |
| `Button(_:symbol:confirm:id:action:)` | A button under the rows. With `confirm`, the island asks first. Buttons alone in a tab show larger, in its middle |
| `TextField(_:text:id:onSubmit:)` | The tab's one text field. Return hands its text to `onSubmit` |
| `Alarm(at:id:perform:)` | Shows nothing. Runs `perform` once when the time comes, as long as it's still in `body` |

`body` can use `if`, `if let`, `switch` and `for`. To reuse a piece, make a struct that conforms to `IslandComponent` and give it a `body`; pass it `$state` to let it change your `@State`.

A state (`state:` on a row, a card or a `Compact`) says what it is up to, and the island draws it: `.working` turns an arc in place of the symbol, `.attention` pulses the symbol (and a row's `detail`) in the island's attention color, `.done` and `.failed` color it. With a state, a row's first subtitle line is its status line, in that color. A plugin never picks a color, so every plugin's "needs you" looks the same. Older apps show the row as it is.

Pictures (`image:`) say only where they come from: `.file(path)` (the island makes a thumbnail), `.app(bundleID)` (that app's icon) or `.url("https://…")`. The island sizes, crops and caches them.

- **Ids:** taps reach the closure of the element that was tapped. Rows and buttons get an id from their place and title; give rows made in a loop an `id:` of their own so a tap still finds them when the list changes.
- **Text limits:** text is cut at 200 characters.

### State and effects

| API | Use |
|---|---|
| `@State var x = …` | A value the plugin changes. Changing it shows the new `body`. It must be `Codable` |
| `@Stored("key") var x = …` | Kept on disk in the plugin's data folder, across runs and updates |
| `Island.popup(_:symbol:seconds:)` | Shown beside the notch for 1 to 10 seconds (3 if you don't say) |
| `Island.open(hold:)` | Opens the island on the plugin's tab, at most every 10 seconds, if the user allows it. With `hold: true` it stays open, without closing on its own, until `Island.close()` (something waiting for an answer) |
| `Island.close()` | Closes the island open on the plugin's tab: one held open, unless the pointer is on it; one the user opened, at once (after a paste) |
| `Island.now` | The time `body` is rendered for. Use it rather than `Date()` |
| `Island.isTabVisible` | Whether the tab is open. Update often only while it is |
| `Island.dataDirectory` | A folder of the plugin's own |
| `Island.log(_:)` | Writes to stderr. If the plugin stops, the island shows the last lines as the reason |
| `await Shell.run("docker", ["ps"])` | Runs a program (found on PATH, or in Homebrew's and the system's folders; `Shell.which` tells) off the main thread and hands back its `status`, `output` and `error`. An on-demand plugin isn't stopped while one runs |
| `Island.refresh()` | Shows `body` again, when something other than @State changed (an object of your own, a server) |
| `func onStart()` | Called once when the plugin starts (not for `--describe`): start servers, timers, subscriptions |
| `static let background = true` | Runs while turned on in Settings, whether or not its tab is one of the user's |
| `static let priority = NotchPriority.high` | Its compact content shows ahead of popups and music |
| `static let acceptsDrops = true` + `func onDrop(paths:urls:)` | Files, text and links can be dropped on its tab. The island opens on it when a drag nears the notch, shows where to drop, and hands over files as paths, text saved as a file in the data folder (`Drops/`), and links |

### Settings

Declare a setting with `@Preference`. It shows in the app under **Settings > Plugins**, drawn like every other setting, and the plugin gets its value. The property's name is its key and its value is the default.

```swift
@Preference("API key", secure: true, required: true) var apiKey = ""   // hidden, kept in the Keychain
@Preference("Refresh every", options: [1, 5, 15]) var minutes = 5      // a menu
@Preference("Days", range: 1...7) var days = 3                         // a slider
@Preference("Celsius") var celsius = true                              // a switch
```

With `required: true`, the island doesn't start the plugin until it's filled in, and the plugin's tab points to Settings.

### Running only when needed

By default a plugin runs while its tab is on. With `static let lifecycle = Lifecycle.onDemand` it runs only when needed:

- its tab opens
- a row or button is tapped
- an `Alarm` or a `@Fetched` refresh is due
- a setting changes

Each time, it shows what it has, hands the island its timeline and quits. The island keeps showing what it left, and `@State` is saved until the next run.

```swift
var timeline: [Date] { [lunch, review] }   // times when body looks different
```

The island switches to `body` as rendered for each time in `timeline` by itself. During that render, `Island.now` is that time. A countdown, a calendar or a reminder therefore uses no process at all between changes. Leave `timeline` out if nothing changes on its own.

### Data from the web

`@Fetched` keeps JSON from the web fresh and cached. Opening the plugin shows the last result at once and refreshes it when it's older than `every`. While it loads with nothing to show, or if it fails, the island shows its standard "loading" or "couldn't load" row.

```swift
@Preference("City") var city = "Paris"
@Fetched(Forecast.self, from: "https://wttr.in/{city}?format=j1", every: .minutes(30)) var forecast

var body: some IslandContent {
    if let forecast { Compact(symbol: "sun.max", text: forecast.summary) }
    Button("Refresh") { $forecast.refresh() }
}
```

`{key}` in the address or a header is replaced by that `@Preference`'s value. `$forecast` gives `isLoading`, `error`, `updated` and `refresh()`. An on-demand plugin is woken for each refresh. [`github-status/` in the plugins repo](https://github.com/nyaaorick/island4mac-plugins/blob/main/github-status/Sources/GitHubStatus.swift) is a complete example.

### Which app versions it needs

`build` writes the oldest protocol the plugin needs into its `plugin.json`, and older versions of the app won't install it:

| Protocol | Needed for |
|---|---|
| 1 | Everything else |
| 2 | `@Preference` |
| 3 | `lifecycle = .onDemand` (`@Fetched` works with any version; the loading row needs 3) |
| 4 | `background`, `priority` (pictures and row actions work with any version; older apps leave them out) |
| 5 | `acceptsDrops` (cards work with any version, as rows on older apps; `Media` shows only on 5) |
| 6 | Nothing: `state` and `detail` work with any version, and show only on 6 |
| 7 | Nothing: `Section`, `Toggle` and `progress` work with any version (as plain rows before 7). A `RowAction` with `confirm` is left out on older apps, rather than run unasked |

### Publishing

Open a pull request on the plugins repo that adds your plugin's folder. CI tests IslandKit and builds every plugin. After merging, it builds each new version universal (arm64 and x86_64), ad-hoc signs it, attaches the zip to a GitHub release `<id>-<version>` and updates `index.json`. Bump `version` to publish an update; the id can't change once published.

Outside the plugins repo, depend on IslandKit with `.package(url: "https://github.com/nyaaorick/island4mac-plugins", from: "1.0.0")`; `island-plugin new` sets that up.

## The protocol

Plugins written without IslandKit, in any language, use the protocol directly.

### How a plugin works

A plugin is a folder:

```text
timer/
  plugin.json
  timer          the program (or a script with its interpreter in plugin.json)
```

```json
{
  "id": "timer",
  "name": "Timer",
  "symbol": "timer",
  "command": ["./timer"],
  "protocol": 1,
  "version": "1.0.0"
}
```

| Field | Meaning |
|---|---|
| `id` | Lowercase letters, digits, `-` and `_`. Must match the folder name |
| `name` | Shown on its tab and in Settings |
| `symbol` | An [SF Symbol](https://developer.apple.com/sf-symbols/) name for its tab |
| `command` | Program and arguments. A relative program is inside the plugin folder (`./timer`). An absolute one is used as is, e.g. `["/usr/bin/python3", "main.py"]` |
| `protocol` | The oldest protocol version with everything it uses. The app speaks up to `7` |
| `version` | Compared with `index.json` to offer updates |
| `preferences` | Optional, protocol 2. Settings the island draws for it (see below) |
| `lifecycle` | Optional, protocol 3. `"onDemand"` runs it only when needed (see below); the default is `"persistent"` |
| `background` | Optional, protocol 4. `true`: runs while turned on in Settings, even when its tab isn't one of the user's |
| `priority` | Optional, protocol 4. `"high"`: its compact content shows ahead of popups and music; the default is `"normal"` |
| `accepts` | Optional, protocol 5. `["files"]`: files, text and links can be dropped on its tab (`drop` events) |

The app runs the command, in the plugin's folder, while the plugin's tab is turned on (a `background` plugin: while it's turned on in Settings), and stops it when the tab is turned off.

- **Plugin → island:** one JSON object per line on **stdout**. Flush after every line.
- **Island → plugin:** one JSON object per line on **stdin**.
- **Quitting:** when stdin closes, quit. If the plugin is still running 2 seconds after it's asked to stop, it is killed, along with every process it started.
- **Crashes:** a plugin that exits is restarted. After 6 exits within a minute it is marked stopped, and the user can restart it.
- **Errors:** the last lines written to **stderr** are shown as the reason when a plugin stops.

#### Environment

| Variable | Value |
|---|---|
| `ISLAND_PROTOCOL` | Protocol version the app speaks |
| `ISLAND_PLUGIN_ID` | The plugin's id |
| `ISLAND_DATA_DIR` | A folder for anything the plugin keeps. It survives updates and is removed when the plugin is removed. Don't write inside the plugin folder: updates replace it |
| `ISLAND_APP_VERSION` | The app's version |

### Plugin → island

Each message replaces what the plugin showed of that kind before.

| Message | Shows |
|---|---|
| `{"type":"compact","symbol":"timer","text":"04:59","progress":0.98}` | Beside the notch while the island is collapsed. `progress` (0 to 1) draws a ring. Protocol 6: `"state":"working"` (or `attention`, `done`, `failed`) draws the symbol as that state |
| `{"type":"compact","symbol":"timer","until":1767225600,"total":300}` | A countdown the island runs itself, to `until` (seconds since 1970). `total` (seconds) fills the ring. Send it once, not every second |
| `{"type":"list","rows":[{"id":"r1","title":"5 min","subtitle":"Pomodoro","symbol":"play.circle"}]}` | Rows in the plugin's tab. A row with an `id` can be tapped. Up to 50 rows. The subtitle shows up to 3 lines. Protocol 4: `"image":{"file":"/path"}` (or `{"app":"com.apple.Safari"}`, `{"url":"https://…"}`) in place of the symbol, and `"actions":[{"id":"del:r1","title":"Delete","symbol":"trash"}]`, sent back as an `action` when tapped. `compact` takes an `image` too. Protocol 6: `"state":"working"` (or `attention`, `done`, `failed`) draws the row as that state: a turning arc, a pulsing symbol, or the island's done and failed colors, with the subtitle's first line as the status line in that color; `"detail":"1:23"` is short text at the row's right edge. A state the app doesn't know is ignored. Protocol 7: `"kind":"section"` makes the line a heading over the rows after it (its title, symbol and detail; never tapped); `"progress":0.4` draws a ring around the symbol; `"toggle":true` draws a switch at the end, which sends the row's `action` like a tap on the row does (then show the new value); an action's `"confirm":"Delete it?"` is asked first, like a button's |
| `{"type":"buttons","buttons":[{"id":"stop","title":"Stop","symbol":"stop.fill","confirm":"Stop the timer?"}]}` | Buttons under the rows. With `confirm`, the island asks first |
| `{"type":"input","id":"minutes","placeholder":"Minutes","text":""}` | One text field above the buttons |
| `{"type":"popup","symbol":"bell.fill","text":"Time's up","seconds":4}` | Beside the notch for 1 to 10 seconds, ahead of music |
| `{"type":"open"}` | Opens the island on the plugin's tab. At most every 10 seconds, only if the user allows it, and never over something they're using. Protocol 4: with `"hold":true` it stays open (no auto-close) until the plugin sends `{"type":"close"}` |
| `{"type":"close"}` | Protocol 4. Closes the island `open` held, unless the pointer is on it. Protocol 5: also closes an island the user opened on the plugin's tab, at once (after a paste) |
| `{"type":"cards","cards":[{"id":"c1","title":"Safari","subtitle":"now","image":{"app":"com.apple.Safari"},"preview":{"text":"let x = 1"},"file":"/path/a.pdf","actions":[…]}]}` | Protocol 5. Cards above the rows, scrolling sideways: a row's fields (`state` too, protocol 6) plus `preview` (`{"text":…}` or `{"image":{…}}`) and `file` (drags out as that file). Up to 50 |
| `{"type":"media","title":"Song","artist":"Artist","album":"Album","artwork":{"url":"https://…"},"app":"com.spotify.client","playing":true,"elapsed":42.0,"at":1767225600,"duration":215.0,"rate":1.0}` | Protocol 5. What plays, drawn with the island's own player and beside the notch. The island counts on from `elapsed` as of `at` (seconds since 1970; now if missing) at `rate`, and hides for a full-screen video of `app`. Its controls send `control` and `seek` |
| `{"type":"lyrics","lines":[{"time":12.3,"text":"…"}]}` | Protocol 5. The playing track's lyrics, up to 1000 lines; lines with a `time` follow the song. A new track's `media` drops the old lyrics, so send them after it |
| `{"type":"clear","target":"compact"}` | Removes `compact`, `list`, `cards`, `media`, `lyrics`, `buttons`, `input` or `all` |
| `{"type":"status","state":"loading","text":"Updating"}` | Protocol 3. One standard row at the top of the tab: `loading` or `error`; `idle` removes it |
| `{"type":"timeline","entries":[{"at":1767225600,"show":[…]}],"wake":1767229200}` | Protocol 3. Each entry's messages (`compact`, `list`, `cards`, `media`, `lyrics`, `buttons`, `input`, `status`, `clear`) are shown at its time, by the island. At `wake`, the island starts the plugin again (at most every 10 seconds). Replaces the last timeline |
| `{"type":"done"}` | Protocol 3, on-demand plugins. Nothing more to do: the island stops the plugin, and what it showed stays |

- **Text limits:** text is cut at 200 characters; a text field takes up to 1000.
- **Errors:** lines that aren't valid JSON, or have an unknown `type`, are ignored.
- **Beside the notch:** high-priority plugins come first (Agents is one), then plugin popups, then music while it plays, then plugin compact content.

### Island → plugin

| Message | When |
|---|---|
| `{"type":"action","id":"r1"}` | A row or button with that id was tapped (after confirmation, if it asks for one) |
| `{"type":"submit","id":"minutes","text":"12"}` | Return was pressed in the text field |
| `{"type":"visible","tab":true}` | Its tab opened (`false`: closed). Also sent right after the plugin starts. Update often only while visible |
| `{"type":"preferences","values":{"apiKey":"…","minutes":5}}` | Protocol 2. Its settings, by key: sent first after it starts, and again when one changes |
| `{"type":"wake","reason":"action"}` | Protocol 3, on-demand plugins. Why it was started: `launch`, `visible`, `action`, `timeline` or `preferences`. Sent last, after its settings, visibility and the tap that woke it |
| `{"type":"drop","paths":["/Users/me/a.pdf"],"urls":["https://…"]}` | Protocol 5, to a plugin with `"accepts":["files"]`. What was dropped on its tab: files and folders as paths, text saved by the island as a file in the plugin's data folder (`Drops/`), links as URLs |
| `{"type":"control","command":"playPause"}` | Protocol 5, to a plugin that sends `media`. A tap on the player: `playPause`, `next` or `previous` |
| `{"type":"seek","position":80.5}` | Protocol 5. The progress bar was dragged to this many seconds into the track |

#### Preferences in plugin.json

```json
"preferences": [
  {"key": "apiKey", "title": "API key", "kind": "secure", "required": true},
  {"key": "minutes", "title": "Refresh every", "kind": "choice", "default": 5,
   "options": [{"title": "1 min", "value": 1}, {"title": "5 min", "value": 5}]},
  {"key": "days", "title": "Days", "kind": "number", "default": 3, "minimum": 1, "maximum": 7}
]
```

`kind` is `text`, `secure` (hidden, kept in the Keychain), `toggle`, `number` or `choice`. A plugin has at most 20.

#### On-demand plugins

With `"lifecycle": "onDemand"`, the island starts the plugin only when it's needed: to show itself once after the app starts, when its tab opens, when something in it is tapped, at its timeline's `wake`, or when a preference changes. It sends what to show, then `timeline` and `done`. A plugin left running with its tab hidden and nothing to say is stopped after 30 seconds. One that exits with an error more than 5 times in a minute is marked stopped.

## A plugin in another language

```python
import json, sys
print(json.dumps({"type": "compact", "symbol": "sun.max", "text": "Hello"}), flush=True)
for line in sys.stdin:          # ends when the app closes stdin
    event = json.loads(line)
```

To publish one, its folder needs a `Package.swift` for CI to build, or open an issue to talk about other languages.
