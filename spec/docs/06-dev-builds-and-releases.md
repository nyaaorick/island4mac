# Dev builds and releases

## Two apps, one notch

Day to day you run the installed release: the DMG from GitHub in /Applications, updated by the app itself like everyone else's copy. Development happens in the dev app, which never touches it.

- Every Debug build (Xcode, `Launch.command`, the unit tests' host) is the dev app: bundle id `com.nyaaorick.island4mac.dev`, display name "island4mac Dev", `BuildConfig.isDevBuild`. Its settings are its own defaults domain, its plugins and their data are in `~/Library/Application Support/island4mac Dev` (`BuildConfig.supportFolder`), its agents helper and socket in `Application Support/com.nyaaorick.island4mac.dev`, its Keychain items under its bundle id, and macOS asks for its permissions separately. It never checks for updates.
- The installed release keeps `com.nyaaorick.island4mac`, `Application Support/island4mac` and `Application Support/com.nyaaorick.island4mac`: the real settings, clipboard history, shelf, plugins and catalog cache.
- A dev build quits the installed release when it starts and reopens it when it quits (`AppIntegration.quitInstalledRelease` / `reopenInstalledRelease`, Debug only; the release's path is kept in the dev app's defaults, so a dev build killed and rebuilt still brings it back). Stopping a dev build in Xcode kills it, so that one doesn't: the next dev build you quit normally does, or open the release yourself.
- Agent hooks follow whichever copy runs: on start, each points the connected agents' hooks at its own helper and socket (`refreshIfInstalled`), rewriting the hooks in the agents' config files.
- `island-plugin dev` installs into the release's plugins folder; `island-plugin dev --dev` into the dev app's.
- Anything new the app stores goes under a name the identity decides (the bundle id, `BuildConfig.supportFolder`), never a fixed one both copies would share.
- The bundle id was `com.macdynamicisland.app` until 2026-10-29 and changed while no release had users: a 1.1.0 copy won't take an update signed under the new id and is reinstalled from the DMG once, granting its permissions again. The support folder was renamed from `MacDynamicIsland` to `island4mac` the same day. `BuildConfig.supportFolder` moves the old folder once when the new one doesn't exist yet, so plugins and their data stay.

## Building

| Command | Does |
|---|---|
| `open island4mac.xcodeproj` | Xcode, scheme `island4mac` |
| `xcodebuild -project island4mac.xcodeproj -scheme island4mac -destination 'platform=macOS' build` | Build |
| `xcodebuild -project island4mac.xcodeproj -scheme island4mac -destination 'platform=macOS' test` | Unit tests (hosted by the app, which skips its launch setup under XCTest) |
| `Launch.command` | Builds the dev app into `build/` and opens it, quitting a dev build already running. A Swift script |
| `Release.command` | Builds the release DMG into `build/Release/`; `--publish` publishes it. A Swift script |

## Signing and updates

A release is `island4mac.dmg` on the GitHub release `v<version>`. There is no paid Apple developer account, so the app is signed with a self-signed certificate and not notarized.

- The certificate "island4mac Release" (self-signed, valid until 2046, SHA-1 `0549e796d95b726aaf3976ba02629b29b8367590`) is in the maintainer's login keychain, with a backup in `~/.island4mac-release-keys/` (the .p12 and its password; keep a copy in a password manager). On another Mac: `security import island4mac-release.p12 -k ~/Library/Keychains/login.keychain-db -P <password> -T /usr/bin/codesign`. Never make a new one, and never change the bundle id: the designated requirement is `identifier "com.nyaaorick.island4mac" and certificate leaf = H"<that SHA-1>"`; installed copies take only updates that satisfy it, and macOS ties the app's permissions to it. `Release.command` refuses a build signed any other way.
- `UpdateClient` downloads the latest release's first `.dmg` asset, mounts it, copies the app out with `ditto`, checks its signature against the running app's designated requirement and its version against the tag, swaps it in for the running app (at the running app's path, whatever the bundle is called) and relaunches it. Anything that fails leaves the installed app as it was and offers the release page instead.
- Only the first install meets Gatekeeper (Open Anyway). Updates are downloaded by the app itself, so they carry no quarantine.
- Debug builds never check. A Release build signed some other way is offered updates but refuses to install them.
- The Hardened Runtime stays on without library-validation exceptions: nothing third-party loads into the app. A framework added to it would need `com.apple.security.cs.disable-library-validation`, because a self-signed app has no Team ID.
- Verified on macOS 26 with release 1.1.0; the first real self-update also confirms macOS's App Management protection leaves the app alone (an update failing with "prevented from modifying apps" would be that).

## Releasing

The procedure is `spec/skills/release/SKILL.md`. In short: raise `MARKETING_VERSION`, add the version's section at the top of `spec/docs/08-changelog.md` (the release notes; `--publish` refuses a version without one), update `02-current-state.md` and `07-roadmap.md`, commit and push, `./Release.command`, try the DMG as a user would, `./Release.command --publish`, then let the installed copy update itself.
