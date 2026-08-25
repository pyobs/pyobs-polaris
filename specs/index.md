# Design history and planning

This project has its own `specs/` structure, following the pattern `pyobs-core` established first
(see `pyobs-core/CLAUDE.md`'s "Design history and planning" section) and mirroring
`pyobs-web-client`'s own `specs/` — but as its own tree, not folded into either. `pyobs-polaris` is
a substantial, independent codebase in its own right (C++/Qt/QML, its own hand-rolled wire-protocol
implementation, its own UI design space) and earns a full structure of its own.

- **`design/`** — living architecture/design docs, one per feature or subsystem. Kept around after
  landing (`status: implemented`), not deleted — check here before re-deriving the reasoning
  behind existing behavior. Almost entirely populated in one pass (2026-08-25) by splitting
  `DEVELOPMENT.md`'s former phase-by-phase history into one doc per shipped feature.
- **`plans/`** — implementation plans, checklist-style. Empty as of this split; see
  `plans/index.md` for why, and `TODO.md` (repo root) for what's actually planned next.
- **`adrs/`** — short decision records for choices that had genuine considered-and-rejected
  alternatives (MADR-lite: Context, Considered Options, Decision Outcome, Consequences).
- **`steering/`** — standing, topic-scoped contributor guidance (environment setup, releases,
  handoff notes — all migrated out of `DEVELOPMENT.md`, which used to carry this inline).

`DEVELOPMENT.md` (repo root) is now a short pointer into `specs/` plus a git-history escape hatch,
not a growing log — new design docs, plans, and ADRs belong in `specs/` going forward, the same
convention `pyobs-web-client` already follows.

## Cross-repo docs

Some design decisions are genuinely about the wire protocol or interfaces shared with
`pyobs-core`, not this repo alone — those live in `pyobs-core/specs/` (tagged with a `Repos:` line
naming this repo), per `pyobs-core/CLAUDE.md`'s "Cross-repo docs" section. `pyobs-core`'s
`specs/adrs/0010-pyobs-gui-stays-on-qtwidgets-not-qml.md` is a relevant cross-reference (the
mirror-image QtWidgets-vs-QML decision for `pyobs-gui`) — see `adrs/0001-qml-over-qtwidgets.md`
here for this repo's own version of that question.
