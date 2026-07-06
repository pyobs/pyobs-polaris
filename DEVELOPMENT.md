# pyobs-gui++ — build plan

A clean-room C++/QML client for pyobs 2.0, modeled directly on
**pyobs-web-client**: no dependency on pyobs-core, everything built from
presence + disco#info discovered live over the wire (QXmpp instead of
Strophe.js). Generic rendering by default; hand-written QML widgets opt in
per-interface where a custom UI earns its place (starting with `ICamera`).

Each phase below should be its own PR/commit, buildable and runnable on its
own before moving to the next. Do not start a phase until the previous one's
acceptance criteria are met and verified against a live ejabberd server —
verify against source and the real wire protocol, never assume the schema
shape from memory of the Python/TS side.

Reference implementation to port from (read before starting each phase, not
just once at the start):

- `pyobs-web-client/src/pyobs-codec.ts` — value↔XML codec, schema parsing
- `pyobs-web-client/src/composables/useXmpp.ts` — connection, discovery,
  state subscription, RPC, presence
- `pyobs-web-client/src/components/ModuleStateCard.vue` + `KeyValueCard.vue`
  — generic rendering
- `pyobs-web-client/src/views/RoofView.vue` — the pattern for a
  custom, interface-specific widget built on top of the generic plumbing

---

## Phase 0 — project bootstrap

**Goal:** an empty Qt Quick window builds and runs, dependency-managed, no
XMPP yet.

- `CMakeLists.txt` targeting Qt6 (`Quick`, `Xml`, `Network` components),
  `qt_add_qml_module`, C++20.
- Conan (`conanfile.txt`) is the project's general C++ dependency manager,
  for whatever comes up in later phases (e.g. `cfitsio` for FITS handling,
  plotting libs). Pin exact resolved versions once known; treat it the same
  as `uv.lock` — commit it, don't let it float.
  - **qxmpp is the one exception, and is deliberately *not* a Conan
    dependency.** ConanCenter's `qxmpp` recipe pulls in `qt/[>=6]` as a
    build dependency, which means `conan install` would build the entirety
    of Qt from source (a multi-hour, multi-GB graph: ICU, harfbuzz, glib,
    freetype, ...) — and that Conan-built Qt would conflict with the system
    Qt6 this project links against for `Quick`/`qt_add_qml_module`. Instead,
    `qxmpp` is vendored via CMake `FetchContent` in `CMakeLists.txt`, pinned
    to a git tag (e.g. `v1.10.2`), built directly against the system Qt6.
    If this ever gets fixed upstream (a Conan recipe option to use system
    Qt) it's worth revisiting, but don't assume that's happened without
    checking the recipe again.
- Directory layout (flat at repo root, not nested under a subdirectory):
  ```
  ├── CMakeLists.txt
  ├── conanfile.txt
  ├── src/
  │   ├── main.cpp
  │   ├── comm/          # QXmpp-based Comm layer (Phase 1+)
  │   └── codec/         # port of pyobs-codec.ts (Phase 1.5+)
  └── qml/
      ├── Main.qml
      └── widgets/
  ```
- `Main.qml` is a bare window with a placeholder label — no login form yet.
- CI: a GitHub Actions workflow that does `conan install` + `cmake --build`
  on push, mirroring pyobs-core's `pytest.yml` role (catch build breakage
  early, nothing integration-level yet).

**Acceptance:** `cmake --build build` succeeds from a clean checkout on a
fresh clone; the window opens and renders.

---

## Phase 1 — XMPP connection walking skeleton

**Goal:** connect, authenticate, and prove the round trip works — no
discovery, no UI beyond a status string.

