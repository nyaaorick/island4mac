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

Built: tabs as a registry (up to 6), the plugin protocol with island-drawn templates, the sample timer, Settings > Tabs and Settings > Plugins. Left:

- Create the plugins repo (`nyaaorick/island4mac-plugins`, the default `pluginIndexURL`): one folder per plugin, reviewed by pull request, `index.json`, and a release zip per plugin with its program built universal (arm64 + x86_64).
- Publish the timer there.
