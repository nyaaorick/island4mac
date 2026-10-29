# Specification and skills

`spec/` is the single home for everything in this repository that is not code: design documents under `docs/` and Claude Code skills under `skills/`. The root `README.md` is the user's install guide and stays short; `CLAUDE.md` is one screen that points here. The former `CLAUDE.md`, `roadmap.md`, `backup.md` and `BundledPlugins/README.md` were folded into these documents on 2026-10-29; git history keeps them.

## Documents

| Document | Says |
| --- | --- |
| [01-goals.md](docs/01-goals.md) | What island4mac is, its principles, and what it is not |
| [02-current-state.md](docs/02-current-state.md) | What ships today: features, bundled plugins, protocol version, requirements |
| [03-architecture.md](docs/03-architecture.md) | Layout of the code, how the app starts, how the island is drawn and animated, what is easy to break |
| [04-plugin-protocol.md](docs/04-plugin-protocol.md) | The plugin protocol: plugin.json, the JSON lines both ways, every version. The one source; IslandKit and the catalog follow it |
| [05-plugin-hub.md](docs/05-plugin-hub.md) | The hub: bundled plugins, the catalog's index.json, installing, updating, what the island keeps for a plugin |
| [06-dev-builds-and-releases.md](docs/06-dev-builds-and-releases.md) | The dev app beside the installed release, signing, the self-update, the release procedure |
| [07-roadmap.md](docs/07-roadmap.md) | What is next and what is deferred |
| [08-changelog.md](docs/08-changelog.md) | What each release changed, for users; `Release.command --publish` reads it |

## Skills

| Skill | Use when |
| --- | --- |
| [island4mac-workflow](skills/island4mac-workflow/SKILL.md) | Any change to this repo: rules, build and test commands, conventions |
| [plugin-protocol-change](skills/plugin-protocol-change/SKILL.md) | The protocol or IslandKit gains something |
| [bundled-plugin](skills/bundled-plugin/SKILL.md) | Changing or adding a plugin that ships in the app |
| [release](skills/release/SKILL.md) | Publishing a release |
| [spec-maintenance](skills/spec-maintenance/SKILL.md) | Editing anything under spec/ |

## Conventions

- English only.
- Documents are numbered in reading order: 01 says what is being built, 02 what exists, 03 to 06 how, 07 when, 08 what changed.
- A fact about macOS behaviour (a private API, a permission, a signing rule) names the macOS version it was seen on, or says "unverified".
- A decision is recorded with its reason and, where useful, the condition that would reopen it. A superseded decision is rewritten in place, not appended to.
- Skills live in `skills/<name>/SKILL.md` with `name` and `description` frontmatter. `.claude/skills` is a symlink to `spec/skills`, so Claude Code finds them.
- Code comments may point at a document section by file and heading, for example `spec/docs/03-architecture.md, "Glass"`. Renaming a heading means updating those pointers.
- The plugin protocol is documented once, in `04-plugin-protocol.md`. The plugins repo's README teaches IslandKit and links here for the wire format; it does not repeat it.
