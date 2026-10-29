---
name: spec-maintenance
description: How to edit documents and skills under spec/ so they stay accurate, in English, and the one source for what they cover.
---

# Spec maintenance

`spec/README.md` lists every document and skill and the conventions. This skill is the checklist for an edit.

## Where a change goes

| Change | Document |
| --- | --- |
| A new goal, principle or non-goal | `01-goals.md` |
| Something shipped or removed | `02-current-state.md` (facts, with the date or version) |
| A module, boundary, run-time behaviour, or something easy to break | `03-architecture.md` |
| A message, field, event, limit or version of the protocol | `04-plugin-protocol.md` (the only place; the plugins repo's README links here) |
| The catalog's index, installing, what the island keeps for a plugin | `05-plugin-hub.md` |
| Dev app, signing, updates, release procedure | `06-dev-builds-and-releases.md` and `skills/release` |
| Status, deferred items | `07-roadmap.md` |
| What users will notice in the next release | `08-changelog.md`, under the next version |

## Rules

- English only. Short sentences. Say what is, not what used to be, except in `08-changelog.md`.
- A superseded decision is rewritten in place with its new reason, not appended as a note.
- A fact about macOS behaviour names the version it was seen on, or says "unverified".
- A code comment that cites a document does so by file and heading; renaming a heading means updating the comment.
- Skills have `name` and `description` frontmatter, are imperative, and point at the document that holds the reasoning instead of repeating it.
- Root docs stay as they are: `README.md` for users (short), `CLAUDE.md` one screen pointing here. No other markdown outside `spec/`.
