# pyobs-gui++ — development notes

A clean-room C++/QML client for pyobs 2.0, modeled directly on
**pyobs-web-client**: no dependency on pyobs-core, everything built from
presence + disco#info discovered live over the wire (QXmpp instead of
Strophe.js). Generic rendering by default; hand-written QML widgets opt in
per-interface where a custom UI earns its place (starting with `IRoof`).

See `TODO.md` for what's planned next. This file is the architecture/build
reference: how to set up a dev environment, and a summary of each completed
phase's design decisions and gotchas.

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

Every phase below was verified against a real ejabberd server and real
running pyobs modules, not just unit tests — this project's whole premise
is that the wire protocol is the source of truth, not any particular
language's in-memory model of it. Keep that discipline for future work too
(tracked in `TODO.md`): verify against source and the real wire protocol,
never assume the schema shape from memory of the Python/TS side, and if a
phase's design turns out to need something not anticipated, fix this doc
too, not just the code.

---

## Environment setup (fresh clone / new machine)

### Prerequisites

- Linux (developed and CI'd on Ubuntu 26.04 specifically; adjust package
  names for other distros — see `.github/workflows/build.yml`'s own
  comment on why `ubuntu-latest` doesn't work: it currently resolves to
  Ubuntu 24.04, whose Qt6 apt packages are 2+ years behind what this
  project requires).
- **Qt 6.5+** system packages (this project always links against the
  *system* Qt6 install — never bundled/vendored, see the Phase 0 summary
  below). On Ubuntu/apt:
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

Treating "verified live" as the bar for done (see above) means reproducing
a real server + real modules setup, not just running unit tests. To set it
up on a new machine:

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
   warnings at all. Note this technique cannot confirm actual window
   visibility on a real compositor — see the Phase 7.5 note below for why
   that matters.

---

## Completed phases

Phases 0 through 7.5 are done, committed, and pushed. Summaries below cover
what each phase built and the gotchas worth remembering; see git history
for the full original blow-by-blow verification logs if needed.

### Phase 0 — project bootstrap

Qt6 (`Quick`, `Xml`, `Network`) + CMake project skeleton, C++20,
`qt_add_qml_module`. Conan (`conanfile.txt`) is the project's general C++
dependency manager for anything that comes up later (e.g. `cfitsio` for
FITS handling, plotting libs) — pin exact resolved versions, treat it like
`uv.lock`. **`qxmpp` is the one deliberate exception**: ConanCenter's
recipe pulls in `qt/[>=6]` as a build dependency, which would rebuild all
of Qt from source and conflict with the system Qt6 this project links
against — so it's vendored via CMake `FetchContent` instead, pinned to a
git tag, built directly against system Qt6.

### Phase 1 — XMPP connection walking skeleton

`comm::XmppClient` (QObject, `QML_ELEMENT`) wraps `QXmppClient`:
`connectToServer(jid, password)`, a `status` property
(`disconnected|connecting|connected|error`) mirroring `useXmpp.ts`'s
`XmppStatus` states exactly. Plain TCP only (`QXmppClient::connectToServer`)
— WebSocket transport is deferred until a browser build actually needs it
(see `TODO.md`). TLS stays strict (`TLSEnabled`, full certificate
validation) by default; `insecureSkipTlsVerification` is an explicit,
off-by-default, non-persisted opt-in surfaced as a clearly-labeled login
checkbox, for self-signed dev certs only.

### Phase 1.5 — value/XML codec (schema-less decode)

`codec::WireValue` is **`std::variant`-based, not `QVariant`**: `dict`/
dataclass fields must preserve wire/declaration order (`KeyValueCard.vue`
relies on this), and `QVariantMap` is a `QMap` that sorts by key — no
order-preserving string-keyed container ships as a `QVariant` type. So
`dict`/dataclass decode into an ordered
`std::vector<std::pair<QString, WireValue>>` variant alternative instead.
`codec::xmlToValue(QDomElement)` ports `pyobs-codec.ts`'s `xmlToValue`
switch (`nil`/`boolean`/`int`/`double`/`string`/`items`/`tuple`/`dict`,
default = dataclass root). **Qt Test, not Catch2**, is the project's test
framework throughout — ships with system Qt6 already, and later phases
want `QSignalSpy`-based assertions.

### Phase 2 — disco#info discovery

