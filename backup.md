# Backup notes

- The old README and `docs/archive/` (about 100 progress reports, checklists and design notes, mostly out of date) were deleted. Restore anything from git history: `git show 22facba:docs/archive/<file>` or `git show 22facba:README.md`.
- The project was renamed from `Mac灵动岛` to `MacDynamicIsland` (folders, Xcode project, scheme, target, module). The bundle id `com.macdynamicisland.app` did not change, so permissions and settings carry over.
- The Application Support folders for the shelf and temporary files moved from `Mac灵动岛` to `MacDynamicIsland`; items parked in the old folder are not migrated.
- The Simplified Chinese localization (`zh-Hans.lproj`) and all Chinese comments, log messages and UI strings were removed; the app is English only.
- Design lineage: window physics and drag detection are modeled on boring.notch; now playing uses the same perl + MediaRemoteAdapter approach.
