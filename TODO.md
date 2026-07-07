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

## Custom widget for `IAutoGuiding`

`IAutoFocus`'s (`AutoFocusView.qml`) and `IAcquisition`'s
(`AcquisitionView.qml`) own widgets are both done - see `DEVELOPMENT.md`'s
"Custom widget: `IAutoFocus`" and "Custom widget: `IAcquisition`"
sections for the design decisions (plotting library choice, `PlotItem`
and its full property surface, real-parameter RPC calls, the
`FocusFoundEvent` JID-format gotcha, the RowLayout side-by-side-plots
gotcha) and reuse all of it here, not just the pattern described below.

**Goal:** a dedicated page for this last interface, the same pattern as
`RoofView.qml`/`IRoof`, `AutoFocusView.qml`/`IAutoFocus`, and
`AcquisitionView.qml`/`IAcquisition` - a sidebar entry conditionally
visible only while a connected module implements `IAutoGuiding`
(`ModuleListModel::hasInterface`), reachable as its own page. Port
`pyobs-gui`'s (the Python/PySide6 client) `pyobs_gui/autoguidingwidget.py`
(`AutoGuidingWidget`) for the actual behavior/layout to match, not
reinvent: subscribes `IRunning`+`IExposureTime`+`IAutoGuiding` state;
"Start"/"Stop" buttons plus a live-editable exposure-time spin box; two
plots (offset magnitude over a bounded sample history, and the 2D offset
scatter, latest-sample only - no "start" marker, unlike
`AcquisitionView.qml`'s trajectory plot, since a rolling history has no
meaningful fixed first point).

`PlotItem` (`src/plot/PlotItem.h/.cpp`) already grew everything
`AcquisitionView.qml` needed (`showLine`, `equalAspect`,
`originCrosshair`, `showStartMarker`/`showLatestMarker`,
`xFieldIndex`/`yFieldIndex`, `xTicksAsIntegers`) and this widget's two
plots map onto the exact same feature set (just `showStartMarker: false`
for the offset scatter) - **no further PlotItem changes expected**,
unlike the jump from `IAutoFocus` to `IAcquisition`. If AutoGuiding's own
live verification turns up something PlotItem genuinely can't do, treat
that as a real surprise worth its own writeup, not an assumed gap.

- Stack the two plots vertically in the page, not side by side in a
  shared `RowLayout` - seemed like the obvious choice for parity with
  `autoguidingwidget.py`'s `plt.subplots(1, 2)` layout, but
  `AcquisitionView.qml` hit a real, reproducible `RowLayout` bug doing
  exactly this (see `DEVELOPMENT.md`): two `Layout.fillWidth: true`
  children of a `RowLayout`, nested inside a `Repeater` delegate inside a
  `ColumnLayout` `StackLayout` page, did not split space evenly - one
  child claimed nearly all the width, confirmed with plain debug-colored
  `Rectangle`s standing in for `PlotItem`, so it wasn't a `PlotItem`-
  specific cause. Vertical stacking via plain `ColumnLayout`
  `Layout.fillWidth` (what every other page already does successfully)
  sidesteps it entirely - don't re-attempt the side-by-side layout here
  without first understanding *why* `RowLayout` broke, or it'll cost
  another multi-hour live-debugging detour.
- `autoguidingwidget.py`'s bounded sample history (`_HISTORY_LENGTH =
  50`, a `deque`) is itself only a *client-side* display cap over what's
  likely a continuous append-only wire state - confirm against the real
  `GuidingState`/`IAutoGuiding` schema (don't assume it already caps
  itself server-side) before deciding whether `PlotItem` needs its own
  bounded-history trimming or whether the QML side should do it before
  ever handing points to `PlotItem`.
- Wrap the page in a `ScrollView` from the start (see
  `AcquisitionView.qml`) rather than a plain `ColumnLayout` - two stacked
  220px-tall plots plus buttons/labels reliably exceeds a typical window
  height, and content silently clips at the bottom without one.
