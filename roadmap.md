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

Built: up to 6 tabs, out-of-process plugins drawn in the island's own look, the plugins repo (github.com/nyaaorick/island4mac-plugins) with the timer, Settings > Tabs and Settings > Plugins. Later:

- Install, update or remove one plugin without restarting the others.
- Compare versions by order, not just difference (no offering a downgrade as an update).
