---
name: release
description: Publish an island4mac release: version, changelog, DMG, GitHub release, and the self-update check.
---

# Releasing

Background and the signing rules: `spec/docs/06-dev-builds-and-releases.md`. Nothing here is done on a dirty tree.

1. Raise `MARKETING_VERSION` of the `island4mac` target (Debug and Release) in `island4mac.xcodeproj/project.pbxproj`. Versions compare number by number (`Version`); only ever go up.
2. Add `## <version>` at the top of `spec/docs/08-changelog.md`: what changed, for users. It becomes the release notes; `--publish` refuses a version without it.
3. Update `spec/docs/02-current-state.md` (what ships now), `07-roadmap.md` (drop what's done), and `README.md` if features, install or requirements changed. Run the tests. Commit and push.
4. `./Release.command` builds and checks `build/Release/island4mac.dmg`. Try it as the release it will be: quit the installed copy, open the DMG and run the app from it (same identity, so your real settings and data), then quit it.
5. `./Release.command --publish` publishes it as `v<version>` (needs a clean, pushed commit and `gh` logged in).
6. Open your installed copy: it offers the update, installs it and comes back as the new version, its Accessibility and Automation permissions intact. You go through exactly what users do.

If the signing identity is missing, `Release.command` says so: import the backup from `~/.island4mac-release-keys/`; never make a new certificate.
