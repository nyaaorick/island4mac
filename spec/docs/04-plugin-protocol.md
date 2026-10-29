# The plugin protocol

The one description of how a plugin and the island talk. IslandKit (the Swift SDK in the plugins repo) speaks it so a Swift plugin doesn't have to; a plugin in any other language speaks it directly. The app reads it in `island4mac/Plugins/Protocol/`; `PluginManifest.supportedProtocol` is the newest version the app speaks (7).

## A plugin is a folder

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
| `id` | Lowercase letters, digits, `-` and `_`. Must match the folder name; can't change once published |
| `name` | Shown on its tab and in Settings |
| `symbol` | An SF Symbol name for its tab |
| `command` | Program and arguments. A relative program is inside the plugin folder (`./timer`) and may not leave it. An absolute one is used as is, e.g. `["/usr/bin/python3", "main.py"]`. Runs in the plugin's folder |
| `protocol` | The oldest protocol version with everything it uses. An app that speaks an older one refuses the plugin |
| `version` | Compared with the catalog's index to offer updates (`Version`: number by number) |
| `description` | Optional. One line for the catalog and Settings |
| `preferences` | Optional, protocol 2. Settings the island draws for it (below) |
| `lifecycle` | Optional, protocol 3. `"onDemand"` runs it only when needed (below); the default is `"persistent"` |
| `background` | Optional, protocol 4. `true`: runs while turned on in Settings, even when its tab isn't one of the user's |
| `priority` | Optional, protocol 4. `"high"`: its compact content shows ahead of popups and music; the default is `"normal"` |
| `accepts` | Optional, protocol 5. `["files"]`: files, text and links can be dropped on its tab (`drop` events) |

The app runs the command while the plugin's tab is turned on (a `background` plugin: while it's turned on in Settings), and stops it when the tab is turned off.

- **Plugin to island:** one JSON object per line on **stdout**. Flush after every line. A line over 64 KB is dropped whole.
- **Island to plugin:** one JSON object per line on **stdin**.
- **Quitting:** when stdin closes, quit. A plugin still running 2 seconds after it's asked to stop is killed, with every process it started.
- **Crashes:** a plugin that exits is restarted. After 6 exits within a minute it is marked stopped, and the user can restart it.
- **Errors:** the last lines written to **stderr** are shown as the reason when a plugin stops.
- **Text limits:** text is cut at 200 characters; a row's subtitle at 600 (3 lines); a text field takes up to 1000. Up to 50 rows, cards and buttons; up to 4 actions per row; up to 1000 lyric lines.
- Lines that aren't valid JSON, or have an unknown `type`, are ignored. A `state` or a row `kind` the app doesn't know reads as none.

### Environment

| Variable | Value |
|---|---|
| `ISLAND_PROTOCOL` | Protocol version the app speaks |
| `ISLAND_PLUGIN_ID` | The plugin's id |
| `ISLAND_DATA_DIR` | A folder for anything the plugin keeps. It survives updates and is removed with the plugin. Don't write inside the plugin folder: updates replace it |
| `ISLAND_APP_VERSION` | The app's version |
| `ISLAND_APP_BUNDLE` | The app's bundle path |

## Plugin to island

Each message replaces what the plugin showed of that kind before.

