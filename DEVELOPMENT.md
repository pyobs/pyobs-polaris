# pyobs-gui++ — build plan

A clean-room C++/QML client for pyobs 2.0, modeled directly on
**pyobs-web-client**: no dependency on pyobs-core, everything built from
presence + disco#info discovered live over the wire (QXmpp instead of
Strophe.js). Generic rendering by default; hand-written QML widgets opt in
per-interface where a custom UI earns its place (starting with `IRoof`).

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

Not vendored as a submodule or otherwise fetched by this repo — clone it
separately, next to this repo:
`git clone git@github.com:/pyobs/pyobs-web-client.git`.

---

## Environment setup (fresh clone / new machine)

### Prerequisites

- Linux (developed and CI'd on Ubuntu 26.04 specifically; adjust package
  names for other distros — see `.github/workflows/build.yml`'s own
  comment on why `ubuntu-latest` doesn't work: it currently resolves to
  Ubuntu 24.04, whose Qt6 apt packages are 2+ years behind what this
  project requires).
- **Qt 6.5+** system packages (this project always links against the
  *system* Qt6 install — never bundled/vendored, see Phase 0's
  conanfile.txt rationale). On Ubuntu/apt:
  ```bash
  sudo apt-get install -y \
    qt6-base-dev qt6-base-dev-tools \
    qt6-declarative-dev qt6-declarative-dev-tools
  ```
- **CMake 3.21+** and a **C++20** compiler.
- **Conan 2.x.** Most modern distros block a plain `pip install` for the
  system Python (PEP 668, "externally managed environment") — install via
  `pipx install conan` instead, then run `conan profile detect --force`
  once.
- `patchelf` is only needed for cutting a release (see "Releases" below),
  not for day-to-day building.

### Build

```bash
git clone git@github.com:pyobs/pyobs-gui-.git pyobs-gui++
cd pyobs-gui++

# Generates CMakeUserPresets.json (gitignored) - do this before the
# cmake --preset step below, or that preset won't exist yet.
conan install . --build=missing

cmake --preset conan-release -DCMAKE_BUILD_TYPE=Release
cmake --build --preset conan-release
ctest --output-on-failure --test-dir build/Release
```

The first configure also fetches and builds `qxmpp` from source (~100
files, pinned via `GIT_TAG` in `CMakeLists.txt`, through CMake
`FetchContent`) — this is the slow part of a clean build (several
minutes), and deliberately not a Conan dependency (see `CMakeLists.txt`'s
own comment: ConanCenter's `qxmpp` recipe would rebuild the whole of Qt
from source instead).

Run it: `./build/Release/pyobs-gui++`

### Live-verification test fixtures

Every phase's acceptance criterion in this document means *verified
against a real ejabberd server and real running pyobs modules*, not just
"unit tests pass" — reproducing that setup is necessary to actually
continue this project's work, not optional. To set it up on a new
machine:

