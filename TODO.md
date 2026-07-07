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

## Custom widgets for `IAcquisition`, `IAutoGuiding`

`IAutoFocus`'s own widget (`AutoFocusView.qml`) is done - see
`DEVELOPMENT.md`'s "Custom widget: `IAutoFocus`" section for the design
decisions (plotting library choice, `PlotItem`, real-parameter RPC calls,
the `FocusFoundEvent` JID-format gotcha) and reuse all of it here, not
just the pattern described below.

**Goal:** dedicated pages for these two remaining interfaces, the same
pattern as `RoofView.qml`/`IRoof` (Phase 7) and `AutoFocusView.qml`/
`IAutoFocus` - a sidebar entry conditionally visible only while a
connected module implements the interface (`ModuleListModel::
hasInterface`), reachable as its own page rather than folded into a
generic view. Port `pyobs-gui`'s (the Python/PySide6 client) existing
widgets for the actual behavior/layout to match, not reinvent:

- `pyobs_gui/acquisitionwidget.py` (`AcquisitionWidget`) — subscribes
  `IRunning`+`IAcquisition` state; "Acquire"/"Abort" buttons; result
  labels (RA/Dec/Alt/Az + offset); two plots (distance-to-target per
  attempt, and the 2D offset trajectory).
- `pyobs_gui/autoguidingwidget.py` (`AutoGuidingWidget`) — subscribes
  `IRunning`+`IExposureTime`+`IAutoGuiding` state; "Start"/"Stop" buttons
  plus a live-editable exposure-time spin box; two plots (offset
  magnitude over a bounded sample history, and the 2D offset scatter).

`PlotItem` (`src/plot/PlotItem.h/.cpp`) only supports one scatter series
plus one vertical reference line today - deliberately minimal, built for
`AutoFocusView.qml` alone (see `DEVELOPMENT.md`). These two widgets need
more and should extend it rather than duplicate a second plot item:
- A connecting line between points, not just markers (both widgets plot a
  progression - distance-per-attempt, offset-magnitude-per-sample - not
  an unordered scatter).
- A second, differently-styled series for the 2D trajectory/offset plots
  (start marker, latest marker, connecting line, equal-aspect scaling -
  `ax.set_aspect("equal", adjustable="datalim")` in both Python widgets,
  no equivalent here yet).
- `acquisitionwidget.py`/`autoguidingwidget.py`'s 2D plots use plain
  gray `axhline(0)`/`axvline(0)` origin crosshairs with no legend, a
  visually different concept from `AutoFocusView.qml`'s single
  highlighted-with-a-label reference line - don't force both through the
  same `referenceX`/`referenceLabel` properties if they don't actually
  fit; a second, purpose-named property pair is fine.
- `autoguidingwidget.py`'s bounded sample history (`_HISTORY_LENGTH =
  50`, a `deque`) is itself only a *client-side* display cap over what's
  likely a continuous append-only wire state - confirm against the real
  `GuidingState`/`IAutoGuiding` schema (don't assume it already caps
  itself server-side) before deciding whether `PlotItem` needs its own
  bounded-history trimming or whether the QML side should do it before
  ever handing points to `PlotItem`.