| Message | Shows |
|---|---|
| `{"type":"compact","symbol":"timer","text":"04:59","progress":0.98}` | Beside the notch while the island is collapsed. `progress` (0 to 1) draws a ring. Protocol 4: `"image":{…}` in place of the symbol. Protocol 6: `"state":"working"` (or `attention`, `done`, `failed`) draws the symbol as that state |
| `{"type":"compact","symbol":"timer","until":1767225600,"total":300}` | A countdown the island runs itself, to `until` (seconds since 1970). `total` (seconds) fills the ring. Send it once, not every second |
| `{"type":"list","rows":[{"id":"r1","title":"5 min","subtitle":"Pomodoro","symbol":"play.circle"}]}` | Rows in the plugin's tab. A row with an `id` can be tapped. Protocol 4: `"image":{"file":"/path"}` (or `{"app":"com.apple.Safari"}`, `{"url":"https://…"}`) in place of the symbol, and `"actions":[{"id":"del:r1","title":"Delete","symbol":"trash"}]`, sent back as an `action` when tapped. Protocol 6: `"state"` draws the row as that state (a turning arc, a pulsing symbol, or the island's done and failed colors), with the subtitle's first line as the status line in that color; `"detail":"1:23"` is short text at the row's right edge. Protocol 7: `"kind":"section"` makes the line a heading over the rows after it (never tapped); `"progress":0.4` draws a ring around the symbol; `"toggle":true` draws a switch at the end, which sends the row's `action` like a tap does (then show the new value); an action's `"confirm":"Delete it?"` is asked first |
| `{"type":"cards","cards":[{"id":"c1","title":"Safari","subtitle":"now","image":{"app":"com.apple.Safari"},"preview":{"text":"let x = 1"},"file":"/path/a.pdf","actions":[…]}]}` | Protocol 5. Cards above the rows, scrolling sideways: a row's fields (`state` too, protocol 6) plus `preview` (`{"text":…}` or `{"image":{…}}`) and `file` (drags out as that file) |
| `{"type":"media","title":"Song","artist":"Artist","album":"Album","artwork":{"url":"https://…"},"app":"com.spotify.client","playing":true,"elapsed":42.0,"at":1767225600,"duration":215.0,"rate":1.0}` | Protocol 5. What plays, drawn with the island's own player and beside the notch. The island counts on from `elapsed` as of `at` (seconds since 1970; now if missing) at `rate`, and hides for a full-screen video of `app`. Its controls send `control` and `seek` |
| `{"type":"lyrics","lines":[{"time":12.3,"text":"…"}]}` | Protocol 5. The playing track's lyrics; lines with a `time` follow the song. A new track's `media` drops the old lyrics, so send them after it |
| `{"type":"buttons","buttons":[{"id":"stop","title":"Stop","symbol":"stop.fill","confirm":"Stop the timer?"}]}` | Buttons under the rows. With `confirm`, the island asks first. Buttons alone in a tab show larger, in its middle |
| `{"type":"input","id":"minutes","placeholder":"Minutes","text":""}` | One text field above the buttons |
| `{"type":"popup","symbol":"bell.fill","text":"Time's up","seconds":4}` | Beside the notch for 1 to 10 seconds (3 if not said), ahead of music |
| `{"type":"open"}` | Opens the island on the plugin's tab: at most every 10 seconds, only if the user allows it (Settings > Plugins), and never over something they're using. Protocol 4: `"hold":true` keeps it open (no auto-close) until `close` |
| `{"type":"close"}` | Protocol 4. Closes the island `open` held, unless the pointer is on it. Protocol 5: also closes an island the user opened on the plugin's tab, at once (after a paste) |
| `{"type":"clear","target":"compact"}` | Removes `compact`, `list`, `cards`, `media`, `lyrics`, `buttons`, `input` or `all` |
| `{"type":"status","state":"loading","text":"Updating"}` | Protocol 3. One standard row at the top of the tab: `loading` or `error`; `idle` removes it |
| `{"type":"timeline","entries":[{"at":1767225600,"show":[…]}],"wake":1767229200}` | Protocol 3. Each entry's messages (`compact`, `list`, `cards`, `media`, `lyrics`, `buttons`, `input`, `status`, `clear`) are shown at its time, by the island. At `wake`, the island starts the plugin again (at most every 10 seconds). Replaces the last timeline |
| `{"type":"done"}` | Protocol 3, on-demand plugins. Nothing more to do: the island stops the plugin, and what it showed stays, across app launches too |

Pictures (`image`) say only where they come from: a file path (the island makes a thumbnail), an app's bundle id (its icon), or an https URL (up to 5 MB). The island sizes, crops and caches them. A plugin never sets a color, a font or a layout.

Beside the notch, in order: high-priority plugins (Agents is one), then plugin popups, then music while it plays, then plugin compact content.

## Island to plugin

