# pyobs-gui++ — todo

What's planned next. See `DEVELOPMENT.md` for how to build, and for the
design decisions/gotchas behind everything already done (Phases 0–7.5).

Each item below should be its own PR/commit, buildable and runnable on its
own before moving to the next, and verified against a live ejabberd server
and real pyobs modules — not just unit tests. Never assume the schema
shape from memory of the Python/TS side; verify against source and the
real wire protocol. If an item's design turns out to need something not
anticipated here, fix this doc, don't just fix the code.

---

## Phase 8 — WebAssembly build

**Goal:** the same client, browser-deployable.

- Second Conan profile (Emscripten toolchain) alongside the native one —
  don't retrofit the native CMake setup for this later; get the second
  profile building (even just "hello world" Qt Quick in a canvas) before
  porting any XMPP code, to isolate WASM-specific build pain from protocol
  pain.
- Networking: raw `QXmppClient::connectToServer` (the native TCP path)
  does not work in a browser sandbox — this is where the WebSocket
  transport actually becomes necessary, same reasoning as `useXmpp.ts`'s
  `buildWsUrl()`/`wss://` handling.
- Threading: decide single-threaded vs. multithreaded WASM now, since it
  determines whether the deployment needs `Cross-Origin-Opener-Policy`/
  `Cross-Origin-Embedder-Policy` headers (`SharedArrayBuffer` requirement)
  — a hosting-environment constraint worth confirming works with wherever
  this actually gets deployed (SAAO's infrastructure) before committing to
  the multithreaded path.

**Acceptance:** the built `.wasm`/`.js`/`.html` bundle, served statically,
connects to the same ejabberd server the native build uses and renders the
same module list.

---

## Real parameterized command execution in Shell

**Goal:** `ShellView.qml`'s module → method → execute → log flow should
let you actually fill in command parameters and run them, the same way
`pyobs-web-client`'s `ShellView.vue` does — not just the current
all-null-params execution every entry point in this project uses so far
(see Phase 5/7.5 in `DEVELOPMENT.md`). Port `ShellView.vue`'s actual
parameter-entry behavior (per-`WireType` widgets: bool/enum/number/string)
rather than reinventing the UI from scratch.

- `ModuleListModel`'s `commands` role currently only exposes
  `{interface, name, paramCount}` (Phase 5) — needs to expose full
  `CommandSchema`s (param names/types/optionality) for real widgets to be
  built from.
- `codec::valueToXml` (Phase 5) already handles schema-aware encoding for
  non-null values; this is mostly new QML-side parameter UI plus wiring
  real values through `executeMethod` instead of `WireValue::null()` for
  every param.

---

## Real filtering on the Logs page

**Goal:** `LogsView.qml` gains real filtering (per-module checkboxes,
level filter, etc. — see `pyobs-gui`'s `mainwindow.py`'s `listClients`
checkbox list feeding `LogModelProxy` for the shape to port), beyond its
current single "All modules"/one-module `ComboBox`.

- `qml/widgets/LogFooter.qml` (the persistent bottom-of-window log tail,
  see `DEVELOPMENT.md`) is a **deliberate duplicate** of `LogsView.qml`'s
  current unfiltered rendering, not a shared component - once this lands,
  the two are expected to diverge (the footer stays a simple unfiltered
  tail; the Logs page gets the real filter UI), not be reconciled back
  into one.

---

## Custom widgets for `IAutoFocus`, `IAcquisition`, `IAutoGuiding`

**Goal:** dedicated pages for these three interfaces, the same pattern as
`RoofView.qml`/`IRoof` (Phase 7 in `DEVELOPMENT.md`) - a sidebar entry
conditionally visible only while a connected module implements the
interface (`ModuleListModel::hasInterface`), reachable as its own page
rather than folded into a generic view. Port `pyobs-gui`'s (the Python/
PySide6 client) existing widgets for the actual behavior/layout to match,
not reinvent:

- `pyobs_gui/autofocuswidget.py` (`AutoFocusWidget`) — subscribes
  `IRunning`+`IAutoFocus` state, listens for `FocusFoundEvent`; "Run Auto
  Focus"/"Abort" buttons (with count/step/exposure-time spin boxes); a
  scatter plot of focus points vs. metric, with the fitted focus drawn in
  once a result comes in.
