# Roadmap

## Next

- Wire up the settings that exist in the UI but have no effect yet: menu bar icon toggle, window shadow, lighting effect, gradient background, colored spectrum, control slot limit, slider color, shelf on/off, show on all displays and the display picker, enlarged drop area, settings icon in the notch, idle face, notch height, remember last tab.
- Add AppIcon images (the asset set is empty).
- Implement the QQ Music lyrics source (`LyricsClient` is a stub).

## Later

- Fall back gracefully if Apple closes the MediaRemote adapter path (now playing would stop working).
- Show apps that don't report to the system Now Playing.
- Customizable keyboard shortcuts (currently fixed).
- Volume waveform visualizer for the music view.

## Plugins

Built: up to 6 tabs, out-of-process plugins drawn in the island's own look, the plugins repo (github.com/nyaaorick/island4mac-plugins) with the timer, Settings > Tabs and Settings > Plugins. IslandKit, the Swift SDK and `island-plugin` tool there (declarative body, @State, @Stored, CLI with live reload, CI that releases and indexes plugins); plugin preferences (protocol 2); on-demand plugins with timelines and @Fetched (protocol 3). Installing, updating or removing one plugin restarts only that one. Later:

- Agents as a plugin (beta, Settings > Agents): pass the go/no-go checks in daily use, then make it the default and delete the native Agents views; then music, clipboard and files the same way.
- A native UI for plugins that need more than the protocol (a UI bundle loaded into the app, with library validation off).
- Compare versions by order, not just difference (no offering a downgrade as an update).
- Sign plugin builds with a Developer ID in the plugins repo's CI (they are ad-hoc signed now).
- Keep what an on-demand plugin last showed across app launches, so it needn't run once at launch.
