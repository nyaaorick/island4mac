# Roadmap

## Next

- Wire up the settings that exist in the UI but have no effect yet: menu bar icon toggle, window shadow, lighting effect, gradient background, colored spectrum, control slot limit, slider color, show on all displays and the display picker, settings icon in the notch, idle face, notch height, remember last tab.
- Add AppIcon images (the asset set is empty).
- Implement the QQ Music lyrics source (`LyricsClient` is a stub).

## Later

- Fall back gracefully if Apple closes the MediaRemote adapter path (now playing would stop working).
- Show apps that don't report to the system Now Playing.
- Customizable keyboard shortcuts (currently fixed).
- Volume waveform visualizer for the music view.
- Notarize releases (needs a paid Apple developer account), so the first launch needs no Open Anyway.

## Plugins

Built: up to 6 tabs, out-of-process plugins drawn in the island's own look, the plugins repo (github.com/nyaaorick/island4mac-plugins) with the timer, Settings > Tabs and Settings > Plugins. IslandKit, the Swift SDK and `island-plugin` tool there (declarative body, @State, @Stored, CLI with live reload, CI that releases and indexes plugins); plugin preferences (protocol 2); on-demand plugins with timelines and @Fetched (protocol 3); pictures, row actions, background and high-priority plugins (protocol 4); cards, drops and media (protocol 5). Music, Clipboard, Files and Agents ship as bundled plugins. Installing, updating or removing one plugin restarts only that one. Later:

- Label the bundled plugins' choices (IslandKit shows an option's value: "24" rather than "24 hours").
- Write the oldest protocol a plugin's content needs into its plugin.json (Media needs 5; today only the declarations count).
- A native UI for plugins that need more than the protocol (a UI bundle loaded into the app, with library validation off).
- Compare versions by order, not just difference (no offering a downgrade as an update).
- Keep what an on-demand plugin last showed across app launches, so it needn't run once at launch.