- `pyobs_gui/acquisitionwidget.py` (`AcquisitionWidget`) — subscribes
  `IRunning`+`IAcquisition` state; "Acquire"/"Abort" buttons; result
  labels (RA/Dec/Alt/Az + offset); two plots (distance-to-target per
  attempt, and the 2D offset trajectory).
- `pyobs_gui/autoguidingwidget.py` (`AutoGuidingWidget`) — subscribes
  `IRunning`+`IExposureTime`+`IAutoGuiding` state; "Start"/"Stop" buttons
  plus a live-editable exposure-time spin box; two plots (offset
  magnitude over a bounded sample history, and the 2D offset scatter).

**This needs a charting solution first** - unlike the Python client's
matplotlib canvases, this project has no plotting capability yet. Wire
one up (verified rendering real data live, not just compiling) before or
as part of the first of these three widgets, since all three need it -
don't build three one-off/duplicated plotting approaches.

**Decided: hand-rolled `QQuickPaintedItem` (C++, `QPainter`), not a
library, not QML `Canvas`.** No external library:
- `QtCharts`/`QtGraphs` are both Qt Add-on modules under GPLv3-or-
  commercial only, no LGPL tier - unlike the rest of this project's stack
  (LGPL Qt Quick/Network/Xml, LGPL qxmpp, BSD qtkeychain), and pyobs-core
  itself is MIT. Using either would force pyobs-gui++ to GPL (or a paid
  Qt license) once distributed, even though this project has no LICENSE
  file yet - the module's license, not this project's, is what forces the
  issue.
- `QCustomPlot` has the same GPL-or-commercial problem. `Qwt` (Qwt
  License, an LGPL-derived license with a static-linking exception - more
  permissive than plain LGPL) avoids the license problem but is
  QWidgets-based, not Qt Quick/QML-native - would mean embedding a
  `QWidget` into an otherwise pure Qt Quick app via `QQuickWidget`, which
  sits awkwardly next to the planned WASM build (Phase 8).
- The plots needed (a focus-metric scatter; two 2-panel plots for
  acquisition/guiding - see the three widgets above) are simple enough
  (modest bounded data - `_HISTORY_LENGTH = 50` in
  `autoguidingwidget.py`, not high-frequency/large datasets) that a
  from-scratch renderer is a reasonable, one-time cost: axes, gridlines,
  markers (circle/square/star to match matplotlib's start/latest
  markers), legends, axhline/axvline reference lines, equal-aspect 2D
  scaling for the offset-trajectory plots.

`QQuickPaintedItem` over QML `Canvas`:
- Keeps plot data in C++ the whole way rather than crossing into QML/JS
  to be iterated for drawing - the same C++→QML boundary that caused the
  `Array.isArray()` bug fixed this session (see `DEVELOPMENT.md`'s "Roof
  state display bug" section). Not a repeat of that exact bug, but the
  same class of risk, avoided by not adding another JS-side consumer of
  C++-supplied list data.
- Testable the same way as everything else in this project:
  `paint(QPainter*)` (or the normalization/layout math it calls) can be
  unit-tested via Qt Test, e.g. drawing into an offscreen `QImage` and
  asserting on it - matching Phase 1.5's "Qt Test, not Catch2" discipline.
  A `Canvas`'s `onPaint` JS logic has no equivalent test path in this
  project; there's no QML test tooling anywhere in the tree.
- Cost either way, so not a factor in the decision: no framework help for
  axes/gridlines/legends/equal-aspect scaling - manual work under both
  options, just written in C++ instead of QML/JS.

- The `IRunning` state these all key off of is a separate subscription
  from the interface-specific state, same shape as `RoofView.qml`'s
  `IMotion` embed alongside `IRoof` - each of these pages needs (at
  least) two live `subscribeState()` calls, not one.
- `FocusFoundEvent` (autofocus) is Phase 6 event-subscription territory,
  not state - see `DEVELOPMENT.md`'s Phase 6 summary for the JSON-on-
  the-wire decode path, not `WireValue`.
- The Python widgets disable their action buttons based on
  `get_permitted_methods` ACL results (`self.permitted(...)`) - this
  project has no equivalent yet (`RoofView.qml`'s Open/Close/Stop are only
  ever disabled by `running` state, never by ACLs). Out of scope to add
  generically here; if these widgets need it, it's a new, separate
  capability, not something to assume already exists.