| Message | When |
|---|---|
| `{"type":"action","id":"r1"}` | A row, a row action, a toggle or a button with that id was tapped (after confirmation, if it asks for one) |
| `{"type":"submit","id":"minutes","text":"12"}` | Return was pressed in the text field |
| `{"type":"visible","tab":true}` | Its tab opened (`false`: closed). Also sent right after the plugin starts. Update often only while visible |
| `{"type":"preferences","values":{"apiKey":"…","minutes":5}}` | Protocol 2. Its settings, by key: sent first after it starts, and again when one changes |
| `{"type":"wake","reason":"action"}` | Protocol 3, on-demand plugins. Why it was started: `launch`, `visible`, `action`, `timeline` or `preferences`. Sent last, after its settings, visibility and the tap that woke it |
| `{"type":"drop","paths":["/Users/me/a.pdf"],"urls":["https://…"]}` | Protocol 5, to a plugin with `"accepts":["files"]`. What was dropped on its tab: files and folders as paths, text saved by the island as a file in the plugin's data folder (`Drops/`), links as URLs |
| `{"type":"control","command":"playPause"}` | Protocol 5, to a plugin that sends `media`. A tap on the player: `playPause`, `next` or `previous` |
| `{"type":"seek","position":80.5}` | Protocol 5. The progress bar was dragged to this many seconds into the track |

## Preferences (protocol 2)

```json
"preferences": [
  {"key": "apiKey", "title": "API key", "kind": "secure", "required": true},
  {"key": "minutes", "title": "Refresh every", "kind": "choice", "default": 5,
   "options": [{"title": "1 minute", "value": 1}, {"title": "5 minutes", "value": 5}]},
  {"key": "days", "title": "Days", "kind": "number", "default": 3, "minimum": 1, "maximum": 7}
]
```

`kind` is `text`, `secure` (hidden, kept in the Keychain), `toggle`, `number` (a slider when `minimum` and `maximum` are given) or `choice` (a menu of `options`, each shown by its `title`). A plugin has at most 20. The island draws them under Settings > Plugins and sends the values as the `preferences` event. With `required`, the plugin doesn't start until the value is filled in, and its tab points to Settings.

## On demand (protocol 3)

With `"lifecycle": "onDemand"`, the island starts the plugin only when it's needed: to show itself once the first time, when its tab opens, when something in it is tapped, at its timeline's `wake`, or when a preference changes. It sends what to show, then `timeline` and `done`. A plugin left running with its tab hidden and nothing to say is stopped after 30 seconds. One that exits with an error more than 5 times in a minute is marked stopped.

What it showed stays while it sleeps. The island keeps the last line of each kind it wrote in its data folder (`.shown.json`) and shows them again at the next app launch without running the plugin; a new build or an update of the plugin runs it once instead.

## Versions

| Protocol | Added |
|---|---|
| 1 | compact, list, buttons, input, popup, open, clear; action, submit, visible |
| 2 | `preferences` in plugin.json and the `preferences` event |
| 3 | `lifecycle` onDemand, `timeline`, `done`, `status`; the `wake` event |
| 4 | pictures on rows and compact content, row `actions`, `background`, `priority`, `open` with `hold`, `close` |
| 5 | cards, `accepts` and `drop`, `media` and `lyrics` with `control` and `seek`, `close` of a user-opened island |
| 6 | `state` on rows, cards and compact content; `detail` on rows |
| 7 | row `kind` section, row `progress`, row `toggle`, `confirm` on row and card actions |

A plugin declares the oldest version with everything it uses. Features that degrade well (a card shown as a row, an unknown state ignored) don't raise the version a plugin needs; IslandKit computes it from what the plugin declares and what its `body` shows (`Media` needs 5, since an older island shows nothing for it).

## A plugin in another language

```python
import json, sys
print(json.dumps({"type": "compact", "symbol": "sun.max", "text": "Hello"}), flush=True)
for line in sys.stdin:          # ends when the app closes stdin
    event = json.loads(line)
```

Any program works locally (Settings > Plugins > Install from File, or a folder in the plugins folder). The catalog's CI builds Swift packages; a plugin in another language is published with its binary already built, or by extending the CI (05-plugin-hub.md).
