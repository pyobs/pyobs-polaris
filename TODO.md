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

## IN PROGRESS: RoofView's KeyValueCard stuck on "(no value yet)"

**Bug, actively being debugged across machines - read this before touching
`StateSubscriptionManager`/`RoofView.qml`/`KeyValueCard.qml`.**

Symptom: on the Roof page, the `IMotion` state card never shows a value,
even after clicking Open/Close (which do execute successfully - RPC
works fine). This is the first time this exact display path
(`subscribeState` → `StateSubscription.value` → `KeyValueCard`) has ever
been checked against a real running module and a real display -
`RoofWidget`'s old TODO entry (removed when Dashboard was deleted, see
`DEVELOPMENT.md`) already flagged this as never visually verified, and
it looks like that gap was hiding a real bug the whole time.

**Confirmed working (via temporary diagnostic `qInfo()` logging added to
`src/comm/StateSubscriptionManager.cpp`, not yet removed):**
- `subscribe()` is called once with correct args (node
  `pyobs:state:roof:IMotion:1`, service `pubsub.localhost`).
- `subscribeToNode()` succeeds.
- The initial `fetchCurrentValue()` (`requestItems<WireValueItem>`)
  returns 1 item.
- `handlePubSubEvent()` fires and calls `dispatchValue()` **multiple
  times**, including once right after each of the `init`/`park` (Open/
  Close) commands actually ran - so live pushes definitely arrive and
  are recognized as state events for the right node.
- One *extra*, unexplained early dispatch happens before our own
  `subscribe()` call even runs - almost certainly a stale bare-JID
  PubSub subscription left over from an earlier dev session that was
  killed uncleanly (`kill`, not a clean `disconnectFromServer()`) rather
  than a bug; see the Phase 3 stale-session gotcha in `DEVELOPMENT.md`.
  Harmless, just noisy - ignore it when reading logs.

**So the bug is downstream of `StateSubscriptionManager::dispatchValue()`**
— somewhere between `codec::toQVariant()`'s conversion of the dispatched
`WireValue` and `KeyValueCard.qml` actually rendering it. Two more
temporary diagnostics were added and are waiting on a repro:
- `dispatchValue()` now also logs the actual `QVariant` content being
  sent to watchers (`"state dispatch for" << node << "->" << variant`).
- `KeyValueCard.qml` has `onValueChanged: console.log(...)` printing its
  `value` property and whether `Array.isArray(value)` is true.

**Next step:** relaunch (either build dir), open the Roof page, click
Open/Close, and read the console for both new log lines:
- If `KeyValueCard.value changed` never fires at all → the break is
  between `StateSubscription::notifyValueChanged()` and
  `RoofView.qml`'s `subscription.value` binding (check whether
  `roofDelegate.subscription` is actually the live object, not stale/
  null - maybe a resubscribe churn issue from
  `onMotionInterfaceChanged`/`onVisibleChanged` refiring due to
  `ModuleListModel::upsert()`'s in-place-update `dataChanged(idx, idx)`
  call not scoping its `roles` argument, unlike `updatePresence()` which
  does - this forces QML to re-read *every* role including
  `statefulInterfaces`, which is rebuilt fresh on every call to
  `data()`).
- If it fires but `Array.isArray(value)` is false → the bug is in
  `codec::toQVariant()` (`VariantBridge.cpp`) or in how
  `codec::xmlToValue()` decoded the payload in the first place -
  compare the logged `state dispatch for ... -> ...` QVariant content
  against what `Decode.cpp`'s dataclass-root branch should produce for
  an `IMotion` state (a dict of `status`/`devices`/`time`).

Once root-caused: remove the temporary `qInfo()`/`console.log()` diagnostic
lines added for this investigation (`StateSubscriptionManager.cpp`,
`KeyValueCard.qml`) as part of the actual fix commit - they're debugging
aids, not meant to ship permanently.

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