- `comm/XmppClient` (QObject-derived, exposed to QML via
  `qt_add_qml_module`'s `QML_ELEMENT`): wraps `QXmppClient`, exposes
  `connectToServer(jid, password)`, a `status` property
  (`disconnected|connecting|connected|error`), mirroring `useXmpp.ts`'s
  `XmppStatus` states exactly — same four states, same names, so anyone
  familiar with the web client recognizes the model immediately.
- WebSocket vs. plain TCP: start with plain TCP (`QXmppClient::connectToServer`)
  since this is a native build first — WASM is a later phase and that's
  where the WebSocket transport (`QXmppWebSocketConnection` if a real pyobs
  build needs it) actually matters. Don't build the WebSocket path early;
  it's dead code until Phase 8.
- `Main.qml` gets a minimal login form (JID + password fields, connect
  button) purely to drive this — not the real login UI, just enough to
  exercise the C++ side by hand.
- Session credential handling: for now, in-memory only. Do **not** port
  `useXmpp.ts`'s `sessionStorage`/`localStorage` persistence yet — that's a
  UI-polish concern for later, and premature credential persistence in an
  unfinished client is a needless risk to carry through every phase.
- TLS: `QXmppClient` defaults to `TLSEnabled` with strict certificate
  validation, and that default is kept — don't weaken it. A local/dev
  ejabberd with a self-signed cert (e.g. one whose cert doesn't cover
  `localhost`) will correctly land in the `error` state against it. For
  that case `XmppClient` exposes an explicit, off-by-default
  `insecureSkipTlsVerification` property (not an env var, not persisted)
  that the login UI surfaces as a clearly-labeled checkbox — opt-in per
  session, never silently on.

**Acceptance:** connects to a real ejabberd instance with real credentials;
status transitions visibly through connecting → connected; wrong password
shows the error state. Verified live, not just against a mock — confirmed
against a local ejabberd with both a correct and a wrong password, using
`insecureSkipTlsVerification` since that instance's cert doesn't cover
`localhost`.

---

## Phase 1.5 — value/XML codec (schema-less decode)

**Goal:** port `pyobs-codec.ts`'s decode half — `xmlToValue` — to C++. No
discovery integration yet, just the codec, unit-tested standalone.

- `codec/WireValue`: **`std::variant`-based**, not `QVariant` — decided and
  documented in `WireValue.h`. Reason: `dict`/dataclass fields need to
  preserve wire/declaration order (`pyobs-web-client`'s `KeyValueCard.vue`
  relies on `Object.entries()` preserving JS insertion order when
  rendering), and `QVariantMap` is a `QMap` that sorts by key — no
  order-preserving string-keyed container ships as a `QVariant` type, so
  `dict`/dataclass both decode into a plain ordered
  `std::vector<std::pair<QString, WireValue>>` variant alternative instead.
  Mirrors the TS `unknown` return of `xmlToValue`: null, bool, int, double,
  string, list, or that ordered dict/dataclass-record.
- `codec::xmlToValue(QDomElement)` ports the switch in `pyobs-codec.ts`
  line-for-line in spirit: `nil`/`boolean`/`int`/`double`/`string`/`items`/
  `tuple`/`dict`, default case = dataclass root (one child per field, each
  wrapping one more self-tagged value).
- Unit tests: **Qt Test**, not Catch2 — it's the project's test framework
  for everything downstream. Reason: ships with the system Qt6 install
  already (no extra Conan/FetchContent dependency), and later phases
  (Phase 4's subscribe ref-counting) will want `QSignalSpy`-based
  assertions Qt Test is built for. Covers scalar decode, nested list/dict,
  a synthetic dataclass-shaped fixture, built by hand from the wire
  vocabulary in `pyobs-codec.ts`'s header comment (`nil`, `boolean`, `int`,
  `double`, `string`, `items`, `tuple`, `dict`, `entry`/`key`/`val`) —
  copied exactly, not guessed. Lives in `tests/`, wired into `ctest` and CI.

**Acceptance:** unit tests green, no XMPP connection required to run them —
this phase should be testable in isolation from Phase 1.

---

## Phase 2 — disco#info discovery

**Goal:** one disco#info round trip per module produces a populated schema,
matching `fetchModuleInfo()`'s job exactly.

- Port `WireType`/`parseWireType`, `FieldSchema`, `CommandSchema`,
  `StateSchema`, `InterfaceSchema`, `EventSchema`, `parseVersionedFeature`,
  `parseInterfaceSchema`, `parseEventSchema` from `pyobs-codec.ts`.
- `comm/ModuleInfo` (C++ struct or QObject, decide based on whether QML
  needs to bind to it directly yet — it doesn't until Phase 4, so a plain
  struct is fine for now) holding `jid`, `name`, `interfaces`, `events`,
  `capabilities` — same shape as the TS `PyobsModule` type.
- `fetchModuleInfo(bareJid, fullJid)`: send the disco#info IQ, walk
  `<query>` children by namespace exactly as `useXmpp.ts` does (`interface`
  under `urn:pyobs:interface:*`, `event` under `urn:pyobs:event:*`,
  `capabilities` under `urn:pyobs:capabilities:*`), populate `ModuleInfo`.
- No presence-driven auto-discovery yet — call `fetchModuleInfo` manually
  (e.g. a hardcoded test JID, or a debug button) to prove the parse is
  correct before wiring it to presence in Phase 4.

**Acceptance:** run against a real module (e.g. a `SimCamera` instance —
stable, low-stakes, matches the order already used for the QXmpp Comm
skeleton in earlier design discussion); print/log the parsed
`InterfaceSchema` and manually diff it against the actual disco#info XML
captured with a packet sniff or `pyobs-web-client`'s own dev tools network
tab, to catch any parsing drift before it's silently wrong.

---

## Phase 3 — presence-driven module list

**Goal:** modules appear/disappear automatically, no manual `fetchModuleInfo`
calls — this is where Phase 1's connection and Phase 2's discovery actually
join up into a live module list.

- Presence handler: resource must be `pyobs` (constant, matches
  `PYOBS_RESOURCE` in `useXmpp.ts`) or ignore the stanza; `unavailable` type
  removes the module, anything else triggers `fetchModuleInfo`.
- Roster presence probe on connect (`probeRosterPresence()`'s C++
  equivalent) — without this, a client that connects *after* modules are
  already online never learns about them. This bit any earlier
  implementation once already (in the TS client); don't skip it here just
  because it's easy to forget it matters.
- Expose the module list to QML as a `QAbstractListModel` (this is the
  first point QML actually needs live C++ data, hence deferring the QObject
  question from Phase 2 to here).
- `Main.qml` gets a bare `ListView` of connected modules (JID + name only,
  no interfaces/capabilities shown yet) — enough to prove presence and
  discovery are correctly linked.

**Acceptance:** start a module after the client is already connected → it
appears. Stop it → it disappears. Restart the *client* while the module is
already running → it still appears (proves the roster probe works, not
just live presence pushes).

---

## Phase 4 — generic state subscription + rendering

**Goal:** the `ModuleStateCard`/`KeyValueCard` equivalent — render any
interface's state as a plain key-value list, zero interface-specific code.

- `subscribeState(bareJid, interfaceName, version)`: ref-counted PubSub
  subscribe exactly like `useXmpp.ts` — same node naming
  (`pyobs:state:{module}:{Interface}:{version}`), same ref-count semantics
  (only actually unsubscribe from the server when the last QML-side watcher
  goes away). Getting the ref-counting wrong here is the kind of bug that's
  invisible in a single-widget test and only shows up once two widgets
  watch the same state — write a test for the double-subscribe/single-
  unsubscribe case specifically, don't rely on manual testing to catch it.
- Retry-with-backoff on subscribe (publisher's node may not exist yet at
  subscribe time — same reasoning as `STATE_SUBSCRIBE_RETRIES` in
  `useXmpp.ts`), plus an explicit "fetch current value" IQ after subscribing
  to close the race between a live push and the subscribe ack.
- A generic QML component (`widgets/KeyValueCard.qml`): binds to a decoded
  `WireValue` dataclass-shaped record and renders field name → value pairs
  with a `Repeater`. This is the component every future custom widget will
  embed for its "boring" state display, same role as `ModuleStateCard.vue`
  in the web client.
- Wire this into the module list from Phase 3: expanding a module row shows
  its `KeyValueCard` for every interface that has a `state` block.

**Acceptance:** live state changes on the server (e.g. toggling a `SimCamera`
between `idle`/`exposing`) show up in the QML UI without a restart or manual
refresh, for a module you did not write any interface-specific code for.

---

## Phase 5 — RPC execution

**Goal:** call commands, matching `executeMethod()`.

- `codec::valueToXml(WireValue, WireType)`: the encode half of the codec,
  ported from `pyobs-codec.ts` — this needs the schema (from Phase 2) since
  encoding is not self-describing the way decoding is (the int32-vs-float64
  ambiguity called out in the TS file's header comment applies here too).
- `executeMethod(fullJid, methodName, params, CommandSchema)`: build the
  XEP-0009 RPC IQ (`jabber:iq:rpc` envelope, `urn:pyobs:rpc:1` value
  payload — same double-wrapping as the TS side, don't flatten it),
  send, parse either a `parseRpcReturn` or an RPC fault
  (`exception`/`message`) back into a result type.
- No custom UI yet — a debug/dev-only QML panel that lets you pick a
  discovered command and pass a fixed set of null params is enough to prove
  the round trip (mirrors how Phase 2 was proved before Phase 3's UI wiring).

**Acceptance:** call a real command with no params (e.g. `IRoof.init`) and
observe the effect on the server; call one that raises a real exception and
confirm the fault's `exceptionClass`/message come through correctly, not
just "some XMPP error."

---

## Phase 6 — events

**Goal:** live `LogEvent`/domain events, matching `LoggingView.vue`'s role.

- Subscribe to every event a module's disco#info advertised
  (`urn:pyobs:event:{name}:{version}`), hosted on the module's own bare JID
  (PEP), not the separate pubsub service state uses — this distinction bit
  the web client once; don't conflate the two subscription paths in C++
  either.
- Bounded in-memory event log (same `MAX_EVENTS`-style cap as `useXmpp.ts`
  — unbounded growth in a long-running observatory-control session is a
  real problem, not a hypothetical one).
- A simple scrolling event log view in QML.

**Acceptance:** trigger a real event on the server, see it appear live.

---

## Phase 7 — first custom widget: `ICamera`

**Goal:** prove the "generic by default, custom where it earns its place"
pattern from `RoofView.vue`, for the interface that actually needs it.

- Before writing any QML: read `ICamera`'s actual current `state`/`command`
  schema off a live module's disco#info reply — don't assume its shape from
  memory of the Python interface definition. Confirm what's actually being
  published on the wire today, since this is exactly the kind of protocol
  detail that drifts during the 2.0 migration.
- `widgets/CameraWidget.qml`: filters the module list for `ICamera`,
  embeds the generic state card (Phase 4) for whatever `ICamera.state`
  actually contains, and adds hand-designed chrome on top — exposure
  controls, a binning selector built from the interface's `enum` block
  (Phase 2's `enums` map), an abort button wired through `executeMethod`
  (Phase 5).
- Explicitly **not** in this phase: live image preview. That depends on
  resolving VFS paths to fetchable URLs, which pyobs-web-client treats as
  its own separate, harder problem (see its `DEVELOPMENT.md`, VFS endpoint
  config) — don't fold it into this phase just because it's the obvious
  next thing a camera widget would want.

**Acceptance:** the widget shows live `ICamera` state via the generic
plumbing and can successfully issue at least one real command
(e.g. abort) against a live camera module — verified live, same bar as
every prior phase.

---

## Phase 8 — WebAssembly build

**Goal:** the same client, browser-deployable, per the earlier WASM
discussion.

- Second Conan profile (Emscripten toolchain) alongside the native one from
  Phase 0 — don't retrofit Phase 0's CMake for this later; get the second
  profile building (even just "hello world" Qt Quick in a canvas) before
  porting any XMPP code, to isolate WASM-specific build pain from protocol
  pain.
- Networking: raw `QXmppClient::connectToServer` (Phase 1's TCP path) does
  not work in a browser sandbox — this is where the WebSocket transport
  actually becomes necessary, same reasoning as `useXmpp.ts`'s
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

## Notes for whoever (human or Claude Code) picks this up mid-phase

- Re-clone/re-check the current branch state before resuming — don't
  assume the working tree matches whatever was last discussed in chat.
- Every phase's acceptance criterion says "live" for a reason: this
  project's whole premise is that the wire protocol is the source of
  truth, not any particular language's in-memory model of it. A phase that
  only passes against a mock isn't actually done.
- If a phase's design turns out to need something not anticipated here
  (e.g. Phase 2's schema turns out to have a shape this doc didn't
  predict), fix the doc, don't just fix the code — this file should always
  describe the actual current plan, not the plan as imagined before anyone
  looked at real disco#info output.
