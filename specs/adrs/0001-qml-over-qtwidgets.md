# QML over QtWidgets

status: accepted
date: 2026-08-25

Repos: pyobs-polaris (this decision); see also pyobs-core's
`specs/adrs/0010-pyobs-gui-stays-on-qtwidgets-not-qml.md`, the mirror-image decision for
`pyobs-gui` — that repo chose to *stay* on QtWidgets rather than migrate, for reasons specific to
migrating an existing 18-widget app. This decision was made independently, for a codebase built
from scratch, and reaches the opposite conclusion for reasons that don't conflict with that one.

## Context and Problem Statement

Polaris is modeled on `pyobs-web-client`, itself a reference for "what would a reactive,
schema-driven telescope UI look like." `pyobs-gui` (PySide6/QtWidgets) is the more literal port of
that same idea into a native desktop app. Before committing to QML, it's worth asking directly:
should this project be a QtWidgets rewrite instead — the more literal port of `pyobs-gui` — or is
QML the right call?

## Considered Options

- **QtWidgets** (PySide6-equivalent in C++, i.e. plain Qt Widgets) — the more literal port of
  `pyobs-gui`'s own architecture.
- **QML** — declarative, reactive bindings; the option actually built.

## Decision Outcome

**QML**, and not close. The deciding factor is that the wire protocol is schema-less and
discovered live (disco#info, not compile-time) — the generic-first rendering path
(`KeyValueCard.qml`, the module-list `Repeater`s) depends on the UI reacting declaratively to
whatever schema and state arrive over PubSub. QtWidgets would mean imperatively
creating/destroying widgets and rewiring signals every time a module's schema changes, instead of
a binding just re-evaluating. The plugin mechanism leans on this too:
`PluginLoader.qml` (see `specs/design/plugin-mechanism-step-2-external-qml-plugin-loading.md`)
loads external `.qml` files as plain text at runtime with no recompilation, which a C++/QtWidgets
plugin story couldn't match without embedding a scripting layer of its own.

### Consequences

- A handful of interface-specific widgets needed hand-rolling to match what `pyobs-gui` got for
  free from QtWidgets — e.g. the shell's autocomplete popup (`QCompleter` lives in `QtWidgets`,
  not usable from QML; see `specs/design/shell-rewrite-parameterized-command-execution.md`) and
  `CameraView.qml`'s cuts/tone-curve/colormap controls (see
  `specs/design/cameraview-image-controls-follow-up-auto-save-custom-cuts.md` and
  `specs/design/cameraview-image-controls-round-2.md`). A one-time tax on a few custom views, not
  a structural problem with the generic path that covers most of the app.
- Unlike `pyobs-gui`'s equivalent evaluation, this decision carried no migration cost — there was
  no existing widget inventory to port, no test suite whose coverage would need rebuilding under a
  different UI paradigm. That asymmetry is exactly why the two sibling clients reached opposite
  conclusions from a similar starting question; see pyobs-core's ADR 0010 above for the migration
  side of that comparison.