Ports `WireType`/`FieldSchema`/`CommandSchema`/`StateSchema`/
`InterfaceSchema`/`EventSchema` parsing from `pyobs-codec.ts`.
`fetchModuleInfo(bareJid, fullJid)` sends the disco#info IQ and walks
`<query>` children by namespace (`interface` under
`urn:pyobs:interface:*`, `event` under `urn:pyobs:event:*`, `capabilities`
under `urn:pyobs:capabilities:*`). Gotcha: `enums`/`commands` are `QMap`s
(sorted by key, looked up by name) — a deliberate divergence from wire
order, unlike `codec::WireDict` where preserving wire order is the whole
point (Phase 1.5).

### Phase 3 — presence-driven module list

Presence handler requires resource `pyobs` (matches `PYOBS_RESOURCE`);
`unavailable` removes the module, anything else triggers
`fetchModuleInfo`. **Roster presence probe on connect is required** —
without it, a client that connects after modules are already online never
learns about them (this bit the TS client once already). Module list is a
`QAbstractListModel`. Gotcha: test harnesses that die without an explicit
`disconnectFromServer()` leave stale XMPP sessions server-side, showing up
as extra `presenceReceived` noise from unrelated resources of the same
bare JID — always fully quit prior test sessions before trusting a
presence test.

### Phase 4 — generic state subscription + rendering

`subscribeState(bareJid, interfaceName, version)`: ref-counted PubSub
subscribe/unsubscribe (server node naming
`pyobs:state:{module}:{Interface}:{version}`; only actually unsubscribes
from the server when the last QML-side watcher goes away), retry-with-
backoff on subscribe races, plus an explicit "fetch current value" IQ to
close the race between a live push and the subscribe ack. `widgets/
KeyValueCard.qml` renders any decoded `WireValue` dataclass-shaped record
generically. `codec::toQVariant` bridges `WireValue` → `QVariant`: a
`WireDict` becomes an order-preserving `QVariantList` of `{"key", "value"}`
entries, never a `QVariantMap` (would re-sort alphabetically). Gotchas:
`QXmppPubSubManager` is **not** part of `BasicExtensions` and must be added
explicitly, or `findExtension<QXmppPubSubManager>()` returns null and the
first `subscribe()` segfaults (caught by `tst_statesubscription`'s
double-subscribe/single-unsubscribe test before any live testing).

### Phase 5 — RPC execution

`codec::valueToXml(WireValue, WireType)` (the encode half) writes directly
to a `QXmlStreamWriter` — schema-dependent, unlike decoding, because of the
int32-vs-float64 ambiguity on the wire. `executeMethod(fullJid,
methodName, params, CommandSchema)` builds the XEP-0009 RPC IQ
(`jabber:iq:rpc` envelope wrapping a `urn:pyobs:rpc:1` value payload — the
double-wrapping is real, don't flatten it), parses either a return value or
an RPC fault (`exceptionClass`/message) back. The debug panel sends every
param as `WireValue::null()` — acceptable since every real `IRoof`/
`IMotion` command's params are already optional; a real param-entry UI
would need the full `CommandSchema` (see `TODO.md`).

### Phase 6 — events

Subscribes to every event a module's disco#info advertised
(`urn:pyobs:event:{name}:{version}`), hosted on the module's own bare JID
(PEP) — a different subscription path than Phase 4's pubsub-service state
nodes; don't conflate the two. Gotcha: events are **plain JSON on the
wire**, not the self-tagged `WireValue` vocabulary state/RPC use —
`<event xmlns="pyobs:event">{escaped JSON}</event>`, decoded with
`QJsonDocument::fromJson`; only `module` is derived client-side from the
notification's `from` JID (see Phase 7.5's gotcha below about why that
alone isn't reliable). Bounded in-memory event log (one central log for
the whole app, not per-widget — so no ref-counting needed here, unlike
Phase 4).

### Phase 7 — first custom widget: `IRoof`

`widgets/RoofWidget.qml`: filters the module list for `IRoof`, embeds
`KeyValueCard` (Phase 4) for the module's `IMotion` state (matching
`RoofView.vue`'s own choice of which interface to render, kept for parity
even though `IRoof` has an equivalent state block on the wire), and adds
hand-designed "Open"/"Close"/"Stop" buttons wired through `executeMethod`
(Phase 5), each disabled while that module's command is in flight.
Gotcha: `pyobs-core`'s disco#info generation emits a full schema for every
interface a module implements, *including inherited ones* — a live `roof`
module lists `IRoof` as its own separate `<interface>` entry with the same
`init`/`park`/`stop_motion` commands and its own `state/IRoof/1` block
duplicated alongside `IMotion`'s, even though the Python `IRoof` class
itself declares nothing of its own (pure semantic marker). Confirmed
repeatedly across live testing, not assumed from the Python class
definition.