1. **An XMPP server** supporting XEP-0030 (disco#info), XEP-0060
   (PubSub), XEP-0163 (PEP), and XEP-0009 (RPC). Developed and tested
   against ejabberd; any compliant server should work. A self-signed dev
   cert is fine — this client has an explicit "skip TLS certificate
   verification" checkbox for exactly that case.
2. **A `pyobs-core` 2.0 install**, in its own venv (`pip install
   pyobs-core`) — this project has zero Python dependency itself,
   pyobs-core is only needed to have real modules to test against. Run at
   least one `DummyRoof` and one `DummyTelescope`:
   ```yaml
   # comm.shared.yaml - shared by every module config
   comm_cfg: &comm
     class: pyobs.comm.xmpp.XmppComm
     domain: localhost         # match wherever your XMPP server is
     use_tls: True
     ignore_cert_errors: True  # self-signed dev cert
   ```
   ```yaml
   # roof.yaml
   {include comm.shared.yaml}
   class: pyobs.modules.roof.DummyRoof
   comm:
     <<: *comm
     user: roof
     password: <pick one, register it on the XMPP server>
   ```
   Same pattern for `telescope.yaml` with `class:
   pyobs.modules.telescope.DummyTelescope`. Start each with `pyobs
   path/to/roof.yaml` from the pyobs-core venv.
3. **Register XMPP accounts**: one per module (`roof@<domain>`,
   `telescope@<domain>`, matching each config's `user:`), plus one more
   for the GUI client itself to log in as (any registered account works —
   doesn't need to be a module account).
4. **A headless C++ test-harness technique** was used throughout this
   project to verify wire behavior without needing a GUI/display: manually
   run `moc` on the relevant headers, compile a standalone
   `QCoreApplication`- (or, for testing actual QML, `QGuiApplication` +
   `QQmlApplicationEngine`-) based program linking directly against the
   already-built `libQXmppQt6.so` (under
   `build/Release/_deps/qxmpp-build/src/`), and run it against the real
   server. For testing real `.qml` files this way (not just C++), point
   `QQmlEngine::addImportPath()` at a copy of the generated
   `build/Release/pyobs/gui/` directory with the `prefer :/qt/qml/...`
   line stripped from its `qmldir` first — that line otherwise forces
   qrc-embedded-resource resolution, which a hand-built standalone test
   binary doesn't have compiled in, and the load silently fails with no
   warnings at all.

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
  correct before wiring it to presence in Phase 3.

**Acceptance:** run against a real module (e.g. a `SimCamera` instance —
stable, low-stakes, matches the order already used for the QXmpp Comm
skeleton in earlier design discussion); print/log the parsed
`InterfaceSchema` and manually diff it against the actual disco#info XML
captured with a packet sniff or `pyobs-web-client`'s own dev tools network
tab, to catch any parsing drift before it's silently wrong.

Verified live against a real running module (`DummyTelescope`, exposing 12
interfaces incl. `IMotion`/`ITelescope` with an 11-value `MotionStatus`
enum, 4 events, 3 capabilities blocks) by dumping the raw `<iq>`/`<query>`
XML alongside the parsed `ModuleInfo` and diffing by eye: every interface,
command, parameter (including `optional<...>`, `array<struct<...>>`,
`enum(...)`, `unit` attributes), state field, event field, enum value list,
and capability value (including an empty `<dict/>` and an ordered string
list) matched exactly. One deliberate divergence from wire order: `enums`/
`commands` are `QMap`s (sorted by key) since they're looked up by name, not
iterated for display order — confirmed this only affects debug-log
presentation order, not correctness, but worth knowing if a future phase's
UI ever wants to preserve declaration order for these two maps specifically
(unlike `codec::WireDict`, where preserving wire order is the entire
point — see Phase 1.5).

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

Verified live, all three cases, in one continuous session against the real
ejabberd: connected fresh while `telescope` was already running (appeared
via the roster probe, no live presence involved); started a second module
(`roof`, `pyobs.modules.roof.DummyRoof`) while already connected (appeared
via a live presence push, `ModuleListModel::upsert` firing `rowsInserted`);
killed it (a graceful SIGTERM shutdown - pyobs's `application.py` disconnects
cleanly, sending `unavailable` presence, which ejabberd forwards) and
watched it disappear (`rowsRemoved`). One thing worth knowing for whoever
debugs presence next: test harnesses that die without an explicit
`disconnectFromServer()` (e.g. a plain `kill` on the test process itself,
not the module) leave stale XMPP sessions that ejabberd doesn't clean up
immediately - these show up as extra `presenceReceived` events from
unrelated resources of the *same* bare JID and can make manual testing
look flakier than the actual code is. Always fully quit prior test
sessions (not just the pyobs module under test) before drawing conclusions
from a presence test.

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

Implementation notes:
- `comm::StateSubscriptionManager` is a `QXmppClientExtension` +
  `QXmppPubSubEventHandler` (registered via
  `QXmppClient::addNewExtension`, alongside a `QXmppPubSubManager` -
  **not** part of `BasicExtensions`, has to be added explicitly, see
  `XmppClient`'s constructor). Owns the ref-counted node/watcher map;
  `comm::StateSubscription` is the QML-facing RAII handle (`{ value,
  unsubscribe }`, mirroring `useXmpp.ts`'s return shape via C++ object
  lifetime instead of a caller-remembered cleanup call).
- `codec::toQVariant` bridges a decoded `WireValue` to `QVariant` for QML:
  a `WireDict` becomes an order-preserving `QVariantList` of
  `{"key":..., "value":...}` entries (never a `QVariantMap` - that would
  re-sort fields alphabetically, undoing Phase 1.5's entire reason for
  `WireValue` not being `QVariant`-based to begin with).
- The double-subscribe/single-unsubscribe ref-counting test
  (`tst_statesubscription`) is a black-box test against the manager's
  public interface only (`subscribe()`/`StateSubscription::unsubscribe()`/
  `handlePubSubEvent()` with a synthesized `<message>` stanza) - no
  internal accessors needed, and it directly caught a real bug before any
  live testing: `StateSubscriptionManager` never actually added a
  `QXmppPubSubManager` extension, so `findExtension<QXmppPubSubManager>()`
  returned null and the first real `subscribe()` call segfaulted.
- Also caught (by a full from-scratch rebuild, not incremental): `XmppClient.h`
  forward-declared `StateSubscription` for `subscribeState()`'s return type,
  which only compiled by accident because CMake's combined
  `mocs_compilation.cpp` happened to pull in `StateSubscription.h` from
  another file's moc output first. Fixed by fully including
  `StateSubscription.h` - moc's constexpr metaobject codegen needs the
  complete type for any `Q_INVOKABLE`/`Q_PROPERTY` using it, and that must
  not depend on other files' include order.

Verified live: subscribed to a running `roof` module's `IMotion` state
(status `idle`), then triggered a real `park()` RPC call via pyobs-core's
own `XmppComm`/`proxy()` (Phase 5 isn't built yet, so this used pyobs's own
Python client rather than this project's), and watched the exact same
generic C++ subscription path used by `KeyValueCard.qml` receive
`idle → parking → parked` live, with no restart - for `IMotion`/`IRoof`,
an interface this project has zero custom code for.

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

Implementation notes:
- `codec::valueToXml` writes directly to a `QXmlStreamWriter` rather than
  building a `QDomElement` first - there's no natural "detached DOM
  element" concept for building outgoing XML in Qt the way there is in JS,
  and outgoing IQs in this project are already built this way (see
  `Discovery.cpp`'s disco#info request).
- `comm::executeMethod` mirrors `useXmpp.ts`'s `findRpcFault`/
  `parseRpcReturn` structurally: a small `findDescendantByLocalTag` (full
  subtree DFS, mirrors `getElementsByTagName()[0]`) locates `<fault>`/
  `<params>` anywhere in the response, then direct-children-only
  navigation from there - not another full-tree search at each step,
  matching the TS port exactly rather than searching more broadly than it
  does.
- `XmppClient::executeMethod`'s Q_INVOKABLE deliberately takes just a
  `paramCount` (not real typed param values or even a `CommandSchema`):
  every param is sent as `WireValue::null()`, and `valueToXml` writes
  `<nil/>` for a null value regardless of the declared `WireType` - so the
  schema's actual param types don't matter for this phase's "fixed set of
  null params" debug panel. A real param-entry UI (if one's ever needed -
  every real `IRoof`/`IMotion` command's params are already optional, see
  Phase 7) would need the full `CommandSchema`; deferred until something
  actually requires it.

Verified live, both cases, against a real running `roof` module using
`XmppClient::executeMethod` itself (not pyobs-core's Python client this
time - this is the phase that IS this project's own RPC path):
`IRoof.init()` with 0 params succeeded and the server's log confirmed the
real effect (`Changed motion status to idle`); `IConfig.get_config_value`
with 1 null param - a required, non-optional `name: str` parameter -
correctly triggered a real remote `ValueError("No parameter name given.")`
(pyobs-core's own `Module.get_config_value` treats a falsy/`None` name as
missing), surfaced with `exceptionClass="ValueError"` and the exact
message, not a generic transport error.

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

Implementation notes:
- Events are **plain JSON on the wire**, not the self-tagged `WireValue`
  vocabulary state/RPC use - confirmed against `pyobs-core`'s actual
  `Event.to_json()`/`send_event()` (not just the TS port from memory):
  the PubSub item payload is `<event xmlns="pyobs:event">{escaped JSON
  text}</event>`, decoded with `QJsonDocument::fromJson`, not
  `codec::xmlToValue`. `type`/`timestamp`/`uuid`/`data` come straight from
  the JSON; `module` is derived client-side from the notification's `from`
  JID, same as the TS port.
- `comm::EventManager` reuses `QXmppPubSubManager::subscribeToNode()`
  directly (Phase 4's manager did too) - it's fully generic over which
  JID hosts the node, so pointing it at the module's own bare JID (PEP)
  instead of a `pubsub.<domain>` service needed no new plumbing, just a
  different `serviceJid` argument.
- `EventLogModel`'s `data` field is a plain `QVariantMap` (sorted), not an
  order-preserving structure like `codec::WireDict` - checked
  `LoggingView.vue` first: it only ever looks up named fields
  (`data['level']`, `data['message']`), never iterates `data` generically,
  so there's no wire-order fidelity to preserve here, unlike Phase 4's
  state rendering.
- No ref-counting/retry-with-backoff for event subscriptions, unlike
  Phase 4's state subscriptions: there's exactly one central event log for
  the whole app rather than per-widget watchers, and `subscribeToEvents()`
  is deliberately un-deduped (matches `useXmpp.ts`'s own
  `fetchModuleInfo`-triggered subscribe, re-sent every time discovery
  resolves for a module - harmless, since re-subscribing an already-
  subscribed JID to a node is a server-side no-op).

Verified live against a running `roof` module: called `IRoof.init()`
(reusing Phase 5's own `executeMethod`) and watched real events arrive
through the generic event path in real time - `MotionStatusChangedEvent`
(`initializing` then `idle`), two `LogEvent`s with full field decoding
(`filename`/`function`/`level`/`line`/`message`/`sender`/`time`), and a
`RoofOpenedEvent` (correctly decoding its empty `{}` payload) - all for a
module this project has zero event-specific C++ code for.

---

## Phase 7 — first custom widget: `IRoof`

**Goal:** prove the "generic by default, custom where it earns its place"
pattern from `RoofView.vue` itself — this is that exact widget, ported to
QML. `IRoof` over `ICamera`: `ICamera` needs exposure controls, a binning
selector, and eventually live image preview (VFS path resolution, its own
hard problem) — a lot of surface area for what this phase is actually
trying to prove. `IRoof` needs none of that: it's IMotion (already fully
generic since Phase 4) plus three buttons, so the phase stays focused on
the generic/custom boundary itself rather than camera-specific chrome.
The Python `IRoof` class itself (see the interface definition) declares no
commands or state of its own — it extends `IMotion` purely as a semantic
marker. **This is not what's actually on the wire, though**: a live
disco#info reply for `roof` lists `IRoof` as its own separate `<interface>`
entry, with the *same* `init`/`park`/`stop_motion` commands and its own
`state/IRoof/1` state block duplicated alongside `IMotion`'s
`state/IMotion/1` - `pyobs-core`'s disco#info generation walks every
interface a module implements, including inherited ones, and emits a full
schema for each. Confirmed by repeatedly observing this across Phases 3-6's
live testing, not assumed from the Python class definition - exactly the
kind of protocol-reality-vs-Python-definition drift this project's
verification discipline exists to catch. Doesn't change which interface's
state to render, though: `RoofView.vue` explicitly picks `IMotion` (not
`IRoof`) for its state card regardless, so this port does too, for the
same reason - one is as good as the other on the wire, and matching the
reference exactly is simpler than re-deciding it.
- `widgets/RoofWidget.qml`: filters the module list for `IRoof` (checking
  by name in `ModuleListModel`'s existing `statefulInterfaces` role - it's
  populated from every interface with a state block, and `IRoof` is one,
  confirmed above), embeds `KeyValueCard` (Phase 4) for the module's
  `IMotion` state, and adds hand-designed chrome on top — "Open" (`init`),
  "Close" (`park`), "Stop" (`stop_motion`) buttons wired through
  `executeMethod` (Phase 5), each disabled while a command for that module
  is in flight, matching `RoofView.vue`'s per-jid `running`/`errors`
  tracking. `executeMethod` gained a second overload taking a QML JS
  callback (`{success, errorClass, errorMessage}`) - Phase 5's shared
  `lastRpcResult` debug label isn't enough once more than one module's
  commands can be in flight at once, which per-widget per-jid tracking
  needs.

**Acceptance:** the widget shows live `IMotion` state via the generic
plumbing and can successfully issue at least one real command (e.g. "Open"
→ `init`) against a live `roof` module, observing the same live
`idle → parking/initializing → parked/idle` transition Phase 4 already
proved — verified live, same bar as every prior phase.

Verified live: the new `executeMethod(..., callback)` overload - the
actual code path "Open"/"Close"/"Stop" trigger - was exercised end-to-end
through a real `QQmlApplicationEngine` (not just plain C++ calls) against
the running `roof` module, both success (`init()` → `{success: true}`,
confirmed by the server's own log) and a real remote fault
(`get_config_value` with a null param → `{success: false, errorClass:
"ValueError", errorMessage: "No parameter name given."}`, reusing Phase
5's own known-fault trigger) came through the JS callback correctly. The
underlying `subscribeState`/`executeMethod` machinery `RoofWidget.qml`
reuses was already proven live in Phases 4-5. A full visual/interactive
check of the widget in the running app was not done this session (lost
X11 access session-side, unrelated to the code) - worth a manual look
before considering this phase fully closed.

---

## Phase 7.5 — app shell: login window + sidebar navigation

**Goal:** replace the single flat window every prior phase piled onto with
a real app shell, matching `pyobs-web-client`'s actual structure: a
separate login screen, then a main window with a left sidebar (Dashboard /
Shell / Logs) and a content area showing whichever page is selected - not
in the original phase plan, added on direct request once Phases 0-7 had
enough substance to actually need organizing.

- `App.vue`/`AppLayout.vue`/`LoginView.vue` read directly (not assumed from
  memory of "a login page and a main page"): confirms the real nav entries
  are Dashboard, Shell, Logging, Settings, plus a conditional Roof entry
  (only `IRoof` modules present) - only Dashboard/Shell/Logs were asked
  for, so Settings (VFS endpoint config - a feature this project has no
  equivalent of at all) and a separate Roof nav entry were deliberately
  left out; `RoofWidget` instead stays embedded at the top of Dashboard,
  same as it already was.
- Two literal top-level `ApplicationWindow`s (`LoginWindow.qml`,
  `MainWindow.qml`), not one page's body swapping - matches normal desktop
  conventions better than the web client's single-page router-view swap.
  `Main.qml` is now a non-visual bootstrap `Item` owning the single
  `XmppClient` instance (must survive the login → main handoff, since it
  holds the live connection) with `visible` on each window bound to
  `xmppClient.status`.
- `MainWindow.qml`'s sidebar + `StackLayout` is the `RouterView` equivalent
  - `qml/views/DashboardView.qml` (the existing generic module list +
    `RoofWidget`, moved as-is), `qml/views/LogsView.qml`, and
    `qml/views/ShellView.qml` (new).
- `LogsView.qml` ports `LoggingView.vue` - **and reading it caught a real
  fidelity gap in Phase 6's original "Events" section**: `LoggingView.vue`
  filters to `type === 'LogEvent'` specifically, with a per-module filter
  dropdown and level-colored rows - Phase 6's port showed every event type
  generically instead. Fixed here. `EventLogModel` gained
  `entriesOfType(type) const` (a plain-JS-array snapshot) since
  `QAbstractListModel` gives QML/JS no generic random-access iteration for
  free - only `Repeater`/`ListView` delegate binding does - and a module
  filter dropdown needs to iterate/aggregate arbitrarily, not just render
  one row per event.
- `ShellView.qml` ports `ShellView.vue`'s module → method → execute → log
  flow. **Deliberately not ported**: type-aware parameter widgets
  (bool/enum/number/string, built from each param's real `WireType`) -
  `ModuleListModel`'s `commands` role only exposes `{interface, name,
  paramCount}` (Phase 5), not full per-param schemas. Every command still
  executes exactly like Phases 5/7's existing entry points: every param
  null. Real parameter entry is a reasonable follow-up, not attempted here.

**A second, more significant finding, caught by live-testing the new
`ShellView`/`LogsView` plumbing end-to-end** (not by inspection): the
`from` attribute on a PubSub notification is **not reliably the
publishing module's JID**. Subscribing to a module's event node makes
ejabberd immediately replay its last published item as a catch-up
delivery (confirmed live, repeatable) - and that catch-up delivery's
`from` is the shared pubsub component (`pubsub.<domain>`), not the
original publisher, even when the replayed item is only seconds old. Only
a live, freshly-pushed notification (arriving after the subscribe
handshake has already completed) correctly carries the publisher's own
bare JID. This is exactly the scenario `pyobs-core`'s own reference client
already guards against - `xmppcomm.py`'s `_handle_event()` discards
anything where `time.time() - event.timestamp > 30`, with the comment "we
do this do avoid resent events after a reconnect". `EventManager::
handlePubSubEvent` now applies the identical 30-second staleness filter,
matching the reference implementation's own documented reasoning rather
than inventing a new one. Covered by `tst_eventmanager`'s
`ignoresStaleEvents()`; the pre-existing `decodesAndAppendsAnEvent()` test
had to be fixed too - it used a fixed old Unix timestamp, which this new
filter now correctly (and had to be updated to use a fresh one instead).

**Acceptance:** login window shown first; connecting swaps to the main
window with a working sidebar; Dashboard/Shell/Logs all functional against
real live modules.

Verified live: reused the Phase 7 `QQmlApplicationEngine`-harness
technique (loading the real compiled `pyobs.gui` QML module standalone,
via its generated `qmldir` with the `prefer :/qt/qml/...` line stripped so
it resolves to on-disk `.qml` sources instead of a qrc this harness
doesn't have) against a live `roof`/`telescope` pair: `xmppClient.jid`
populated correctly on connect; `EventLogModel::entriesOfType("LogEvent")`
returned the wrong (empty) `module` for stale catch-up events before the
staleness-filter fix, and the correct one (`"roof"`) for a live event
triggered by `IRoof.init()` after the fix. Window-visibility toggling
(`LoginWindow`/`MainWindow` swap) could not be confirmed via this harness
- a control test showed even a trivial hardcoded `visible: true` window
reads back `false` through a synchronous `QObject::property()` check under
`QT_QPA_PLATFORM=offscreen`, confirming this is an artifact of that
platform/technique rather than a real bug (the binding itself is
simple, standard QML) - but it means an actual visual check on a real
display is still outstanding.

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

### Current status

Phases 0 through 7.5 are done, committed, and pushed to `main`. **Phase 8
(WebAssembly) is next and hasn't been started.** Known loose ends from
Phases 7/7.5 — not blocking, but worth closing out before treating those
phases as fully done:

- No real visual/interactive check of `RoofWidget` or the
  `LoginWindow`/`MainWindow` split has been done on an actual display —
  only headless/offscreen verification (see Phase 7/7.5's own notes on
  why: repeated loss of X11 access mid-session). Worth a manual look.
- `ShellView.qml`'s command execution is still all-null params, same as
  every other entry point in this project so far — real, type-aware
  per-parameter widgets (reading each param's actual `WireType` from disco
  #info) would need `ModuleListModel`'s `commands` role to expose full
  `CommandSchema`s, not just `{interface, name, paramCount}` (see Phase
  5). A reasonable next increment, not started.

### Releases

Push a `vX.Y.Z` tag and CI does the rest: builds, runs tests, packages a
redistributable tarball (binary + the vendored `libQXmppQt6.so.5`, RUNPATH
patched with `patchelf` so it's actually runnable once extracted — see
`.github/workflows/build.yml`'s own comments), and creates the GitHub
release with that tarball attached, via `gh` (pre-installed on
GitHub-hosted runners, authenticated with the automatic `GITHUB_TOKEN`).
No manual artifact-building or uploading needed. `v0.1.0` is the first
example of this. System Qt6 itself is deliberately never bundled — the
release notes call this out as a runtime requirement instead.

### Repository

`git@github.com:pyobs/pyobs-gui-.git` (trailing hyphen is deliberate, not
a typo — renamed from `pyobs-qml-client` during Phase 0). Currently
reports as private to unauthenticated GitHub API reads, which also means
CI run status and release contents can't be checked from a plain
unauthenticated `curl` — needs either the `gh` CLI with a token, or
checking directly on github.com.
