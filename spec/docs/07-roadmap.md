# Roadmap

Status: `[ ]` not started, `[~]` in progress, `[x]` done. Done items move to `02-current-state.md` and `08-changelog.md` at the next release.

## Next

- [ ] Add AppIcon images (the asset set is empty).
- [ ] QQ Music as a lyrics source (`LyricsClient` reaches LrcLib and NetEase).
- [ ] Label the bundled plugins' choices where IslandKit's labelled options don't cover a case yet.
- [ ] A plugin's tab shows a quiet "update available" note that opens Settings > Plugins.

## Later

- [ ] Fall back gracefully if Apple closes the MediaRemote adapter path (now playing would stop working).
- [ ] Show apps that don't report to the system Now Playing.
- [ ] Customizable keyboard shortcuts.
- [ ] A volume waveform visualizer for the music view.
- [ ] Notarize releases (needs a paid Apple developer account), so the first launch needs no Open Anyway.
- [ ] A native UI bundle for plugins that need more than the protocol: only if a real plugin shows the protocol can't carry it (01-goals.md, "What it is not").
- [ ] Catalog CI for plugins in other languages (Go, Python): a `--prebuilt` path in `island-plugin publish` that takes a folder with the binary already built.

## Done in the restructuring (2026-10-29)

- [x] Product, project, scheme, folders and display name renamed to island4mac; bundle id kept; support folder moved once.
- [x] Dead settings, migrations, debug noise, upstream headers and unused strings removed.
- [x] Sources split by purpose: `Plugins/{Protocol,Runtime,Catalog,Views}`, `Music/`.
- [x] Hub: checksum-verified installs, install phases, Update All, Install from File, Finder and data folder from the row, cached catalog, sidebar badge, custom catalog address, richer index (sha256, size, author, homepage, updated).
- [x] On-demand plugins keep what they showed across launches.
- [x] IslandKit: labelled options, the protocol a `body` needs (Media is 5), `island-plugin dev --dev`, `publish` writes the richer index.
- [x] Docs and skills in `spec/`; the protocol documented once.