### Phase 7.5 — app shell: login window + sidebar navigation

Replaced the single flat window every prior phase piled onto with two
literal top-level `ApplicationWindow`s (`LoginWindow.qml`,
`MainWindow.qml`), matching normal desktop conventions rather than the web
client's single-page router-view swap. `MainWindow.qml`'s sidebar +
`StackLayout` hosts `DashboardView.qml` (existing module list +
`RoofWidget`), `ShellView.qml` (module → method → execute → log, still
all-null params, see `TODO.md`), and `LogsView.qml` (ports `LoggingView.vue`
— filters to `type === 'LogEvent'` with a per-module dropdown and
level-colored rows, `EventLogModel::entriesOfType(type)` added since
`QAbstractListModel` gives QML no generic random-access iteration for
free).

Two real gotchas found here:

- **A PubSub notification's `from` attribute is not reliably the
  publishing module's JID.** Subscribing to a module's event node makes
  ejabberd immediately replay its last published item as a catch-up
  delivery — and that catch-up delivery's `from` is the shared pubsub
  component (`pubsub.<domain>`), not the original publisher, even when the
  replayed item is only seconds old. Only a live, freshly-pushed
  notification correctly carries the publisher's own bare JID. This is
  exactly the scenario `pyobs-core`'s own `xmppcomm.py` already guards
  against (`_handle_event()` discards anything older than 30s "to avoid
  resent events after a reconnect") — `EventManager::handlePubSubEvent`
  now applies the identical filter. Covered by
  `tst_eventmanager::ignoresStaleEvents()`.
- **`Main.qml`'s root must be `QtObject`, not `Item`.** `Item` is a visual
  type that expects to belong to a `QQuickWindow`'s scene graph; as the
  `QQmlApplicationEngine` root it never gets one, which silently breaks
  visibility of the `Window` children declared inside it (`LoginWindow`/
  `MainWindow` get created with no errors, but never map on the real
  compositor). This was originally misdiagnosed as an artifact of testing
  under `QT_QPA_PLATFORM=offscreen` and dismissed as not-a-real-bug — it
  reproduces identically on a real KDE Plasma/Wayland session, confirmed
  by querying KWin's own window list live. A second, unrelated bug was
  introduced while first fixing this: giving the `XmppClient` instance a
  property name identical to the `id` used to reference it elsewhere
  (`property var xmppClient: XmppClient {}`, then `xmppClient: xmppClient`
  on `LoginWindow`) is a self-shadowing reference — the RHS resolves to
  that object's own not-yet-assigned property of the same name before
  falling back to the outer scope. Keep the `id`-based reference pattern
  (`XmppClient { id: xmppClient }`); if `QtObject`'s lack of a default
  property means the child needs to live in some property, give that
  property a *different* name than the `id`.

---

## Notes for whoever (human or Claude Code) picks this up next

- Re-clone/re-check the current branch state before resuming — don't
  assume the working tree matches whatever was last discussed in chat.
- Every acceptance criterion in this project's history means "verified
  live," not just unit tests passing — keep that bar for whatever's next
  in `TODO.md`.
- If a design turns out to need something not anticipated in `TODO.md`,
  fix that doc, don't just fix the code.

## Releases

Push a `vX.Y.Z` tag and CI does the rest: builds, runs tests, packages a
redistributable tarball (binary + the vendored `libQXmppQt6.so.5`, RUNPATH
patched with `patchelf` so it's actually runnable once extracted — see
`.github/workflows/build.yml`'s own comments), and creates the GitHub
release with that tarball attached, via `gh` (pre-installed on
GitHub-hosted runners, authenticated with the automatic `GITHUB_TOKEN`).
No manual artifact-building or uploading needed. `v0.1.0` is the first
example of this. System Qt6 itself is deliberately never bundled — the
release notes call this out as a runtime requirement instead.

## Repository

`git@github.com:pyobs/pyobs-gui-.git` (trailing hyphen is deliberate, not
a typo — renamed from `pyobs-qml-client` during Phase 0). Currently
reports as private to unauthenticated GitHub API reads, which also means
CI run status and release contents can't be checked from a plain
unauthenticated `curl` — needs either the `gh` CLI with a token, or
checking directly on github.com.
