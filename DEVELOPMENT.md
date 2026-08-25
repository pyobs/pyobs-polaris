# pyobs-polaris — development notes

A clean-room C++/QML client for pyobs 2.0, modeled directly on
**pyobs-web-client**: no dependency on pyobs-core, everything built from
presence + disco#info discovered live over the wire (QXmpp instead of
Strophe.js). Generic rendering by default; hand-written QML widgets opt in
per-interface where a custom UI earns its place (starting with `IRoof`).

Reference implementation to port from:

- `pyobs-web-client/src/pyobs-codec.ts` — value↔XML codec, schema parsing
- `pyobs-web-client/src/composables/useXmpp.ts` — connection, discovery,
  state subscription, RPC, presence
- `pyobs-web-client/src/components/ModuleStateCard.vue` + `KeyValueCard.vue`
  — generic rendering
- `pyobs-web-client/src/views/RoofView.vue` — the pattern for a
  custom, interface-specific widget built on top of the generic plumbing

Not vendored as a submodule or otherwise fetched by this repo — clone it
separately, next to this repo:
`git clone git@github.com:/pyobs/pyobs-web-client.git`.

Every completed feature in this project's history was verified against a real ejabberd server and
real running pyobs modules, not just unit tests — this project's whole premise is that the wire
protocol is the source of truth, not any particular language's in-memory model of it. Keep that
discipline for future work too.

## Status

Full design/decision history has moved to `specs/` — see `specs/index.md`. Environment setup, the
release process, and handoff notes now live in `specs/steering/`; every completed feature's
design decisions and gotchas now has its own doc under `specs/design/`; the one genuine
architectural decision (QML vs QtWidgets) is `specs/adrs/0001-qml-over-qtwidgets.md`. See
`TODO.md` for what's planned next — if a change reveals something neither `TODO.md` nor `specs/`
anticipated, fix those docs too, not just the code.

`pyobs-polaris` was renamed from `pyobs-gui++` (itself renamed from `pyobs-qml-client` during
Phase 0) — see the README for the one-line version of that history.

## Full history

The detailed phase-by-phase narrative this file used to carry inline is preserved in git history
rather than duplicated in both places — see `git log -p -- DEVELOPMENT.md`.
