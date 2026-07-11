# pyobs-polaris — development notes

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
- **`libsecret-1-dev` and `pkg-config`**, for QtKeychain's Linux Secret
  Service backend (vendored via FetchContent, same treatment as qxmpp -
  see the config/remembered-logins summary below):
  ```bash
  sudo apt-get install -y libsecret-1-dev pkg-config
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
git clone git@github.com:pyobs/pyobs-polaris.git pyobs-polaris
cd pyobs-polaris

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

Run it: `./build/Release/polaris`

**IDE gotcha (CLion or similar)**: an ad-hoc IDE-generated build profile
(e.g. CLion's default `cmake-build-debug`) invokes `cmake` directly,
bypassing the Conan-generated toolchain entirely — `find_package(cfitsio)`
then fails outright (`cfitsio` is Conan-only, no system package fallback,
unlike Qt6). Point the IDE's CMake profile at the `conan-release` CMake
preset instead of a raw custom profile. For a Debug build specifically,
run `conan install . --build=missing -s build_type=Debug` first (adds a
`conan-debug` preset, generates `build/Debug/generators/`) and point the
IDE at that preset.

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
   pyobs-core is only needed to have real modules to test against.
   `fixtures/` (checked into this repo) holds the actual configs used so
   far - `fixtures/_comm.yaml` is the shared `XmppComm` block (`domain:
   localhost`, `use_tls`/`ignore_cert_errors` for a self-signed dev cert),
   included by each per-module config (e.g. `fixtures/autofocus.yaml`,
   `class: pyobs.modules.focus.DummyAutoFocus`). Start one with `pyobs
   fixtures/autofocus.yaml` from the pyobs-core venv. Add a new
   `fixtures/<module>.yaml` alongside it (same `{include _comm.yaml}` +
   `<<: *comm` shape) whenever a new interface-specific widget needs its
   own dummy module - don't reach for an external/uncommitted config, so
   the fixture a widget was actually verified against stays in the repo's
   history next to it.
3. **Register XMPP accounts**: one per module, matching each fixture's
   `user:` (e.g. `ejabberdctl register autofocus localhost <password>`),
   plus one more for the GUI client itself to log in as (any registered
   account works — doesn't need to be a module account). The passwords
   committed in `fixtures/*.yaml` are dev-only, meaningful solely against
   a throwaway local ejabberd instance - not secrets worth protecting.
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
off-by-default opt-in surfaced as a clearly-labeled login checkbox, for
self-signed dev certs only - `XmppClient` itself never persists it or
reads it from an ambient env var (see the "Configuration file + saved
accounts" section below for how a *saved account* remembers its own
choice).

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

### Configuration file + saved accounts

**Goal:** a config file in the system's default location; a list of saved
login accounts (not just one remembered login) that can be added, edited,
and deleted, with per-account opt-in password storage - see `TODO.md`'s
original entries, now done. First shipped as a single remembered login,
then reworked into a full list on direct request once that landed - the
single-login version is gone, not kept alongside this.

- `config::AppSettings` (QObject, `QML_ELEMENT`) wraps a plain `QSettings`
  for genuinely app-wide, non-per-account settings — resolves to the
  system default location (e.g. `~/.config/pyobs/Polaris.conf` on
  Linux) purely from `QCoreApplication::setOrganizationName()`/
  `setApplicationName()` in `main.cpp`, which must run before any
  `QSettings` is constructed. Currently holds only
  `lastSelectedAccountId` (which row to preselect in the login window on
  next launch) - add more here as app-wide (not per-account) needs come
  up.
- `config::SavedAccountsModel` (`QAbstractListModel`, `QML_ELEMENT`) is
  the actual saved-account list: `id`/`jid`/`label`/`hasStoredPassword`/
  `host`/`port`/`insecureSkipTls` roles, persisted as a `QSettings` array
  (`beginReadArray`/`beginWriteArray`, key `"accounts"`, rewritten in full
  on every add/update/remove - never a bottleneck at this scale).
  `insecureSkipTls` (added after a report that "Save changes" silently
  dropped the login window's "Skip TLS" checkbox) is a deliberate
  exception to `XmppClient::insecureSkipTlsVerification`'s own
  never-persisted default (see Phase 1): a *saved account* is itself an
  explicit, visible, user-created record, so `LoginWindow.qml` reads this
  role back into `xmppClient.insecureSkipTlsVerification` in
  `selectAccount()` and writes it back out from that same live property
  when "Save as new account"/"Save changes" is clicked - a brand new,
  unselected connection is unaffected and still starts from `false`
  either way. **Each account's
  `id` is a generated `QUuid`, independent of its `jid`/`label`, and is
  what the keychain entry is actually keyed on** - editing an account's
  jid must never orphan its stored password, which keying on the jid
  itself would risk the moment it's edited.
- **Saving an account and storing its password are two fully independent
  actions**, not one bundled step: `addAccount()`/`updateAccount()` never
  touch the keychain at all; `storePassword()`/`clearStoredPassword()` are
  separate calls the login window only makes when its own "Store password
  in system keychain" checkbox says to. This is what makes "connect
  without storing credentials" the default rather than a special case:
  `LoginWindow.qml`'s Connect button *never* saves anything on its own -
  it just calls `xmppClient.connectToServer()` with whatever's currently
  in the fields, full stop. Saving/editing/deleting a row is only ever a
  deliberate, separate button click ("Save as new account"/"Save
  changes"/"Delete").
- **The password itself never touches `QSettings`/the config file.**
  `SavedAccountsModel` vendors **QtKeychain**
  (`frankosterfeld/qtkeychain`, tag `0.17.0`) via CMake `FetchContent`,
  same treatment as qxmpp (Phase 0) — `storePassword()`/`loadPassword()`/
  `clearStoredPassword()` go through `QKeychain::WritePasswordJob`/
  `ReadPasswordJob`/`DeletePasswordJob` (async, `finished` signal), keyed
  on the account's `id` under service `"Polaris"`. On Linux this needs
  `libsecret-1-dev` + `pkg-config` to build (see Prerequisites) and a
  running Secret Service provider (gnome-keyring/KWallet) at runtime for
  it to actually persist anything — `QKeychain::isAvailable()` is false
  without one, and `WritePasswordJob`s fail cleanly rather than silently
  falling back to plaintext (no `setInsecureFallback(true)` anywhere - not
  worth the risk for a password).
- **Transactional commit, not optimistic:** `storePassword()` only flips
  `hasStoredPassword` to `true` *after* the keychain write succeeds
  (`credentialsSaved(id)`), never before - the same reasoning as the
  original single-login design (see git history): a machine with no
  keychain backend at all must never end up with `hasStoredPassword=true`
  and no password ever actually stored, silently re-failing
  `loadPassword()` forever after. `LoginWindow.qml` surfaces
  `credentialsSaveFailed(id)`/`credentialsForgetFailed(id)` as a visible
  (orange) notice for the same reason.
- `LoginWindow.qml` is list-left/details-right (`RowLayout` of a
  `ListView` bound to `accountsModel`, plus a details `ColumnLayout`), not
  a single form - `selectAccount(id)` (`id === ""` means "new connection")
  populates the detail fields and kicks off `loadPassword()` if
  `hasStoredPassword`. Each list row also has its own quick-connect
  (`▶`) button, enabled only when that account has a stored password -
  true one-click reconnect, tracked via `quickConnectPendingId` so the
  eventual `passwordReady(id, ...)` signal knows to call
  `connectToServer()` immediately instead of just prefilling the password
  field (plain row-click selection does the latter only). Guarded by `id
  !== root.selectedAccountId`/matching `quickConnectPendingId` checks so
  rapidly clicking two different rows' connect buttons can't cross-wire
  which account a delayed keychain read ends up connecting.
- `qt6keychain` builds as a shared library (`BUILD_SHARED_LIBS` defaults
  `ON` upstream) - like `libQXmppQt6.so.5`, it needs bundling alongside the
  `polaris` binary for releases (`.github/workflows/build.yml`'s
  packaging step), not just at dev-build time.
- Its own `autotest` subdirectory builds by default (gated on the CTest
  convention variable `BUILD_TESTING`, set via its own `include(CTest)`)
  — forced off in `CMakeLists.txt` since it's pure extra build time here;
  this project's own `tests/` registers via plain `add_test()`
  unconditionally, unaffected by that variable.
- `tests/config/tst_savedaccountsmodel.cpp` exercises the **real** OS
  keychain (skipping itself via `QSKIP` if `QKeychain::isAvailable()` is
  false) rather than mocking QtKeychain, matching this project's "verify
  against the real thing" philosophy elsewhere — every test that writes a
  keychain entry also deletes it again before finishing, so a run never
  leaves test credentials behind in a developer's real keychain.

**Follow-up, found live against a real SAAO server (`monet.saao.ac.za`):**
a saved account there connected successfully but appeared to hang for
about a minute before doing so. Root-caused with a throwaway headless
harness (same technique as the live-verification fixtures above, deleted
after use - and deliberately logging only `QXmppLogger::InformationMessage
| WarningMessage`, never `ReceivedMessage`/`SentMessage`, since those
include the raw SASL auth stanza i.e. the real password): that domain has
no DNS SRV records for its XMPP service, so `QXmppOutgoingClient` falls
back to trying legacy implicit-TLS on port 5223 first, then STARTTLS on
5222 - and 5223 is closed/filtered there in a way that silently drops the
connection instead of refusing it, so QXmpp has to wait out a full OS-level
TCP connect timeout (around a minute) before falling through to 5222,
which then connects and authenticates immediately. Not a bug in this
project - but indistinguishable from actually being stuck without knowing
the cause.

Fixed with a client-side escape hatch rather than requiring server/DNS
changes: `SavedAccountsModel` gained optional per-account `host`/`port`
override fields (empty/`0` = no override, normal SRV-based discovery), and
`XmppClient::connectToServer()` gained matching optional `host`/`port`
parameters - `QXmppConfiguration::setHost()` makes `QXmppOutgoingClient`
connect straight there, skipping SRV lookup (and the 5223 attempt)
entirely. `LoginWindow.qml` surfaces this as an "Override server address"
checkbox revealing host/port fields, applied consistently everywhere a
connection is initiated (the plain Connect button, and the per-row
quick-connect path). Verified live: enabling the override against
`monet.saao.ac.za:5222` connects immediately instead of stalling.

### Status page

Ad hoc, not in original plan - ports `pyobs-gui`'s (the Python/PySide6
desktop client, `statuswidget.py`) `StatusWidget`: a flat "is everything
OK" overview of every connected module - name, `IModule` capabilities'
`version`, and live presence-derived health (ready/error/local), with a
one-click "Clear error" (just `IModule.reset_error`, already a generic
command). Deliberately *not* a port of `StatusWidget`'s full `QTreeWidget`
(interfaces/capabilities/state drill-down) - that lived, differently, in
`DashboardView.qml`'s expandable module rows at the time this page was
written; duplicating it here would just have been two paths to the same
data. (`DashboardView.qml` itself is gone as of the next section below -
this note is kept for why Status was scoped narrowly, not because the
alternative still exists.)

The one genuinely new piece: this project's presence handling
(`XmppClient::handlePresence`) previously only ever distinguished
available vs. `QXmppPresence::Unavailable` (add/remove from
`ModuleListModel`) - it never looked at `<show/>`/`<status/>`, so there
was no READY/ERROR/LOCAL concept anywhere in the C++ side yet, unlike the
Python/`pyobs-core` side which has always had it. Wire-level mapping
(confirmed against `pyobs-core`'s `xmppcomm.py` `_got_online`/
`_got_presence_update`/`_set_presence`): `show=dnd` → error,
`show=away`/`xa` → local, anything else (including plain available) →
ready; `<status/>` text is the error string. `QXmppPresence` exposes this
directly (`availableStatusType()`/`statusText()`) - no new wire parsing
needed. An unavailable module is still fully removed from the list rather
than kept around as a "closed" row (matches this project's existing
presence-removal behavior; the Python `ModuleState.CLOSED` state has
correspondingly no representation here).

`ModuleInfo` gained `presenceState`/`presenceError` fields, set from the
presence stanza that triggers either a fresh `fetchModuleInfo()` (new
module) or, more often, `ModuleListModel::updatePresence()` - an in-place
role update with no disco#info re-fetch, since most presence traffic for
an already-known module is just a state change, not new schema. `version`
is not a new network round trip either: it was already sitting in
`ModuleInfo::capabilities["IModule"]` (a `WireDict` with `label`/
`version`) from the existing disco#info fetch, just never surfaced
through a model role before.

Covered by `tests/comm/tst_modulelistmodel.cpp` (new-module defaults,
version lookup with/without `IModule` capabilities present,
`updatePresence()` in-place update + its unknown-JID `false` return).
Live data flow (disco#info parse producing `capabilities.IModule` with a
real version string) reconfirmed against the `telescope` fixture; the
actual on-screen page itself wasn't visually verified this session - the
app's window didn't appear in the real X11 session's window tree when
launched (same class of issue as Phase 7.5's window-visibility gotcha),
and this display is the user's actual desktop session (visible other
windows include a private chat client), so no broader screenshot was
attempted either. Worth an actual look next time a clean display is
available.

### Dashboard and `RoofWidget` removed

Direct request: Status moved to the top of the sidebar, and Dashboard
dropped entirely rather than kept alongside it - taking `RoofWidget`
(Phase 7's `IRoof` Open/Close/Stop controls) and the original generic
expandable module list (interfaces/live state/commands, Phase 3-5) down
with it, on the reasoning that neither had a second home to move into
that wasn't itself extra unasked-for scope. `ShellView.qml` already
covers generic command execution (module → method → execute → log); nothing
currently replaces per-module live state viewing (`KeyValueCard`/
`subscribeState()`) or dedicated roof control - `comm::StateSubscription`/
`StateSubscriptionManager`/`XmppClient::subscribeState()` are untouched
and still fully covered by `tests/comm/tst_statesubscription.cpp`, just
with no QML caller left; picking a new home for live state viewing (the
Status page? a rebuilt Dashboard? per-interface pages?) is an open
question for whenever that capability is actually needed again, not
decided here.

Deleted: `qml/views/DashboardView.qml`, `qml/widgets/RoofWidget.qml`,
`qml/widgets/KeyValueCard.qml` (the last one orphaned the moment the
first two were gone - nothing else ever used it). `MainWindow.qml`'s
`StackLayout`/sidebar order is now Status (0), Shell (1), Logs (2).
`TODO.md`'s "Loose ends from Phase 7" section (both items were about
`RoofWidget`) is gone too rather than left describing a widget that no
longer exists.

**Follow-up, next request:** roof control came back, but reshaped - as
its own dedicated `qml/views/RoofView.qml` page (index 3) rather than
folded back into a rebuilt Dashboard, and `qml/widgets/KeyValueCard.qml`
came back with it (still the only consumer). The one new piece: the
"Roof" sidebar entry is conditionally visible, shown only while at least
one connected module implements `IRoof` - `ModuleListModel` gained a
plain query, `Q_INVOKABLE bool hasInterface(const QString &)`, and
`MainWindow.qml` recomputes a `hasRoofModule` property from it on every
`rowsInserted`/`rowsRemoved`/`modelReset`/`dataChanged` (same
recompute-on-signal shape as `LogsView.qml`'s own model-driven
`refresh()`, since a `QAbstractListModel` gives QML no live-updating
aggregate query for free). If the last `IRoof` module disconnects while
its page is the active one, `MainWindow.qml` jumps back to Status rather
than leaving the sidebar highlighting a now-hidden entry. Covered by
`tests/comm/tst_modulelistmodel.cpp` (`hasInterface` true/false across
multiple modules); the reactive sidebar-visibility/auto-switch behavior
itself is QML-only and wasn't separately verified live this session (same
X11-access constraints as the Status page's own note above).

**Follow-up, sidebar layout ported from `AppLayout.vue`:** direct
request to match the web client's nav look - an icon before each label,
plus its "Tools"/"Modules" section grouping (Status standalone at top,
Shell/Logs under "TOOLS", Roof under a conditionally-visible "MODULES").
No bundled icon font/theme exists here (unlike the web client's
Bootstrap Icons), so icons are plain Unicode glyphs picked to read the
same at a glance: `●` (status dot, matching the health-badge dots
already used on the Status page itself), `❯` (terminal prompt, Shell),
`▤` (lined page, Logs), `⌂` (house, Roof). `MainWindow.qml` gained two
inline `component`s (Qt 6.5+ syntax, scoped to that one file since
nothing else needs them): `SidebarItem` (an `ItemDelegate` with a custom
`contentItem` laying out icon + label) and `SidebarSectionLabel` (small
uppercase muted header). The "MODULES" header's `visible` is bound to
the same `hasRoofModule` the Roof entry itself already used, so the
header and the entry appear/disappear together.

### Roof state display bug: `Array.isArray()` is unreliable across the C++/QML boundary

`RoofView.qml`'s `KeyValueCard` was stuck on "(no value yet)" even after a
real state change, first flagged as never-visually-verified in the old
`RoofWidget` TODO entry (see the Dashboard-removal section above) and
finally checked against a live `DummyRoof` module + real display this
session. Root-caused with the same headless/live-verification discipline
as everywhere else in this project - registered a throwaway `roof` XMPP
account on the dev ejabberd server (password `pyobs`, matching the other
dummy modules'), ran a real `DummyRoof`, and read temporary `qInfo()`/
`console.log()` diagnostics while clicking Open/Close in a real window on
a real Wayland session.

The whole C++ side was already correct: `subscribe()`/`subscribeToNode()`/
`fetchCurrentValue()` all succeeded, and `dispatchValue()` fired repeatedly
with the right `QVariant` content (a `QVariantList` of `{"key", "value"}`
entries, exactly what `codec::toQVariant()` is supposed to produce). The
diagnostic that pinned it down was in `KeyValueCard.qml` itself:
`JSON.stringify(value)` printed proper `[...]` array syntax, but
`Array.isArray(value)` on that same value was `false`. **A `QVariantList`
crossing into QML via a `Q_PROPERTY(QVariant ...)` (here,
`StateSubscription::value`) arrives as a list-like/iterable object that
`JSON.stringify` and `Repeater.model` both handle as a sequence, but which
fails the strict ECMAScript `Array.isArray()` check.** `KeyValueCard.qml`
gated *both* its placeholder text's visibility and its `Repeater`'s
`model` on `Array.isArray(root.value)` - so the value was correctly
delivered all the way to QML and then silently discarded by that check on
every single dispatch.

Fix: `KeyValueCard.qml` now gates on `value !== undefined && value !==
null` (`hasValue`) instead of `Array.isArray(value)` - the only thing that
ever needs excluding is "no value has arrived yet." `Repeater.model`
itself was always fine consuming the list-like value directly; it was
only the `Array.isArray()` guard in front of it that was wrong. No C++
changes were needed - `codec::toQVariant()`, `StateSubscriptionManager`,
and `StateSubscription` were all already correct, confirmed by this
session's live trace. Worth remembering for any future generic-rendering
code that inspects a `QVariant`-typed value in QML: don't reach for
`Array.isArray()`/`typeof value === "object"` assumptions borrowed from
plain JS - a value that *behaves* like an array/object across this
boundary doesn't necessarily *pass as* one under strict JS type checks.

### Persistent log footer

Direct request: ports pyobs-gui's `MainWindow` (`mainwindow.py`'s
`splitterLog` - a vertical splitter always showing `tableLog` below the
nav+content area, regardless of which page is selected, default height
100px). `MainWindow.qml`'s single `RowLayout` is now the top pane of a
vertical `SplitView`, with a new `qml/widgets/LogFooter.qml` as the
bottom pane (`SplitView.preferredHeight: 140`, draggable like the
Python original).

`LogFooter.qml` is a **deliberate duplicate** of `LogsView.qml`'s
rendering (time/level-colored/module/message rows, same
`entriesOfType("LogEvent")` + recompute-on-`rowsInserted`/`modelReset`
pattern) - no per-module filter, no Clear button, on direct
instruction: the Logs page is getting real filtering next, and this
footer is expected to diverge from it once that lands rather than
share one component now only to be untangled later.

### Custom widget: `IAutoFocus`

First of the three custom widgets tracked in `TODO.md`
("`IAutoFocus`/`IAcquisition`/`IAutoGuiding`"), ported from pyobs-gui's
`autofocuswidget.py` - `qml/views/AutoFocusView.qml`, gated in the
sidebar the same way as Roof (`MainWindow.qml`'s `hasAutoFocusModule`,
`ModuleListModel::hasInterface("IAutoFocus")`). Live-verified against a
real `DummyAutoFocus` (`fixtures/autofocus.yaml`) end to end: running a
series, watching the plot update live, the fitted-focus result appearing
after completion, and aborting mid-run.

**New capability this widget needed that nothing before it did: real RPC
parameters.** Every command call in this project up to now
(`RoofView.qml`'s Open/Close/Stop, `ShellView.qml`'s debug panel) sent
all-null params, which only works because those commands' params are all
declared optional. `IAutoFocus.auto_focus(count: int32, step: float64,
exposure_time: float64)` has none - all three are required, so the
all-null path would fail server-side. Added:
- `codec::fromQVariant(QVariant, WireType)` (`VariantBridge.h/.cpp`) - the
  encode-side counterpart to Phase 4's `toQVariant`. Necessary, not just
  symmetric: `codec::valueToXml()` reads a `WireValue` out via the
  `std::get<>` accessor matching the *target* `WireType` (`toDouble()`
  for `Float64`, etc.), so a `WireValue` built from a plain QVariant
  without checking the schema (e.g. an int-backed `WireValue` for a
  `float64` param - easy to get wrong from a QML `SpinBox`'s integer
  value) throws inside `valueToXml()` rather than just encoding wrong.
- `ModuleListModel::find(bareJid)` - a plain C++-internal lookup (not
  `Q_INVOKABLE`; QML never needs a whole `ModuleInfo`), returning
  `const ModuleInfo *`.
- `XmppClient::executeMethod(bareJid, methodName, QVariantList params,
  QJSValue callback)` - a third overload alongside Phase 5/7's
  paramCount-based ones. Looks up the command's `CommandSchema` from the
  module's already-fetched disco#info (first interface declaring a
  command of that name - same "dispatch by name alone" convention as the
  existing overloads), encodes each `params` entry against the matching
  `FieldSchema` via `fromQVariant`. Reports a client-side failure through
  `callback` without touching the network if the module/command can't be
  found, rather than sending something malformed.

**`PlotItem` (`src/plot/PlotItem.h/.cpp`)** is the first plotting
capability in this project - see `TODO.md`'s "no external library"
decision. A `QQuickPaintedItem` (`QPainter`-based), deliberately minimal:
one scatter series, axes/gridlines/tick labels, one optional dashed
vertical reference line with a label. `points` is a raw, unprocessed
`QVariant` (an array of dataclass-shaped records, e.g.
`AutoFocusState.points`, each a `WireDict`-shaped `{focus, value}` pair)
- parsed entirely in `setPoints()`, in C++, via `QVariant::toList()`/
`toMap()`, positionally (first field = x, second = y, not looked up by
name - wire order is exactly what this project's codec preserves
dict/dataclass fields for everywhere else, so `AutoFocusPoint{focus,
value}` needs no extra config). This is deliberate, not incidental:
letting `AutoFocusView.qml` do that extraction itself in QML/JS (`.map()`
over the state's decoded value) would touch the exact same C++→QML
boundary that caused the roof state-display bug above - keeping it in
C++ sidesteps that whole class of risk rather than re-verifying JS
array semantics are safe here too.

**A second, real instance of that same C++→QML boundary risk turned up
while wiring this up, caught by trying it - not by static reasoning.**
The natural-looking approach was a `StateSubscription::field(name)`
`Q_INVOKABLE` helper (pull one named field out of the subscription's
current `value`, so QML never has to search it). That method was written
and then found to break reactivity: QML's binding dependency tracking
only captures *property reads*, not C++ method calls - `field()` reads
`m_value` directly in C++, invisible to the tracker, so a binding that
calls `subscription.field("running")` never re-evaluates when the
subscription's `value` actually changes. Removed before it shipped.
`AutoFocusView.qml` instead reads `.value` directly into a `readonly
property var` (a real property read, correctly tracked - the exact same
pattern `RoofView.qml` already uses for its `KeyValueCard.value`
binding), then extracts named fields from *that* via a plain QML-defined
JS function (`fieldOf()`, styled after `RoofView.qml`'s own
`findInterface()`): a JS function call **does** propagate binding
dependencies, because it executes within the same evaluation context as
the binding itself - only a call across the C++/QML meta-object boundary
is opaque to the tracker. `findInterface()`'s plain indexed
`list.length`/`list[i]` loop (not `Array.isArray()`, not `.map()`/
`.filter()`) was already proven safe live before this widget existed;
`fieldOf()` reuses that exact style for the same reason.

**A third gotcha, also only caught live:** the fitted-focus result
(`FocusFoundEvent`) never showed up in the plot on the first end-to-end
run, despite the RPC itself succeeding and the event genuinely being
sent - `EventManager::handlePubSubEvent` sets `PyobsEvent::module` from
`QXmppUtils::jidToUser(element.attribute("from"))`, i.e. just the
JID's user part ("autofocus"), never the bare JID ("autofocus@localhost")
`ModuleListModel`'s `jid` role holds. `AutoFocusView.qml` was comparing
`FocusFoundEvent` entries against the bare JID directly, which silently
never matched. `LogsView.qml` never hit this because its own module
filter only ever compares event-supplied `module` values against each
other, never against `ModuleListModel`. Fixed by comparing against
`jid.split("@")[0]` instead - worth checking for again in
`AcquisitionView`/`AutoGuidingView` if they end up matching events to a
specific module the same way.

### Custom widget: `IAcquisition`

Second of the three custom widgets tracked in `TODO.md`, ported from
pyobs-gui's `acquisitionwidget.py` - `qml/views/AcquisitionView.qml`,
gated in the sidebar the same way as Roof/Auto Focus
(`MainWindow.qml`'s `hasAcquisitionModule`). Live-verified against a real
`DummyAcquisition` (`fixtures/acquisition.yaml`) end to end: running an
acquisition series, watching both plots update live, the result fields
(RA/Dec/Alt/Az/offset) populating on success, and aborting mid-run.

Simpler than `IAutoFocus` in two respects, both confirmed against the
real disco#info schema before writing any QML: `acquire_target()` takes
no params at all, so this widget didn't need the real-parameter
`executeMethod` overload Phase 8's `IAutoFocus` work added - the existing
paramCount-based overload is enough. And the result
(`AcquisitionResult`) arrives as part of `AcquisitionState` itself
(`state.result`), not a separate event - `acquisitionwidget.py` never
registers one, so `AcquisitionView.qml` doesn't either, sidestepping the
`FocusFoundEvent` JID-format gotcha entirely for this widget (still worth
checking for again in `AutoGuidingView`, see `TODO.md`).

**`PlotItem` grew a real property surface here** (`xFieldIndex`/
`yFieldIndex`, `showLine`, `equalAspect`, `originCrosshair`,
`showStartMarker`/`showLatestMarker`, `xTicksAsIntegers`) to cover
`acquisitionwidget.py`'s two plots: distance-per-attempt (a line, not
just a scatter - `AutoFocusView.qml`'s plot never needed one) and the 2D
offset trajectory (equal-aspect scaling, an origin crosshair, red-square
"start"/green-star "latest" markers). `xFieldIndex`/`yFieldIndex` matter
because `AcquisitionAttempt`'s fields aren't in `(x, y)` position for the
offset plot (`{attempt, distance, offset_applied, offset_frame,
offset_lon, offset_lat}` - offset_lon/lat are indices 4/5, not `PlotItem`'s
default 0/1) - the alternative (reshaping records in QML before handing
them to `PlotItem`) would have meant `.map()`-ing over a value that
crossed the C++→QML boundary, the exact risk class already flagged in the
`IAutoFocus` section above. `setPoints()`/`reparsePoints()` also gained
null-field skipping here (`AcquisitionAttempt.offset_lon`/`offset_lat`
are `optional<float64>`, `None` before an offset frame is known) - a gap
`IAutoFocus`'s always-populated `AutoFocusPoint{focus, value}` never
exposed. Covered by `tests/plot/tst_plotitem.cpp` (new test target,
`QT_QPA_PLATFORM=offscreen`), including a real assertion via the new
test-only `pointCount()`/`pointAt()` accessors - not just "didn't crash."

**The real story of this widget was a `RowLayout` bug that cost most of
the implementation time**, found and fixed only by live screenshot-driven
iteration, not by reasoning about the QML alone:

- First symptom, live: the two plots (meant to sit side by side, matching
  `acquisitionwidget.py`'s `plt.subplots(1, 2)`) rendered with one taking
  almost all the available width and the other squeezed to a barely-
  visible sliver - both `PlotItem`s had identical
  `Layout.fillWidth: true` + `Layout.preferredWidth: 1`. Screenshotting
  the actual running app (via `spectacle -b -n`, this machine's Wayland-
  session screenshot tool, since no window-automation tool was available)
  was what made this obvious in the first place - it hadn't been caught
  by reading the QML.
- Ruled out `PlotItem` as the cause by reproducing the identical lopsided
  split with plain debug-colored `Rectangle`s standing in for both
  `PlotItem`s - confirming this was a `RowLayout` stretch-distribution
  problem, not anything about `PlotItem`'s own (missing) size hints.
- First fix attempt - computing each child's `Layout.preferredWidth`
  directly from the `RowLayout`'s own `id`-referenced width
  (`plotsRow.width`) - **froze the app solid** (window manager reported
  "not responding"). `RowLayout`'s own width is not necessarily
  independent of its children's `preferredWidth`; that binding fed back
  on itself. Recovered by force-killing the process
  (`pkill -9`) and reverting.
- Second fix attempt - a plain `Row` (not `RowLayout`) with each child's
  `width:` computed directly from a stable ancestor
  (`acquisitionDelegate.width`, the `Repeater` delegate's own
  `ColumnLayout`) - didn't freeze, but silently stabilized at a *small,
  wrong* value instead: a temporary `DEBUG root.width=...` label
  (removed once diagnosed) showed `AcquisitionView`'s own root at 365px
  vs. `AutoFocusView`'s root at 676px in the *same* window at the *same*
  size - `acquisitionDelegate.width` turned out not to be the
  externally-driven value it looked like either, so this was the same
  class of circularity as the frozen attempt, just one that happened to
  converge instead of hang.
- Ruled out `Layout.preferredWidth` itself as the culprit by trying
  `Layout.fillWidth: true` alone (no preferredWidth override at all,
  matching how `AutoFocusView.qml`'s single `PlotItem` already works) -
  reproduced the exact same lopsided split. Also tried wrapping each
  `PlotItem` in a plain `Item` (giving *that* the `Layout.*` properties,
  `PlotItem` just `anchors.fill: parent` inside it) on the theory that a
  custom `QQuickPaintedItem` with no `implicitWidth`/size hints of its
  own confuses `RowLayout`'s stretch algorithm - reproduced the same
  failure mode, still with real `PlotItem`s inside. At this point the
  lopsided split had been reproduced with three different child types
  (`PlotItem` directly, `PlotItem` wrapped in `Item`, plain `Rectangle`s
  with no `PlotItem` involved at all) - conclusively a `RowLayout`
  problem in this specific nesting context (`Repeater` delegate inside a
  `ColumnLayout` `StackLayout` page), not a child-type problem, but the
  exact root cause inside `RowLayout`'s stretch-distribution algorithm
  was never actually identified.
- **First resolution: stopped trying to fix `RowLayout` and stacked the
  two plots vertically instead**, via the same plain `ColumnLayout`
  `Layout.fillWidth: true`-per-item mechanism every other page in this
  project (including `AutoFocusView.qml`'s own single plot) already uses
  successfully - shipped and committed as a working, if visually
  different from `acquisitionwidget.py`, layout.
- Stacking two 220px-tall plots vertically pushed the page's total
  content height past a typical window's visible area - the result
  fields/buttons below the plots silently clipped at the window's bottom
  edge. Fixed by wrapping the whole page in a `ScrollView` (`root`'s
  element type, not just a plain `ColumnLayout` like every other page)
  - the first page in this project that needed one, and worth keeping
  regardless of the plot layout question below, since even a single row
  of two plots plus labels/buttons can still exceed a short window.
- **On request, side by side after all** - found on a second attempt, not
  by finally cracking `RowLayout`'s actual bug, but by sidestepping it a
  different way than the two failed attempts above: a plain `Row` (not
  `RowLayout`, same as the failed second attempt) with each `PlotItem`'s
  `width:` computed from `root.availableWidth` instead of
  `acquisitionDelegate.width`. The earlier attempt's circularity was
  specifically about `acquisitionDelegate.width` (a `Repeater` delegate's
  own width, which turned out to be ambiguous when referenced from its
  own descendants) - `root` is the page's own top-level `ScrollView`,
  gets its width authoritatively from `MainWindow.qml`'s `StackLayout`
  from *outside* this file, and nothing inside ever writes back to it, so
  there's no cycle to feed. Confirmed live, stable (no freeze, normal
  CPU), correct split, before asking for confirmation - this is the
  layout `AcquisitionView.qml` actually ships with; the vertical-stack
  fallback above was superseded, not left as an alternate path.
  `TODO.md`'s `IAutoGuiding` entry should be read with this in mind: the
  `root.availableWidth` technique, not vertical stacking, is the
  recommended starting point for that widget's own two plots.
- Two more issues only visible live, not from reading the QML/C++: the
  narrower side-by-side plots' y-axis tick labels (long decimal degree
  values, e.g. `0.0003142`) overlapped the rotated y-axis title text -
  both were being drawn inside the same fixed-width `kMarginLeft = 55`
  zone in `PlotItem::paint()`. Fixed by computing the left margin per-
  paint from the actual widest y-tick label's measured text width
  (`QFontMetrics`) plus a reserved strip for the title, rather than one
  constant shared by both. Separately, `AcquisitionAttempt`'s
  `offset_lon`/`offset_lat` are degrees, which produced exactly those
  impractically long decimal tick labels for values this small - added
  `PlotItem.xScale`/`yScale` (default `1.0`, applied in
  `reparsePoints()`, so no QML-side per-point transform is needed) and
  set them to `3600` on the offset plot, matching
  `autoguidingwidget.py`'s own degrees-to-arcsec convention for the same
  kind of small angular offset. The result row below the plots
  (`RA/Dec offset: (...)`) was switched to arcsec too, for consistency
  with the plot it sits under.

### Custom widget: `IAutoGuiding`

Third and last of the three custom widgets tracked in `TODO.md` - with
this one, that original TODO item (`IAutoFocus`/`IAcquisition`/
`IAutoGuiding`) is fully closed out. Ported from pyobs-gui's
`autoguidingwidget.py` - `qml/views/AutoGuidingView.qml`, gated in the
sidebar the same way as the other three (`MainWindow.qml`'s
`hasAutoGuidingModule`). Live-verified against a real `DummyAutoGuiding`
(`fixtures/autoguiding.yaml`) end to end: starting guiding, watching both
plots accumulate live over several correction cycles, editing the
exposure time and confirming it stuck rather than reverting, and
stopping cleanly.

Reused essentially everything built for `IAcquisition` unchanged: the
`root.availableWidth`-based side-by-side `Row` layout, the `ScrollView`
wrapper, `PlotItem`'s `xScale`/`yScale` for arcsec display. No `PlotItem`
changes were needed at all this time, confirming `TODO.md`'s own
prediction. The one genuinely new mechanism:

**`GuidingState` has no history - unlike `AcquisitionState.attempts`, it
only ever carries the *latest* correction** (`{loop_closed, offset_frame,
offset_lon, offset_lat, time}`, confirmed against the real disco#info
schema before writing any QML, matching `pyobs-core`'s `IAutoGuiding.py`
exactly). `autoguidingwidget.py`'s own bounded sample history
(`_HISTORY_LENGTH = 50`) is therefore built entirely client-side, by
accumulating each state push into a local deque - `AutoGuidingView.qml`
does the same via a plain `property var offsetHistory: []`, appended to
on every `guidingStateChanged` (capped at 50 via `.slice()`). This is a
new pattern for this project - the first client-side-only data
accumulation - but it's *not* the same risk class as the C++/QML boundary
issues flagged elsewhere in this file: `offsetHistory` is built and owned
entirely in QML/JS from primitive numbers (`fieldOf()`'s output), never
itself a value that crossed the boundary as a `Q_PROPERTY(QVariant)`, so
freely `.map()`/`.concat()`-ing it to derive `PlotItem.points` (in the
`{value:...}`-per-field shape `PlotItem` expects - see `PlotItem.h`) is
safe. Ported one Python quirk faithfully rather than "fixing" it on
sight: `_publish_guiding_state()` keeps re-publishing the *last known*
`offset_lon`/`offset_lat` even on an open-loop (lost guide star) push
where nothing new was actually corrected, and `autoguidingwidget.py`'s
own `_on_guiding_state()` appends to history on any non-null offset
regardless of `loop_closed` - so this client does too, meaning the same
stale offset can appear as a duplicate history entry across consecutive
open-loop pushes. Confirmed this is the Python reference's actual
behavior (not an assumption) before matching it.

Two smaller behavioral matches, both confirmed against the live disco#info
schema rather than assumed: `IAutoGuiding` extends `IStartStop` (not
`IRunning` directly) - `IStartStop` itself extends `IRunning`, and
pyobs-core's disco#info duplicates the inherited `state/IRunning/1` block
under both interface names (the same "inherited interfaces get their own
separate entries" gotcha as Phase 7's `IRoof`/`IMotion` case) - so this
page subscribes to the plain `IRunning` state, same as every other
widget, not `IStartStop`. And `set_exposure_time(exposure_time)` is a
genuine single-required-param command, reusing the real-parameter
`executeMethod` overload built for `IAutoFocus`'s `auto_focus()` - no new
C++ needed, just the third call site.

**The live-editable exposure-time `SpinBox`** mirrors
`autoguidingwidget.py`'s `_on_exptime_state` "was-synced" check: a fresh
`ExposureTimeState` push only overwrites the spin box's current value if
the box still shows the *last value this page itself synced from the
server* - so a user's in-progress edit isn't clobbered by an unrelated
state update, but the box still stays live-synced the rest of the time.
Simplified from the Python reference in one deliberate way: no separate
"confirmed value" label next to the spin box (`autoguidingwidget.py`'s
own `ModifiedIndicator` custom widget shows one) - the spin box's own
value already conveys this, and no other page in this project has needed
a second label for the same field. Sends the RPC immediately on
`SpinBox.valueModified` (fires on every user-driven change, whether a
button click or a confirmed text edit) rather than trying to replicate
the Python widget's own delayed-commit interaction - simpler, and
acceptable for a value that isn't expensive to set repeatedly.

### Custom widget: `IMode`

Ported from pyobs-gui's `modewidget.py` - `qml/views/ModeView.qml`, gated
in the sidebar the same way as the other custom widgets
(`hasModeModule`). One row per mode "group" a module exposes: a
`ComboBox` of that group's static options, showing/setting the live
current mode. Live-verified against a real `DummyMode`
(`fixtures/mode.yaml`): all three groups render with the right options,
picking a new mode round-trips over the wire and genuinely cycles
`IMotion` `slewing` -> `positioned` (DummyMode's 3s delay), and the combo
boxes disable/enable correctly around that transition.

**This item's own TODO.md note was briefly wrong, then got corrected
twice in-flight - worth recording since it's a good example of this
project's "verify against source, not memory" discipline catching a real
mistake**: an earlier pass claimed `IMode.set_mode`'s `group` param had
already changed upstream (`pyobs-core`) from a positional index to the
group name itself. Re-checking directly against `pyobs-core` source
before starting implementation found this false - `group` was still
`int`. The item was paused; the user then made that exact change upstream
themselves (`pyobs-core@3a0a70c3`), confirmed again from source once
landed, and only then did `ModeView.qml`/`ModeGroupsRole` get built
against the (now genuinely real) `group: str` shape. New role
`ModuleListModel::ModeGroupsRole` decodes `IMode` capabilities'
`modes: dict[str, list[str]]` field into a `QVariantList` of
`{"group":..., "modes":[...]}` entries - confirmed against the real
disco#info XML (nested `<dict>`-of-`<items>` under the `<capabilities>`
dataclass root) before trusting the `WireDict`/`WireList` decode
assumption. `set_mode(mode, group)` needed no new C++ at all - the
existing real-parameter `executeMethod(jid, name, QVariantList, callback)`
overload (built for `IAutoFocus`) handles two string params exactly like
any other type, confirmed live (not just from reading
`VariantBridge::fromQVariant`) via a throwaway headless harness driving
`comm::XmppClient` directly (same technique as Phase 1/4/7 - `xdotool`/
`wmctrl` still aren't installed here, so this remains the way to verify
C++/wire behavior without GUI input automation).

**Two unrelated things found and fixed/worked around along the way, not
this item's own bugs**:
- The dev ejabberd server's `mode`/`autofocus` (and likely other) fixture
  accounts had their passwords out of sync with what `fixtures/*.yaml`
  assume (`pyobs`) - fixed via `ejabberdctl change_password`, not a
  `pyobs-polaris` or `pyobs-core` bug, just dev-environment drift. Worth
  checking again if a fresh fixture run ever gets "Invalid username or
  password" for an account that's already in `registered_users`.
- `pyobs.modules.utils.DummyMode` isn't re-exported from that package's
  `__init__.py` in `pyobs-core` (every other `Dummy*` module used by this
  project's fixtures is) - `fixtures/mode.yaml` uses the full submodule
  path (`pyobs.modules.utils.dummymode.DummyMode`) as a workaround, which
  works fine since Python's import machinery binds the submodule onto its
  parent package as a side effect regardless of the `__init__.py` export.
  Worth an upstream `__init__.py` fix at some point; not blocking.

**Found, not fixed, out of scope for this item**: the live-verification
harness above segfaulted on shutdown (after all meaningful output had
already been produced) when its `StateSubscription`s were parented
directly to the `XmppClient` they came from and both were torn down
together. `StateSubscription::~StateSubscription()` calls
`unsubscribe()`, which dereferences `m_manager` - a raw pointer into
`XmppClient`'s own `m_client` member (`StateSubscriptionManager`, a
`QXmppClient` extension). If `XmppClient`'s own destructor runs (tearing
down `m_client` and its extensions as ordinary member destruction) before
the QObject base destructor gets to destroy `XmppClient`'s remaining
children (`~QObject()` runs after the derived class's own member
destructors), any subscription still parented directly to `XmppClient`
itself dereferences an already-destroyed manager. Every widget in this
project always parents its subscriptions to a QML delegate item instead
(shorter-lived than `xmppClient`, e.g. `roofDelegate`/`modeDelegate`), so
this specific ordering may not be reachable from the real app today - but
it's a real latent bug in shared `StateSubscription`/`XmppClient`
infrastructure (neither touched by this `IMode` change) worth its own
look, not something to fix as a drive-by here.

### Real filtering on the Logs page

`LogsView.qml`'s single-select "All modules"/one-module `ComboBox`
replaced with real filtering, ported from pyobs-gui's actual
`mainwindow.py`/`logmodel.py` shape (checked directly, not assumed): a
checkbox per known client (`listClients`, a `QListWidget`) feeding a
`QSortFilterProxyModel` (`LogModelProxy.filter_source`) - multi-select
show/hide, not a single active filter. Reuses the existing `knownModules`
idiom (derived from `logEvents`, not a new model) instead of introducing
a `Repeater` over `xmppClient.modules` - this project has no clean idiom
yet for turning a `QAbstractListModel` into a plain JS array outside of
delegate binding (see `EventLogModel::entriesOfType()`'s own comment on
this), and `knownModules` already solves the same problem for the
now-removed `ComboBox`.

**Deliberate divergence, not a bug**: `listClients` is fully
cleared/rebuilt from `self.comm.clients` on every client-list change,
which resets every checkbox back to checked - any filter you'd set is
silently discarded the next time a module connects or disconnects. This
page instead only ever *appends* newly-seen module names to
`knownModules`, so a filter choice (which modules are hidden) survives
new modules coming and going. Trade-off: a module only gets a checkbox
once it has logged at least one entry this session, not the moment it
connects (`listClients` populates from all connected clients regardless
of whether they've logged anything yet).

A minimum-level filter (`ComboBox`: ALL/DEBUG/INFO/WARNING/ERROR/
CRITICAL) was also added - confirmed via `logmodel.py::LogModelProxy`
that the Python reference has **no level filter at all**, only sender
filtering, despite `TODO.md`'s own note mentioning one; added anyway
since this page already computes a level for row coloring, so the
threshold check is nearly free.

Live-verified against two real dummy modules (`DummyRoof`, `DummyCamera`,
started ad hoc against fixture accounts - not new committed fixture
files) rather than just built: screenshotted the running app and
confirmed the level `ComboBox`, per-module checkboxes (correctly labeled,
checked by default), and per-row module attribution all render
correctly. Incidentally surfaced a pre-existing data characteristic, not
a bug in this change: a module's very first startup log line can arrive
with an empty `module` field (an early log message racing the module's
own XMPP JID binding) - the old `ComboBox` would have shown this just as
blankly, the new checkbox list just makes it more visible. **Not
verified**: actually clicking a checkbox/the level `ComboBox` to confirm
the toggle interaction end-to-end - no UI automation tool (`xdotool`/
`ydotool`) was available in this environment and installing one wasn't
requested. The toggle logic itself reuses already-proven QML idioms from
elsewhere in this project (whole-array reassignment for reactivity,
`filter()`/`includes()`/`concat()`), so this is a real but narrow gap,
worth an actual click-test whenever a display with automation tooling is
available.

### New page: all incoming events

`qml/views/EventsView.qml`, ported from pyobs-gui's `eventswidget.py` - a
generic dump of every incoming event across all connected modules, not
just `LogEvent` (which `LogsView.qml`/`LogFooter.qml` already cover on
their own pages). Always visible in the sidebar's TOOLS group, after
Logs - not interface-gated, since events aren't module-type-specific the
way Roof/Auto Focus/etc. are. Sidebar/`StackLayout` indices for Roof/Auto
Focus/Acquisition/Auto Guiding shifted from 3-6 to 4-7 to make room.

`EventLogModel` (Phase 6) already logs every event centrally -
`entries()` (new `Q_INVOKABLE`, factored to share `toVariantMap()` with
the existing `entriesOfType()` rather than duplicate the per-entry
`QVariantMap` construction) is the unfiltered counterpart, same
`{type, module, timestamp, uuid, data}` shape. `LogEvent` itself is
excluded client-side (`EventsView.qml`'s own `refresh()`, `.filter(e =>
e.type !== "LogEvent")`), matching `eventswidget.py::_handle_event`'s own
explicit skip - confirmed live that this actually works, not just
assumed: triggering a real module command (`ITelescope.init()`) produces
both a fresh `LogEvent` (visible only in the Logs page/footer) and a
`MotionStatusChangedEvent` (visible only in this new page), at the same
moment, from the same module.

`data` (a `QVariantMap` crossing the C++/QML boundary) renders via
`JSON.stringify()`, same as `LogEvent`'s own fields already do in
`LogsView.qml` - confirmed live this also holds for a genuinely nested
payload (`MotionStatusChangedEvent`'s data includes a nested `interfaces`
dict, not just flat scalar fields like `LogEvent`), not only the flat
case already proven.

**First shipped with module/type filtering** (the same multi-select
checkbox `Flow` idiom `LogsView.qml`'s own filtering uses), **then
removed on direct request** - this page is meant as a flat, unfiltered
dump of everything, unlike the Logs page. Removing the filter `Flow`s
also surfaced a real layout bug, fixed at the same time: the `Type`
column had no `elide`, so a long event name (e.g.
`MotionStatusChangedEvent`) painted straight over the `Data` column
next to it - `RowLayout` doesn't clip siblings from each other, only
`ListView.clip` clips the whole delegate from the view's own edge.
Fixed with `elide: Text.ElideRight` (plus a wider `Layout.preferredWidth`
in place of the removed filter, and a small `font.bold` to keep it
scannable) instead of just widening the column further, since a
sufficiently long type name would always eventually recreate the
problem otherwise.

Live-verified end to end against two real running modules (`camera`,
`telescope`, already up from an unrelated session) rather than just
built: connected the app, confirmed the Events page and sidebar entry
render correctly with nothing yet received, then drove real RPC calls
(`ITelescope.init()`, `IOffsetsRaDec.set_offsets_radec()`) via a
throwaway script (this project's `ShellView` still can't send real
params yet - see the Shell TODO item - so a script was the only way to
exercise commands with real, non-null arguments) and confirmed the
resulting `MotionStatusChangedEvent`/`OffsetsRaDecEvent` appeared
correctly while the simultaneous `LogEvent`s correctly did not (same
`LogEvent`-exclusion check as the filtered version), then re-verified
after the filtering removal that the `Type` column no longer overlaps
`Data` for a real long event name. The page's default-route wiring
itself needed a temporary local edit to verify each time
(`StackLayout.currentIndex` briefly forced to the new page, since no
click-automation tool was available in this environment either - same
gap noted in the Logs-filtering section above) - reverted before
committing both times, confirmed via a clean rebuild + full `ctest` pass
afterward.

### Resizable sidebar

Direct request: the sidebar was a fixed-width (`Layout.preferredWidth:
180`) child of a plain `RowLayout`, with a manual 1px `Rectangle` as a
purely visual divider between it and the page content - no way to
resize it at all, unlike the log footer below (already a `SplitView`
pane). `MainWindow.qml`'s nav+content `RowLayout` is now itself a
horizontal `SplitView` nested inside the existing vertical one (the
outer `SplitView` still splits nav+content from the log footer; the new
inner one splits the sidebar from the page content) - the sidebar
`ColumnLayout` and content `StackLayout` become `SplitView` panes
(`SplitView.preferredWidth: 180`/`SplitView.minimumWidth: 140` and
`SplitView.fillWidth: true` respectively) the exact same way `LogFooter`
already does for height. The manual `Rectangle` divider is gone -
`SplitView`'s own handle replaces it, both as the visual divider and as
the actual drag target.

Live-verified rendering (correct default width, sidebar content and
content pane both intact, handle visible) but **not** the actual
drag-to-resize interaction - same class of gap as the Logs/Events pages
above (no `xdotool`/`ydotool` in this environment), compounded here by
`MainWindow` only being reachable past a real login, which needed its
own temporary workaround to get past non-interactively: `LoginWindow.qml`'s
`Component.onCompleted` briefly grew an extra `root.quickConnect(lastId)`
call (reusing the existing one-click-reconnect path the account list's
own ▶ button already calls) to skip straight to a connected `MainWindow`
without a click - reverted before committing, confirmed via a clean
rebuild + full `ctest` pass afterward, same discipline as every other
temporary verification edit in this file.

### Shell rewrite: real parameterized command execution

Replaced `ShellView.qml`'s module-picker-then-method-picker-then-click UI
(pyobs-web-client's `ShellView.vue`) entirely with a single-line command
prompt (`module.command(arg1, arg2, ...)`, typed and executed like a
shell) plus history and an autocomplete popup - a port of pyobs-gui's
actual `ShellWidget`/`CommandInputWidget`/
`pyobs.utils.shellcommand.ShellCommand`, not the web client's. Built in
four independently-buildable steps, per this doc's own discipline:

1. `ModuleListModel::CommandSchemasRole` (`commandSchemas`) - the full
   `CommandSchema` per command (`{interface, name, params: [{name, type,
   unit, optional}]}`), alongside the existing `CommandsRole` (left
   unmodified). `codec::wireTypeToString()` (previously an
   anonymous-namespace helper local to `Discovery.cpp`'s debug logging)
   moved into `codec::WireType.h`/`.cpp` as a shared free function so both
   that logging and the new role reuse one implementation.
2. `shell::ShellCommandParser` (`src/shell/`, new) - a hand-rolled
   tokenizer + state machine porting `pyobs-core`'s
   `ShellCommand.parse()` grammar exactly (read directly against the
   installed `pyobs-core` source). Returns `std::optional<ParsedCommand>`,
   matching `codec::parseVersionedFeature()`'s existing hard-parse-failure
   convention - no exceptions, no precedent for those anywhere in this
   codebase. **Two deliberate fixes vs. the Python original, both
   confirmed as real bugs by reading the source, not assumed**:
   single-quoted strings are unquoted correctly (the Python original's
   `t.string[0] in ['"', '"']` check tests a double quote twice - a
   copy-paste bug - so a single-quoted string there keeps its quotes
   attached); a unary `-` is rejected before a string or before a second
   `-` instead of being silently accepted-and-dropped (the Python
   original only ever *applies* `sign` to a `NUMBER`, but doesn't
   *validate* it was followed by one).
3. `XmppClient::executeShellCommand(commandText, callback)` - parses via
   step 2, resolves the typed module name to a bare JID via new
   `ModuleListModel::jidForModuleName()`, and forwards to the existing
   real-param `executeMethod(jid, methodName, QVariantList, callback)`
   overload (built for `IAutoFocus`, reused by `IMode`) - no new
   encode/dispatch logic needed. **Module resolution is by JID local part,
   never by disco#info display name - confirmed against `pyobs-core`'s
   actual `XmppComm` source, not assumed**: `_get_full_client_name()`
   (`xmppcomm.py`) builds the target JID by gluing the typed name directly
   onto the domain with zero lookup/escaping, and `Module.name` is
   explicitly documented in `module.py` as always tracking the comm
   layer's own identity ("since other modules address us by that, not by
   any locally configured string") - a module's `label` is an independent,
   display-only field, architecturally excluded from routing.
   `ShellView.qml`'s prompt (`TextField`, Enter executes and clears,
   Up/Down cycle an in-session command history array) replaces the old
   picker UI wholesale; the scrolling green/red result log is unchanged.
4. Autocomplete popup - a plain QML-native `Popup` (`ListView` over a
   JS-`filter()`ed array, the same idiom `LogsView.qml`/`EventsView.qml`
   already use), not `QCompleter` (lives in `QtWidgets`, which this
   project links nowhere at all). New `ModuleListModel::allCommands()`
   returns a flat `{module, name, params}` list across every connected
   module, deduped by command name per module using the exact same
   "first interface wins" iteration order `executeMethod()`'s own dispatch
   resolution uses, so a suggestion's displayed signature always matches
   what would actually execute. Up/Down navigate the popup's highlighted
   row when it's open (falling back to history browsing when it's not);
   Enter completes a highlighted suggestion before it ever executes
   anything, standard autocomplete convention. No doc/description column -
   confirmed gap, not fixable from the wire alone: this project's
   `CommandSchema` has no equivalent to pyobs-gui's docstring-sourced third
   column.
   - **Bug found and fixed before committing**: the popup's filter
     initially stripped the typed text at its first `(` to get a
     "command name so far" prefix, on the theory that once `(` appears the
     popup should have nothing left to suggest. It didn't work - the
     just-completed command's own `module.command` text still matches
     *itself* via `startsWith`, so the popup never actually closed after a
     selection (or after typing a full command by hand), and Enter kept
     re-completing the same suggestion instead of ever executing it.
     Fixed by checking `text.indexOf("(") !== -1` explicitly and hiding
     the popup unconditionally once true, rather than inferring "nothing
     to suggest" from the filtered list happening to be empty.

**Live-verified against the real dev ejabberd server** (not just unit
tests, per this project's own discipline) via temporary headless
`XmppClient`-driving harnesses (same technique as Phase 1/4/7/`IMode` -
built, run, and deleted again, never committed): real dispatch through
`DummyMode` (`fixtures/mode.yaml`) succeeded for both quoting styles;
an unknown module and an unknown command on a real module both produced
the correct client-side error without ever touching the wire; malformed
syntax was rejected before dispatch. Separately confirmed
`allCommands()`'s dedup logic against a genuine multi-interface case
already live in this environment's own `DummyTelescope` fixture - `init`
is independently declared on `IFilters`, `IFocuser`, `IMotion`, *and*
`ITelescope` all at once, and correctly collapsed to exactly one popup
entry.

### Plugin mechanism, step 1: internal widget registry

`WidgetRegistry.qml` (new, plain `QtObject`) + `MainWindow.qml` changes
only - step 1 of TODO.md's "Plugin mechanism for custom module widgets"
item, no external `.qml` loading yet (that's step 2). Replaces
`MainWindow.qml`'s five hand-written `hasXModule` boolean/`SidebarItem`/
`StackLayout`-page triples (Roof/AutoFocus/Acquisition/AutoGuiding/Mode)
with a registry (`registerForInterface(name, entry)`/
`registerForModule(jid, entry)`, `entry: {iconGlyph, label, component[,
exclusive]}`) and two generic `Repeater`s (sidebar items, StackLayout
pages) driven by it. Built-ins register themselves once in
`Component.onCompleted`; a new `ModuleListModel::hasModule(bareJid)`
backs the jid-registration half the same "QML gets no generic
random-access iteration" way `hasInterface()` already does.

**A real, live-caught duplicate-rendering bug drove the final design, not
the first draft that compiled cleanly and looked right in isolation.**
First attempt: `widgetRegistry.visibleEntries(modules)` *filtered*
`entries` down to only the currently-connected ones, and both Repeaters
iterated that filtered result - meaning a widget's `Component` wasn't
even instantiated until its registration first became visible, by which
point the module backing it could already carry a full data set while
*other* modules were still concurrently connecting. Live-verified (real
ejabberd server, `mode`/`camera`/`telescope` all connecting within the
same couple of seconds, screenshotted via `spectacle -b -n` - this
machine's Wayland-session tool, same as the Acquisition widget's own
`RowLayout` bug write-up above) and caught a real defect: the "Mode" page
showed the exact same `mode@localhost` card **twice**. Bisected by
diffing against a build of the pre-refactor `MainWindow.qml` (confirmed
that version shows the card once, so this was newly introduced, not
latent) and by instrumenting both `refreshVisibleWidgets()` and
`ModeView.qml`'s own per-module delegate with temporary `console.log()`s
(removed before committing): exactly one `Loader`/`ModeView` *instance*
was created, but *that one instance's own* internal `Repeater { model:
xmppClient.modules }` created two delegates for the same jid - its
initial bulk population (the model already had rows by the time this
lazily-created widget finally came into existence) raced a `dataChanged`
for that same row from another module concurrently connecting elsewhere
in the shared model, and the duplicate delegate survived.

Two candidate fixes were tried in sequence, live-verified each time
(the first didn't actually work - recorded here since it's a real dead
end worth not repeating): reassigning `visibleWidgets` to a same-content
array on every redundant `dataChanged` was *also* real (confirmed via
the same `console.log()` instrumentation) and looked plausible as the
cause, but suppressing those redundant reassignments (comparing by
reference before writing) did **not** fix the duplicate - the race is in
the lazily-created widget's own *first* construction, not in how many
times it gets rebuilt afterward. The actual fix: stop filtering the
Repeaters' `model` by visibility at all. `widgetRegistry.entries` (the
full, unfiltered registration list) now backs both Repeaters directly,
so every registered widget is instantiated eagerly at startup - exactly
matching how all five built-ins already behaved *before* this registry
existed (`xmppClient.modules` starts empty, each widget's own internal
Repeater grows one connection at a time, never racing a concurrent
connection against its own construction). `WidgetRegistry.isVisible(entry,
modules)` now only toggles a parallel `visibilityByEntry` boolean array
used for each `SidebarItem`'s own `visible:` - it no longer controls
whether a `Component` exists at all. Confirmed fixed live, same
screenshot method, same three concurrently-connecting modules.

A second, independent bug surfaced by the same live check, before it ever
reached a screenshot: `registerForInterface()`/`registerForModule()`
originally used `entries.push(...)` - an in-place mutation of a `property
var` array, which does **not** emit that property's change signal in
QML. A `Repeater` bound directly to `entries` would never see any of the
five startup registrations at all. Fixed by reassigning
(`entries = entries.concat([...])`) instead - the same "plain array,
reassign don't mutate" discipline this project already uses elsewhere for
reactive `property var` arrays (e.g. `ShellView.qml`'s own `log`/
`history`).

**Resolution rule implemented, not fully wired up - a deliberate,
documented gap, not an oversight**: `WidgetRegistry.isVisible()`'s doc
comment covers this in full. In short, "a jid-registration can mark
`exclusive: true` to suppress the interface-level widget for that one
module" only ever affects registry-level *slot* visibility today, not a
generic widget's own internal per-module rendering (that would mean
retrofitting an exclusion list into every one of `RoofView.qml`/
`AutoFocusView.qml`/`AcquisitionView.qml`/`AutoGuidingView.qml`/
`ModeView.qml`'s internal `Repeater`s, well beyond this step's "pure
plumbing, no behavior change" scope) - moot for now anyway, since no
jid-level registration exists yet to exercise it. Revisit once step 2
lands a real one.

### Plugin mechanism, step 2: external QML plugin loading

`AppSettings::pluginsDirectory`/`pluginFiles()` + `PluginLoader.qml` -
step 2 of TODO.md's "Plugin mechanism for custom module widgets" item.
`AppSettings` gained a `pluginsDirectory` string setting (empty by
default - "don't scan for anything" - `QSettings`-backed, same as
`lastSelectedAccountId`, with no settings-UI control yet, same "add
settings as needed, don't design a UI speculatively" discipline that
class's own header comment already states) and a `pluginFiles()`
`Q_INVOKABLE` (every `*.qml` file directly inside that directory,
non-recursive, returned as ready-to-use `file://` URL strings - resolving
local-path-to-URL conversion in C++ rather than leaving easy-to-get-wrong
string concatenation to QML). `MainWindow.qml`'s `Component.onCompleted`
calls `PluginLoader.loadAll(appSettings.pluginFiles())` right after
registering the five built-ins, then one final `refreshVisibility()`
covering both.

**Plugin file contract** (also documented at the top of
`PluginLoader.qml` itself, and demonstrated end-to-end by
`examples/plugins/TelescopeQuickView.qml`): a plugin `.qml` file's root
type is a plain `QtObject` exposing `targetInterface` XOR `targetJid`
(which of step 1's two registration kinds this is), `iconGlyph`/`label`
(sidebar text), an optional `exclusive` (jid-registrations only - see
step 1's own note on this), and a `widget` `Component` - the actual UI,
instantiated later via `Loader` exactly like a built-in widget's own
`Component`, and able to close over the plugin root's own `xmppClient`
property the same way `MainWindow.qml`'s `roofComponent` et al. close
over `root.xmppClient`. `PluginLoader` instantiates the root object with
`xmppClient` bound to the app's real `XmppClient` - **a considered
choice, not the only option**: TODO.md's own step 2 bullet asked for "a
defined, stable plugin API surface" and named `jid`/`interfaces`/
subscribe-execute helpers as the kind of thing to pass in, which could
have meant a deliberately narrower, curated context object instead of
handing over the whole `XmppClient`. Went with reusing the exact same
contract every built-in widget already gets instead: it's already proven
stable (nothing about it has changed across any of this project's many
widget-adding phases), asks a plugin author to learn nothing new beyond
what's already documented for built-in widgets, and a narrower API would
itself need ongoing design/maintenance for a need that doesn't concretely
exist yet - revisit only if a real plugin actually needs protecting
*from* something on `XmppClient`, not preemptively.

A malformed/errored plugin file is logged via `console.warn()` and
skipped (`Component.status === Component.Error`, or exactly one of
`targetInterface`/`targetJid` not being set) - one broken third-party
file doesn't take the whole app down. `Qt.createComponent()`'s
`Component.Loading` status is handled defensively (connects to
`statusChanged` and finishes registration once ready) even though local
`file://` components load synchronously in every case actually observed -
`refreshVisibility()`'s single call right after `loadAll()` returns
depends on that synchronous-in-practice timing to give a freshly-loaded
plugin its correct initial sidebar visibility; a plugin that genuinely
loaded asynchronously would still register correctly (the registry's
`entries` array is reassigned reactively either way) but would stay
hidden until the next real module-list change - a known, narrow,
accepted gap, not a bug, given no local file has ever actually exercised
that path.

**Live-verified against a real connected module with no built-in widget
at all** - not synthetic: `examples/plugins/TelescopeQuickView.qml`
targets `ITelescope` (a bare `IMotion` marker interface - see this doc's
own `ITelescope` MVP notes; this repo ships no built-in widget for it),
essentially `RoofView.qml`'s own shape pointed at a different interface.
Verified live (real ejabberd server, the same long-running
`dummy-telescope.yaml` instance used throughout this session,
screenshotted via `spectacle -b -n` with the user clicking through since
no input-automation tool exists in this environment - same limitation
noted throughout this file): pointed `AppSettings::pluginsDirectory` at
`examples/plugins/` via a temporary `Main.qml` edit (reverted after,
including explicitly resetting the now-persisted `QSettings` value back
to empty - `AppSettings` writes to the same real config file the actual
app uses, so the temporary *code* being reverted doesn't undo an
already-*persisted* setting on its own), confirmed a "🔭 Telescope
(plugin)" sidebar entry appeared under MODULES with no console warnings,
and clicking into it showed the real `telescope@localhost` module's real
live `IMotion` state (status `parked`, a real timestamp) with working
Init/Park/Stop buttons - proof the whole path works end to end:
directory scanning, component loading, registration, sidebar/StackLayout
rendering, real `xmppClient` binding, and real state subscription/RPC
dispatch from code that lives entirely outside this repo.

---

### Custom widget: `IWeather`

`qml/views/WeatherView.qml`, registered into `WidgetRegistry` the same
one-line way every other built-in widget is (`MainWindow.qml`) - see
TODO.md's "Custom widget: `IWeather`" for the full design rationale.
Simpler than the ported `weatherwidget.py`: `WeatherState` is a plain
dataclass pushed via normal state publication (`good: bool, readings:
list[WeatherSensorReading{sensor, value, unit, time}]`), no RPC polling
needed at all - same subscribe-and-render shape as every other custom
widget. One tile per reading actually present (a `Flow`, not a fixed
11-tile grid), labelled via a client-side map ported from
`AVERAGE_SENSOR_FIELDS` (minus `sunalt` - no equivalent left in the
current `WeatherSensors` enum - plus a new `skymag` entry), with units
read straight off each reading's own wire `unit` field rather than a
second hardcoded map. `WeatherSensorReading` no longer carries a
per-sensor `good` flag (only one overall `WeatherState.good`), so unlike
the old widget's per-tile red/green coloring, this page colors a single
"Weather OK"/"Weather BAD" banner from that one flag instead - there's no
wire data left to color tiles independently.

**The fixture gap TODO.md flagged (no `Dummy*` module implementing
`IWeather`, since the only real implementation is an HTTP client to a
separate `pyobs-weather` service) got resolved upstream rather than
worked around here**: the user added `pyobs.modules.weather.MockWeather`
to `pyobs-core` - a genuinely self-contained simulated station (fixed
default values per sensor, `set_good`/`set_sensor_value` for driving it
in tests). `fixtures/weather.yaml` uses it, same shape as every other
fixture (`{include _comm.yaml}`, `user: weather`/`password: pyobs`) - no
mock HTTP responder needed after all.

Live-verified against a real running `MockWeather`
(`pyobs fixtures/weather.yaml`) with a throwaway headless harness (same
`comm::XmppClient`-direct technique as every other item in this file,
registering two new dev ejabberd accounts, `weather` and
`weatherharness`, for the module and the harness's own login
respectively) - not the QML itself, same limitation as everywhere else in
this file (no input-automation tool in this environment). Confirmed the
decoded `IWeather` state is exactly what `WeatherView.qml` assumes: 10
readings (every non-`TIME` `WeatherSensors` member `MockWeather`
defaults), each `sensor` value one of `WeatherView.qml`'s own
`sensorLabels` map's exact keys (`temp`/`humid`/`press`/`winddir`/
`windspeed`/`rain`/`skytemp`/
`dewpoint`/`particles`/`skymag` - `WeatherSensors` is a `StrEnum`, so the
wire value is the lowercase short form, not the member name), `unit`
already module-supplied text (`celsius`/`percent`/`hpa`/`deg`/`km/h`/
`bool`/`1/m3`/`mag/arcsec2`), and `good` a real bool. The harness's own
teardown then segfaulted - already-known, already out of scope (see this
doc's `IMode` section's own note on `StateSubscription`s parented
directly to `XmppClient`) - after all meaningful output had already
printed, so it didn't block confirming the decode. `set_good`'s RPC
round-trip specifically was *not* verified this way:
`XmppClient::executeMethod`'s real-param overload resolves commands
against disco#info's *interface-declared* commands only, and
`set_good`/`set_sensor_value` are `MockWeather`-only test helpers, not
part of `IWeather`'s own contract - a client-side-only limitation of that
lookup, not a wire bug, and irrelevant to this widget anyway (Start/Stop
controls are explicitly out of scope for this pass, see TODO.md). The
harness source itself wasn't kept, same as every other one-off harness
used throughout this project.

---

### Custom widget: `ITelescope` (MVP)

`qml/views/TelescopeView.qml`, registered into `WidgetRegistry` the same
one-line way every other built-in widget is (`MainWindow.qml`) - see
TODO.md's "Custom widget: `ITelescope` (MVP)" for the full design
rationale/scope. `ITelescope` itself is a bare `IMotion` marker (confirmed
against `pyobs.interfaces.ITelescope` source - no methods/state of its
own), so the base block is identical to `RoofView.qml`'s: `KeyValueCard`
for `MotionState` plus Init/Park/Stop. Two more sections stack below it,
each gated on the module actually implementing the relevant capability
interface, following the exact `findInterface()`/`visible`/
`refreshSubscriptions()` shape every custom widget here already uses:

- **Move** (`IPointingRaDec`/`IPointingAltAz`): a `ComboBox` populated only
  with the coordinate types actually present, switching between an RA/Dec
  page (two decimal-degree `TextField`s with a `DoubleValidator`) and an
  Alt/Az page (two integer-degree `SpinBox`es, alt −90..90 / az 0..360).
  Both are fire-and-forget command fields, not persistent state, so unlike
  Offsets below they don't need the "was synced" idiom - there's no
  server-pushed value they'd ever need to reflect.
- **Offsets** (`IOffsetsRaDec`/`IOffsetsAltAz`): one sub-row per interface
  present, each with its own `StateSubscription` (a module can have up to
  three live subscriptions running at once here - motion plus both offset
  interfaces - following `AutoGuidingView.qml`'s multi-subscription
  `refreshSubscriptions()` pattern, not `RoofView.qml`'s single-subscription
  one). Each sub-row's `SpinBox` pair mirrors `AutoGuidingView.qml`'s
  exposure-time "was synced" idiom exactly: only overwritten by a fresh
  server push if it still shows the last value *this page* last synced, so
  an in-progress edit isn't clobbered by an unrelated update - this also
  serves as the "shows the current offset" display TODO.md asked for, no
  separate read-only label needed. "Set" sends both axes at once; "Reset to
  0" zeroes the `SpinBox`es locally and sends a `(0, 0)` RPC.

Both sections stay disabled until `IMotion`'s `status` is one of the
`telescopewidget.py:287-300`-derived "initialized" set. **Real bug caught
by live verification, not by inspection**: the wire value for
`MotionStatus` is the lowercase enum member (`"idle"`, not `"IDLE"`) -
confirmed both by the live harness output below and by
`ModeView.qml:111-112`'s own `motionStatus`/`initialized` pair, which
already used the correct lowercase form. The first draft of this gating
check compared against the uppercase Python member names and would have
silently left every control permanently disabled against a real module.

**New fixture**: `fixtures/telescope.yaml`,
`class: pyobs.modules.telescope.DummyTelescope` (exported from its
package's `__init__.py`, unlike `DummyMode` - the short class path works
here, no full-submodule-path workaround needed). Confirmed via source it
implements `ITelescope`/`IMotion`/`IPointingRaDec`/`IPointingAltAz`/
`IOffsetsRaDec` (plus `IFocuser`/`IFilters`/`ITemperatures`, unused by this
MVP widget) - covering everything in scope **except `IOffsetsAltAz`**,
which `DummyTelescope` doesn't implement. That sub-row ships schema-
verified only, not live-pixel-verified against a real running module -
exactly the gap TODO.md anticipated. `DummyTelescope.open()` also starts
it in `MotionStatus.IDLE`, not `PARKED`, so Move/Offsets are immediately
usable without calling Init first - unlike a real telescope, which starts
`PARKED` and refuses moves until initialized. Uses the `telescope`
ejabberd account, already registered from an earlier fixture pass.

Live-verified against a real running `DummyTelescope`
(`pyobs fixtures/telescope.yaml`) with a throwaway headless
`comm::XmppClient`-direct harness, same technique as every other item in
this file. Confirmed the decoded `IMotion`/`IOffsetsRaDec` state matches
exactly what the QML assumes (`status`/`devices`/`time`,
`ra`/`dec`/`time`, all in degrees), and exercised `move_radec` and
`set_offsets_radec` end to end - both real `ITelescope`-declared commands,
so (unlike `IWeather`'s `set_good`/`set_sensor_value`) the real-param
`executeMethod` schema lookup succeeded and the RPCs actually landed:
`set_offsets_radec(0.001, -0.002)` pushed a fresh `RaDecOffsetState` back
immediately, confirmed live in the GUI itself (not just the harness) as
`4`/`-7` arcsec in the Offsets `SpinBox`es - proof the "was synced"
live-sync idiom works end to end over the real wire, not just against a
locally-constructed value. The harness's own teardown then segfaulted -
already-known, already out of scope (see this doc's `IMode` section's own
note on `StateSubscription`s parented directly to `XmppClient`) - after
all meaningful output had already printed. The GUI app itself was then
launched against the same live `DummyTelescope` and screenshotted:
sidebar entry, `KeyValueCard` fields, Move section (both coordinate
types selectable), and the Offsets `SpinBox`es all rendered correctly.
Full interactive click-through (typing into RA/Dec fields, switching the
Move `ComboBox`, clicking Set/Reset) was **not** exercised - same
no-input-automation-tool limitation as every other widget in this file -
so that path is verified by code review against established patterns
(`AutoGuidingView.qml`'s identical `SpinBox`/RPC call site) rather than by
an actual click. The harness source itself wasn't kept, same as every
other one-off harness used throughout this project.

---

### Custom widget: `ICamera` (MVP — exposure control, no image display)

`qml/views/CameraView.qml`, registered into `WidgetRegistry` the same
one-line way every other built-in widget is (`MainWindow.qml`) - see
TODO.md's "Custom widget: `ICamera` (MVP)" for the full design rationale/
scope. The largest widget in this project so far by a wide margin:
`ICamera` is `IData + IExposure` (confirmed from source), but a real
camera module combines up to seven more capability interfaces the Python
reference (`camerawidget.py`) shows/hides groups for individually. This
subscribes to `"IExposure"` specifically (the interface that actually
originates `ExposureState`, inherited by `ICamera` the same way
`IMotion`'s state is inherited by `ITelescope`), gating visibility on
`"ICamera"` itself - same split `RoofView.qml`/`TelescopeView.qml` already
use. Up to eight simultaneous `StateSubscription`s per module (`IExposure`
always; `IImageType`/`IExposureTime`/`IBinning`/`IWindow`/`IGain`/
`IImageFormat`/`ICooling` each independently gated), extending
`AutoGuidingView.qml`'s multi-subscription `refreshSubscriptions()` array
pattern further than any prior widget.

**First widget needing module capabilities, not just state.** Confirmed by
reading `pyobs`'s XMPP comm layer that capabilities (`IBinning`'s available
binnings, `IWindow`'s full-frame extent, `IImageFormat`'s available
formats) are published via XEP-0030 disco#info (a one-shot IQ fetched at
connect) rather than XEP-0060 pubsub, but decoded through the exact same
dataclass-from-XML machinery as state. This project's `Discovery.cpp`
already parsed every such element generically into
`ModuleInfo::capabilities: QMap<QString, codec::WireValue>` - nothing
needed to change there. Only three new narrow, per-interface
`ModuleListModel` roles were needed (`BinningOptionsRole`/
`WindowExtentRole`/`ImageFormatsRole`), following `ModeGroupsRole`'s exact
existing pattern (`ModuleListModel.cpp`) rather than inventing a generic
capabilities-dump role - matching this project's established "narrow-scope
discipline" convention. Unit-tested the same way `ModeGroupsRole` already
was (`tests/comm/tst_modulelistmodel.cpp`), one populated + one
absent-capabilities test per role.

**Two real API surprises caught by reading source, not assumed:**
- `IWindow`'s *state* fields are named `x`/`y`, but `set_window`'s
  *command* params are named `left`/`top` for the same axes - a genuine
  wire naming mismatch, not a typo. `CameraView.qml` labels the four
  `SpinBox`es Left/Top/Width/Height for UI consistency but sends them
  through `set_window(left, top, width, height)` while reading the
  live-sync source from `WindowState.x`/`.y`.
  Confirmed live: `set_window(0, 0, 100, 100)` produced a fresh
  `WindowState{x:0, y:0, width:100, height:100}` push.
- `IGain` has **no declared capabilities** (no min/max range on the wire)
  and `set_gain`/`set_offset` are **two separate RPCs**, no combined
  command - `CameraView.qml`'s single "Set" button for that row fires both
  independently.

**Real fix vs. the Python reference, not a faithful port**:
`camerawidget.py`'s own `_window_changed`/`_gain_changed` handlers are dead
`print("ok")` stubs - editing those fields in the real pyobs-gui app never
actually calls `set_window`/`set_gain`/`set_offset` on the wire. This
widget wires all three RPCs up correctly instead of reproducing that gap -
noted here explicitly so a reviewer doesn't mistake the different behavior
for an unintended deviation.

**New territory with zero prior precedent in this project** (confirmed via
`grep` before building): a `ProgressBar` (exposure progress) and a `Dialog`
(the broadcast-uncheck confirmation, "New images will not be processed or
saved. Are you sure?" - `Dialog.Yes`/`Dialog.No`, reverting the `CheckBox`
on reject). Both are plain `QtQuick.Controls` types, no new C++ needed.

**New fixture**: `fixtures/camera.yaml`, `class:
pyobs.modules.camera.DummyCamera` - confirmed via source it implements
`ICamera`/`IExposureTime`/`IImageType` (via `BaseCamera`) plus
`IWindow`/`IBinning`/`ICooling`/`IGain`/`IImageFormat`. **Does not declare
`IAbortable`** - `BaseCamera.abort()` exists concretely but its own
docstring says "Derived class must implement IAbortable for this!", so
it's never advertised via disco#info - the Abort button's gating is
schema-verified only, not live-tested against this fixture, same class of
gap as `ITelescope`'s `IOffsetsAltAz`. **Does not declare `IFilters`**
either. Uses the already-registered `camera` ejabberd account.

Live-verified against a real running `DummyCamera`
(`pyobs fixtures/camera.yaml`) with a throwaway headless
`comm::XmppClient`-direct harness, same technique as every prior widget in
this file - this pass's harness additionally called
`ModuleListModel::find()` directly (a C++-internal, non-`Q_INVOKABLE`
lookup, fine to call from C++ test code) to dump `ModuleInfo::capabilities`
and the three new roles. Every decode matched `DummyCamera`'s real
defaults exactly: `binningOptions` → `["1x1", "2x2", "3x3"]`,
`windowExtent` → `{fullFrameX:0, fullFrameY:0, fullFrameWidth:512,
fullFrameHeight:512}`, `imageFormats` → `["int8", "int16"]`. All eight
real-param RPCs (`set_image_type`, `set_binning`, `set_window`,
`set_gain`, `set_offset`, `set_image_format`, `set_cooling`, `grab_data`)
succeeded end to end and produced the expected state pushes - unlike
`IWeather`'s test-only helpers, every one of these is a real
`ICamera`-family declared command, so the real-param `executeMethod`
schema lookup resolved correctly for all of them. `grab_data(true)` drove
`ExposureState` through `exposing` → `readout` with `progress` 0→100, as
expected. The harness's own teardown then segfaulted - already-known,
already out of scope (see this doc's `IMode` section's own note on
`StateSubscription`s parented directly to `XmppClient`) - after all
meaningful output had already printed. The harness source itself wasn't
kept, same as every other one-off harness used throughout this project.

**GUI screenshot verification was not completed this pass** - unlike
`IWeather`/`ITelescope`, the running `polaris` app came up at a fresh,
empty login screen (no saved account), most likely because the
`pyobs-polaris` rename changed the app's keychain/settings identity
(`DEVELOPMENT.md`'s rename note: "app display name and keychain service
name are now Polaris") so accounts saved under the old `pyobs-gui++`
identity no longer show up. With no `xdotool`/`wmctrl` available in this
environment, there was no way to fill in and submit the login form to
reach the point of visually confirming `CameraView.qml`'s actual pixel
rendering. The wire-level harness above is significantly more thorough
than a visual click-through would have been (every state field, all three
capability roles, and all eight RPCs, vs. a screenshot only confirming
layout), so this is a real but narrow gap, not a substitute for the
missing verification - whoever picks up the next widget should either
register a saved account first (one manual login through the GUI persists
it for every widget after) or continue accepting this same limitation
already documented for `ITelescope`'s Move/Offsets click-through.

---

### `ITelescope` follow-up: libnova + destination-coordinate preview

TODO.md's original scope for this item bundled libnova vendoring, a
destination-coordinate preview, and solar-frame pointing
(`IPointingHGS`/`IPointingHelioprojective`). Split during planning after
two blockers turned up that TODO.md hadn't anticipated - see that item's
own new write-up (a separate, explicitly-blocked entry) for the second
one. This section covers what shipped: libnova + the destination preview.

**Observer location has no wire path at all - confirmed by reading
pyobs-core source, not assumed.** The legacy Python `pyobs-gui`'s
`TelescopeWidget` only had access to an `astroplan.Observer` because it
ran *in-process* as a `pyobs.modules.Module` inside the same `MultiModule`
tree as the telescope module - `pyobs.object.Object.__init__`/`get_object`
share `location`/`observer` via plain Python attribute-copying at
construction time (`pyobs/object.py:245-327,476-479`), never serialized to
XMPP. No `ILocation` interface, no capability, nothing in disco#info
exposes it - a separate XMPP client process like this one structurally
cannot fetch it from a connected module. Fixed by adding three new
`AppSettings` properties (`observerLatitude`/`observerLongitude`/
`observerElevation`, `src/config/AppSettings.h`/`.cpp`) - a client-side-
only value the user enters once via `TelescopeView.qml`'s inline "Observer
Location" `TextField`s, not fetched from any module. Unlike
`pluginsDirectory` (deliberately no settings UI, a one-time developer-only
knob - see that property's own doc comment), this got real UI: it's a
genuinely interactive end-user feature. `AppSettings::hasObserverLocation()`
(`QSettings::contains()`-based, not a NaN sentinel - a double `NaN`'s
round-trip through `QSettings`' on-disk ini serialization isn't guaranteed
reliable across platforms/Qt versions) is how the preview knows "never set"
from "set to (0,0)".

**libnova vendoring.** Vendors the genuine upstream project (hosted on
SourceForge, git-accessible via `git.code.sf.net/p/libnova/libnova`),
pinned to its real tagged release `v0.16` (confirmed via `git ls-remote
--tags` - it does cut real releases, unlike some GitHub mirrors/forks of
it) via `FetchContent` in `cmake/Dependencies.cmake`, same treatment as
qxmpp/QtKeychain. (A CMake-ified third-party fork was evaluated first and
briefly vendored, but replaced with genuine upstream on request - nothing
about that fork's own algorithmic content was ever in question, but
depending on upstream directly is preferable when upstream can be made to
work at all.)

Upstream `v0.16` does ship a `CMakeLists.txt`, but it's old
(`cmake_minimum_required(VERSION 2.6)`, predates any option to disable its
own `lntest`/`examples` subdirectories) and needed several small, purely
mechanical build-system fixes - **none of them touch libnova's own
source/build files**, everything is additive configuration on this
project's own `FetchContent` block:

- `SOURCE_SUBDIR src` points `FetchContent` straight at
  `src/CMakeLists.txt`, skipping the top-level file entirely - its
  unconditional `add_subdirectory(lntest)` defines an executable target
  literally named `test`, which collides with CTest's reserved `test`
  target name once this project's own `enable_testing()` is active (a
  real configure error, confirmed by hitting it, not a hypothetical).
- Skipping the top-level file means its `project(libnova)` call (which
  would have implicitly enabled the C language) and its
  `include_directories(${libnova_SOURCE_DIR}/src)` (needed for libnova's
  own `.c` files to find their own `<libnova/foo.h>` headers) are both
  skipped too - replaced with an explicit `enable_language(C)` and a
  `target_include_directories(libnova PUBLIC ${libnova_SOURCE_DIR}/src)`
  call (`PUBLIC` so this project's own targets that link against
  `libnova` inherit the same include path automatically).
- `LIBRARY_NAME`/`BUILD_SHARED_LIBS` are variables `src/CMakeLists.txt`
  normally expects its (now-skipped) parent to have already set - set
  explicitly instead (`libnova`/`ON`).
- `julian_day.c` guards its own fallback `round()` implementation behind
  `#ifndef HAVE_ROUND` - a macro normally supplied by the `autoconf`
  `configure` script this CMake-only build never runs, so the fallback
  always compiled in and collided with glibc's real `round()` ("static
  declaration of 'round' follows non-static declaration"). `round()` is a
  real C99 function present on every platform this project targets -
  defining `HAVE_ROUND` via `target_compile_definitions(libnova PRIVATE
  HAVE_ROUND)` is the correct fix, not a workaround for something
  actually missing.
- `v0.16`'s own `cmake_minimum_required(VERSION 2.6)` is a hard configure
  error on modern CMake ("Compatibility with CMake < 3.5 has been
  removed") - fixed via `CMAKE_POLICY_VERSION_MINIMUM`, CMake's own
  documented escape hatch for vendoring old projects, scoped to only this
  one `FetchContent_MakeAvailable` call (not set globally).
- `ln_types.h` requires exactly one of `LIBNOVA_SHARED`/`LIBNOVA_STATIC`
  to be defined, but (since the top-level file that would normally set
  this for consumers is skipped) this project's own `polaris` and
  `tst_coordinatetransform` targets need
  `target_compile_definitions(... PRIVATE LIBNOVA_SHARED)` added
  explicitly (`CMakeLists.txt`/`tests/CMakeLists.txt`).

Target name is `libnova` (its own `set(LIBRARY_NAME libnova)`), not `nova`
like the fork used - anyone updating from an older checkout that still
references `nova` needs to update both `target_link_libraries` call sites.

**New C++**: `src/util/CoordinateTransform.h`/`.cpp` - pure functions
(`coordxform::equatorialToHorizontal`/`horizontalToEquatorial`, no `QObject`,
independently unit-tested, `codec::xmlToValue`'s "plain free function"
precedent rather than `PlotItem`'s QML-facing-class one) plus a thin
`QML_SINGLETON` adapter (`coordxform::CoordinateTransform`) `TelescopeView.qml`
calls directly. **Two real bugs caught, neither assumed - both confirmed
against libnova's own source and cross-checked against astropy, then fixed
before shipping:**
- **Azimuth convention.** `libnova/ln_types.h`'s own doc comment on
  `ln_hrz_posn.az`: "0 deg = South, 90 deg = West, 180 deg = Nord, 270 deg
  = East" - South-based, exactly 180° rotated from this project's own
  North-based convention everywhere else (`IPointingAltAz`'s `AltAzState.az`).
  Fixed with `az = fmod(az + 180.0, 360.0)` at the `coordxform` boundary,
  so nothing downstream ever sees libnova's convention.
- **Precession.** `ln_get_hrz_from_equ` expects mean-*of-date* equatorial
  coordinates, not J2000 - `precession.c`'s own doc comment on
  `ln_get_equ_prec`: "Uses mean equatorial coordinates and is only for
  initial epoch J2000.0". This project's RA/Dec convention everywhere else
  (`IPointingRaDec`'s `RaDecState`, what a user types into
  `TelescopeView.qml`, matching pyobs-core's own `BaseTelescope.move_radec`
  - `SkyCoord(..., frame=ICRS)`) is J2000/ICRS. Missing this precession
  step produced a systematic ~0.2-0.4° error against astropy's reference
  values in the unit test - suspiciously close to the ~24.5 years of
  precession (~50″/year) between J2000 and the test dates used, which is
  what led to finding it. Fixed by precessing J2000→date before
  `ln_get_hrz_from_equ` (`ln_get_equ_prec`) and date→J2000 after
  `ln_get_equ_from_hrz` (`ln_get_equ_prec2`).
- **Elevation is accepted but genuinely unused** - `ln_get_hrz_from_equ`/
  `ln_get_equ_from_hrz` take no elevation parameter at all (unlike
  astropy's `EarthLocation`-based transform, which does account for
  observer height). Still stored/passed through for forward compatibility
  with what the user actually enters, not silently dropped from the API,
  but has zero effect on the computed result - noted explicitly in
  `CoordinateTransform.cpp` so it isn't mistaken for an oversight.

No atmospheric refraction correction is applied, matching pyobs-core's own
server-side behavior exactly (confirmed via source: `astroplan.Observer` is
constructed by `pyobs.object.Object` without `pressure`/`temperature`, so
`pressure` defaults to zero/no atmosphere) - the preview would otherwise
systematically disagree with what `move_radec`'s own server-side
`min_altitude` check actually computes.

**Correctness verification methodology** (this feature has no wire/RPC
component at all - "live-verify against a real pyobs module" doesn't apply
the same way it did for every prior widget): cross-checked
`coordxform::equatorialToHorizontal`/`horizontalToEquatorial` against
`astropy`'s `SkyCoord.transform_to(AltAz(..., pressure=0))` for three fixed
(RA, Dec, lat, lon, elevation, JD) tuples, computed via the already-
available `pyobs-core/.venv` astropy install, `tests/util/
tst_coordinatetransform.cpp`, tolerance `0.05°` (libnova and astropy use
different underlying reduction algorithms - not bit-identical, but far
tighter than a "preview before committing to Move" UI needs). All three
cases passed cleanly once precession was added; a fourth test
(`azimuthIsNorthBasedNotLibnovaSouthBased`) pins the convention-fix
direction explicitly so a regression back to the raw libnova value (an
exact 180° error) can't slip through unnoticed even if some future test
tolerance were loosened.

**A second, live-GUI-caught bug, distinct from the two libnova ones
above**: the destination-preview `Label`'s binding originally called
`AppSettings::hasObserverLocation()` (a `Q_INVOKABLE`, not a property) as
its very first check, returning early ("Set observer location above to
preview") when unset. Since a `Q_INVOKABLE` call creates no QML binding
dependency by itself, and the binding's first-ever evaluation happened
while location actually was still unset, the early return meant
`observerLatitude`/`observerLongitude` were *never* read as properties
during that evaluation - so no reactive dependency on them was ever
established, and the preview silently never updated even after a real
location was entered. Caught live: launched the app, watched the user
(interacting with the running window directly, not through screenshot-only
verification) type an observer location into the fields, and the preview
stayed stuck on the placeholder text instead of showing computed values.
Fixed by reading `observerLatitude`/`observerLongitude`/`observerElevation`
unconditionally at the top of the binding, before any early return, so the
dependency is always established regardless of which branch executes.

**GUI verification note**: restarting the app to pick up the above fix
logged out the session, landing back at the login screen (pre-filled
saved credentials, just needs "Connect" clicked) - same
no-`xdotool`/`wmctrl`-available limitation as `ICamera`'s own writeup.
Unlike that pass, though, this feature's correctness rests primarily on
the astropy-cross-checked unit tests above (deterministic, quantified),
not on a visual click-through - the live-GUI session (even though not
fully re-verified end-to-end after the final fix) is what caught the
reactivity bug in the first place, which the unit tests alone couldn't
have (it's a QML-binding-specific bug, invisible to pure C++ tests).

---

### VFS transport (`config::VfsEndpointsModel` + `comm::VfsClient`)

**Scope**: the first slice of TODO.md's "`ICamera` follow-up: image
display, VFS" - config storage + HTTP fetch only, stopping at "bytes in
hand". No FITS decode (`cfitsio`) or image-display widget yet, and
nothing calls this from `CameraView.qml`'s `NewImageEvent` flow yet
either - there's nothing useful to do with raw bytes until decode exists.
Narrower than that TODO item's full scope on purpose; see TODO.md's own
updated text.

**Reference-side finding**: `pyobs-web-client` only has the *config* half
of this (`useVfsConfig.ts` + `SettingsView.vue`'s "VFS Endpoints"
section) - a per-bare-JID `{root, baseUrl, username, password}` list and
`resolveVfsPath()`. Nothing in `pyobs-web-client` actually fetches a file
with it - no `DataDisplayWidget` equivalent exists there at all. This
project is ahead of the reference implementation here, not porting an
existing end-to-end pattern.

**Wire-side confirmation** (`pyobs-core` source, not assumed): `pyobs/
vfs/httpfile.py`'s `HttpFile` backend is a plain HTTP GET
(`urljoin(download_base, filename)`), optional preemptive-safe HTTP Basic
Auth (`aiohttp.BasicAuth`), no `WWW-Authenticate` challenge - it just
401s outright on bad credentials. `VirtualFileSystem.split_root()` splits
a VFS path as `{root}/{rest...}`, leading slash stripped first.

**Design, mirroring `SavedAccountsModel`'s existing keychain-backed list
pattern** (user-confirmed choice over folding this into `CameraView.qml`
or skipping the UI entirely - a real Settings page, since VFS credentials
are sensitive and Polaris had no settings page of any kind before this):

- `config::VfsEndpointsModel` - `QAbstractListModel`, one flat QSettings
  array (now carrying a `bareJid` field per row, unlike
  `SavedAccountsModel`) filtered to `currentJid` for display/row
  bookkeeping (`visibleIndices()` maps model rows to storage indices).
  Password storage/retrieval reuses `SavedAccountsModel`'s exact async
  QtKeychain job shape (`storePassword`/`loadPassword`/
  `clearStoredPassword`, same `kKeychainService = "Polaris"` - safe to
  share since both classes key entries on their own independent random
  `QUuid` ids, not on anything that could collide). `resolveVfsPath()`
  reimplements `split_root` + endpoint lookup, returning
  `{url, endpointId, username, hasStoredPassword}` for a caller to then
  drive `loadPassword()`/`VfsClient::fetchFile()` itself - this class
  does no fetching of its own.
- `comm::VfsClient` - wraps one `QNetworkAccessManager` (already linked
  via `Qt6::Network`, no new dependency). `fetchFile(requestId, url,
  username, password)` sends `Authorization: Basic` preemptively rather
  than reacting to a 401 challenge - simpler, and correct here since
  `HttpFile`'s server side never sends a challenge anyway. No caching, no
  retry - every call is a live GET, matching this project's "the wire
  protocol is the source of truth" stance elsewhere.
- `qml/views/SettingsView.qml` - new page, new "Settings" sidebar entry
  (static pages are now indices 0-4: Status/Shell/Logs/Events/Settings;
  dynamic `WidgetRegistry` pages now start at index 5, not 4 - every
  `stack.currentIndex` arithmetic in `MainWindow.qml` shifted
  accordingly). List-left/details-right, same idiom as
  `LoginWindow.qml`'s account manager. Its "Test connection" button
  fetches the endpoint's bare `baseUrl` (not a real VFS file - there's no
  filename to test against outside of a real `grab_data()` call) purely
  to prove reachability/auth wiring; any HTTP response (even a 404)
  distinguishes "the server answered" from "connection refused/timed
  out".
- `VfsEndpointsModel`/`VfsClient` are instantiated once in `Main.qml`
  (`VfsEndpointsModel.currentJid: xmppClient.jid` - already bare,
  `LoginWindow.qml`'s `jidField` has no separate resource input) and
  passed down through `MainWindow.qml`, same top-level-wiring pattern as
  `XmppClient`/`AppSettings`/`SavedAccountsModel`.

**Testing**: `tests/config/tst_vfsendpointsmodel.cpp` mirrors
`tst_savedaccountsmodel.cpp`'s shape exactly, including the same
real-keychain-backend/CI-skip idiom for the two keychain round-trip
tests, plus `currentJid`-filtering and `resolveVfsPath` split/join cases.
`tests/comm/tst_vfsclient.cpp` is new in kind for this project - a
hand-rolled `QTcpServer`-based local HTTP stub (success body, preemptive
Basic Auth header capture, 404, connection-refused) rather than mocking
`QNetworkAccessManager`, matching this project's "verify against the
real thing" bar in miniature for a component too fast/local to need a
whole ejabberd+fixture round trip just to unit-test HTTP parsing.

**Live verification** (`fixtures/httpfilecache.yaml` is new - pairs with
`fixtures/camera.yaml`, which gained a `vfs:` block pointing its `cache`
root at it, plus a `location:` block): confirmed the *entire* chain for
real, not just the new C++ code in isolation. `pyobs
fixtures/httpfilecache.yaml` + `pyobs fixtures/camera.yaml` running
against the dev ejabberd server, `grab_data()` invoked via a throwaway
Python `XmppComm` proxy script (mirrors driving it from `CameraView.qml`'s
existing "Expose" button, without needing GUI automation - see below)
returned `/cache/pyobs-20260710-0001-e00.fits.gz`. A hand-compiled
headless harness (this project's documented technique - `moc` run
manually, linked directly against the built `VfsEndpointsModel.cpp`/
`VfsClient.cpp` plus the vendored `libqt6keychain.so`/`qtkeychain`
FetchContent headers under `build/Release/_deps/`) then called
`resolveVfsPath()` on that exact filename and `fetchFile()` on the
result: **532800 bytes, sha256
`21e48d5038a5a54c67c11ee0427e90f595ae6b2607c810ed7b958db7d57bd1ae`**,
byte-for-byte identical to a plain `curl` of the same URL used as an
independent reference. Two real gaps, both by necessity rather than
oversight:
- `pyobs.modules.utils.HttpFileCache` (confirmed via source) takes no
  `username`/`password` constructor args at all and enforces no auth -
  there's no live pyobs module anywhere to test `VfsClient`'s
  preemptive-Basic-Auth path against, so that path is stub-server-tested
  only (`tst_vfsclient.cpp`), same class of gap as `ICamera`'s
  `IAbortable`/`IFilters` schema-verified-only caveats.
- No GUI click-through of the new Settings page itself - same
  no-`xdotool`/`wmctrl`-available limitation noted in `ICamera`'s and the
  `ITelescope` follow-up's own write-ups. The wire-level harness above
  (byte-identical fetch of a real, live-produced file) is a stronger
  correctness signal than a visual click-through would have been for
  this particular feature (data correctness, not layout), so this is a
  real but narrow gap, not a substitute for verification that matters
  here.

**Fixture-writing gotcha, worth remembering**: `BaseCamera`'s default
`filenames` pattern is `/cache/pyobs-{...}.fits.gz`, but
`VirtualFileSystem`'s own built-in default roots are only `pyobs`/
`robotic` (both `LocalFile`) - `cache` isn't one of them. Without an
explicit `vfs:` block, `grab_data()` fails outright with "Could not find
root cache for file", not a silent fallback to some default location.
Separately, `grab_data()` also unconditionally needs a `location:` block
- `FitsHeaderMixin`'s `DAY-OBS` header computation calls
`night_obs(self._observer)`, and `_observer` is `None` without one
(`AttributeError: 'NoneType' object has no attribute 'sun_set_time'`,
confirmed live) - neither gap is specific to VFS, but both blocked this
verification pass until fixed, and would block any future
`grab_data()`-touching work against this fixture the same way.

---

### FITS decode (`fits::FitsImage`, first real Conan dependency)

**Scope**: the second slice of TODO.md's "`ICamera` follow-up" - decode
only. `fits::FitsImage` (new `src/fits/`) turns a complete in-memory FITS
file (the exact bytes `comm::VfsClient::fetchFile()` produces) into
`width()`/`height()`/row-major `double` pixels/header cards. No QML
surface, no `CameraView.qml` wiring, no display widget - this project's
own `CoordinateTransform.h` precedent (plain, independently-testable
pure functions/classes, QML adapter added later only once something
actually needs one) applies here too: nothing consumes decoded pixels
yet, so there's no QML API worth guessing at before the display widget
(TODO.md's next bullet) shapes what it actually needs.

**`cfitsio` is this project's first real Conan dependency** (previously
just `[generators]`/`[layout]`, zero `[requires]` - see Phase 0's own
note anticipating exactly this). Unlike `qxmpp`/`QtKeychain`,
`find_package(cfitsio REQUIRED)` + `cfitsio::cfitsio` needed no
FetchContent workaround - cfitsio has no Qt dependency of its own to
conflict with system Qt6, so ConanCenter's ordinary binary/source
resolution just works.

**API surface used** (cfitsio's "long name" macros, confirmed against
the actual vendored `fitsio.h`/`longnam.h` rather than assumed from
memory - the short `ff...` names are what's declared in `fitsio.h`
itself, `longnam.h` is a header of plain `#define` aliases mapping the
friendly names onto them):
- `fits_open_memfile`/`fits_close_file` - reads directly from the
  in-memory `QByteArray` (`buffptr` points straight at
  `data.constData()`, no copy), `READONLY` mode so `mem_realloc` is
  passed `nullptr` and simply never invoked (that callback only exists
  for growing a buffer being written to).
- `fits_get_num_hdus`/`fits_movabs_hdu`/`fits_get_img_param` - walks HDUs
  looking for the first `IMAGE_HDU` with `NAXIS == 2` and real
  dimensions, skipping a dataless primary HDU (`NAXIS == 0`) if present.
  Not something this project's own `DummyCamera` fixture actually
  produces (confirmed live - see below: it writes the image straight
  into the primary HDU, `EXTNAME='SCI'` is just a header card on it, not
  a real extension), but a real, well-known FITS convention worth
  handling defensively rather than assuming every future producer looks
  like `DummyCamera`.
- `fits_read_img(..., TDOUBLE, ...)` - reads pixel data as `double`
  regardless of the file's actual on-disk `BITPIX` (int8/16/32/64 or
  float32/64), with cfitsio applying any `BZERO`/`BSCALE` unsigned
  rescaling itself. A future stretch/display widget wants one uniform
  pixel type to work with, not eight separate on-disk-type branches.
- `fits_get_hdrspace`/`fits_read_keyn` - header cards in file order
  (not semantically meaningful the way `codec::WireDict`'s wire order
  is - kept anyway since it's simply what a raw card list naturally is).

**Testing** (`tests/fits/tst_fitsimage.cpp`): the "happy path" fixture
(a minimal 2x2 `BITPIX=16` image, values including a negative one to
exercise two's-complement decoding) is hand-built byte-for-byte, not
generated via cfitsio's own writer - deliberately independent of the
code under test, so a decode bug can't be masked by a matching encode
bug. The "dataless primary HDU + image extension" fallback case, by
contrast, *is* built via cfitsio's write API
(`fits_create_memfile`/`fits_create_img`/`fits_write_img`) - hand-rolling
a second HDU's exact byte layout (`XTENSION` card, `PCOUNT`/`GCOUNT`,
block alignment) by hand would itself be exactly the kind of
error-prone detail worth leaving to a library, and this only exercises
cfitsio's *write* path while `FitsImage::decode()` only ever calls its
*read* path, so the two stay meaningfully independent.

**Live verification**, extending the VFS transport harness from the
section above rather than starting over: `grab_data()` via the same
throwaway `XmppComm` proxy script (`/cache/pyobs-20260710-0002-e00.fits.gz`,
a fresh file, not the one reused from the VFS transport pass) →
`VfsEndpointsModel::resolveVfsPath()` → `VfsClient::fetchFile()` → piped
straight into `FitsImage::decode()`, all in one hand-compiled headless
harness (same manual-`moc` technique as before, now also linking
`FitsImage.cpp` against the vendored cfitsio static lib + `libz` - note
for next time: cfitsio's static lib needs `-lz` explicitly on the final
link line, or `libQt6Network.so`'s own `-lz` link ends up earlier on the
command line than cfitsio's undefined `inflateEnd` reference and GNU ld
refuses to resolve it backwards). Decoded **512×512, BITPIX 16, DATAMIN
5.0/DATAMAX 14.0, IMAGETYP 'object', EXTNAME 'SCI', 65 header cards** -
every one of these independently cross-checked against `astropy`'s own
read of the same bytes (via the already-available `pyobs-core/.venv`)
and matching exactly, including the header card count. The actual
decoded pixel min/max (**5, 14**) matched the file's own `DATAMIN`/
`DATAMAX` header claims exactly too - proof the pixel *data*, not just
the header parsing, decoded correctly.

---

### Image display widget (`fits::FitsImageItem`)

**Scope**: the third and final slice of TODO.md's "`ICamera` follow-up",
completing the chain the VFS transport and FITS decode sections above
each stopped short of wiring up. `fits::FitsImageItem` is a new
`QQuickPaintedItem` (`src/fits/`, `QML_ELEMENT`) that decodes, stretches,
and renders a FITS image, and `CameraView.qml` now drives it from a real
`NewImageEvent`.

**No existing Qt/QML widget was a fit** (a real question asked and
answered before writing any code, not assumed): the legacy reference
(`../qfitswidget`) is Python + Qt Widgets + `matplotlib`'s
`FigureCanvasQTAgg` + OpenCV + astropy WCS - a heavy widget-based stack,
not a `QQuickItem`, not portable to this project's QML architecture.
KStars/`libkstars`'s `FITSViewer` is the closest mature C++/Qt FITS
viewer, but it's Qt Widgets too, GPL-licensed, and pulls in a large slice
of KDE/KStars infrastructure just for the viewer widget. Nothing
maintained and `QQuickItem`-native exists. Built from scratch instead,
following `plot::PlotItem`'s existing precedent (this project's only
other custom-painted QML item) - a `QQuickPaintedItem` painting a
pre-built `QImage`, not a live-recomputed-every-frame render.

**Design**:
- `fits::FitsStretch.h/.cpp` (new, pure functions, no Qt-object/QML
  dependency - same "independently testable" shape as
  `coordxform`/`FitsImage` before it) - `computeStretch()` (min/max, or a
  simple symmetric-percentile-tail-clip - deliberately *not* DS9-style
  iterative zscale, a materially more involved algorithm not justified
  without a concrete need) and `renderGrayscale()` (maps pixel values
  into a `QImage::Format_Grayscale8`, flipping FITS's bottom-up row order
  to QImage's top-down convention in the same pass, so nothing downstream
  needs to know the two disagree).
- `fits::FitsImageItem.h/.cpp` (new, the actual `QQuickPaintedItem`) -
  `loadFitsBytes(QByteArray)` decodes via `FitsImage::decode()`,
  recomputes the stretch/cached render, and repaints; a failed decode
  leaves whatever was previously displayed in place rather than blanking
  it (a single bad/truncated fetch shouldn't erase the last good frame).
  `stretchMode` is a plain `QString` ("minmax"/"percentile"), not a
  `Q_ENUM` int - matches this project's existing convention for
  QML-facing enum-like state (`comm::XmppClient::status`'s own
  "disconnected|connecting|..." strings) over introducing a new
  `Q_ENUM`-registered type for two values.
- **Zoom/pan are deliberately not implemented in C++.** QML already has
  idiomatic tools for both - `CameraView.qml` wraps the item in a
  `Flickable` (pan, for free) and drives the item's own `width`/`height`
  from a zoom `SpinBox` (`FitsImageItem` just smoothly rescales its
  cached `QImage` into `boundingRect()` on every paint - reimplementing
  flick physics in C++ would only duplicate what `Flickable` already
  does).
- `CameraView.qml` wiring: `NewImageEvent` delivery itself needed no new
  C++ - `EventManager` already subscribes to every event a module's
  disco#info advertises (Phase 6), so this only needed to notice a new
  one arriving for *this module's* jid
  (`xmppClient.events.entriesOfType("NewImageEvent")`, the same
  `Connections { onRowsInserted }` idiom `EventsView.qml` already uses)
  and drive `VfsEndpointsModel::resolveVfsPath()` →
  (`loadPassword()` if the endpoint has one, async) →
  `VfsClient::fetchFile()` → `FitsImageItem::loadFitsBytes()`. Every
  in-flight request is correlated back to its own `Repeater` delegate via
  a `jid|filename` request id and the endpoint id from `resolveVfsPath()`
  - both `VfsClient`'s and `VfsEndpointsModel`'s signals are global, not
  scoped to one delegate, since multiple cameras can legitimately be
  fetching concurrently (possibly even sharing one VFS endpoint's
  password load).

**Testing**: `tests/fits/tst_fitsstretch.cpp` covers `computeStretch()`
(min/max, percentile-tail-clip math checked against hand-computed
indices, non-finite values ignored, empty/all-non-finite fallback) and
`renderGrayscale()` (black/white mapping, the FITS-to-QImage row flip
specifically, flat-image divide-by-zero handling, size-mismatch
rejection). `tests/fits/tst_fitsimageitem.cpp` covers the item's public
API short of `paint()` itself (load success/failure, failure preserving
the previous image, stretch-mode changes recomputing levels) - same
"don't test `paint()` directly" precedent `tst_plotitem.cpp` already
set.

**Live verification**: extended the FITS decode section's harness
further - `grab_data()` → `VfsClient::fetchFile()` →
`FitsImageItem::loadFitsBytes()` end to end against the same
`fixtures/httpfilecache.yaml` + `fixtures/camera.yaml` pair, confirming
`hasImage`/`imageWidth`/`imageHeight`/`blackLevel`/`whiteLevel` all
populated correctly from a real fetched frame. Beyond that, went one step
further than every prior wire-level-only harness in this project: dumped
the actual rendered `QImage` to a PNG and visually inspected it (via
Claude Code's own image-reading capability, not just byte/dimension
assertions) - a clean, correctly-decoded 512x512 grayscale noise field,
exactly matching `DummyCamera`'s synthetic random test image, no
flip/clipping artifacts. No GUI click-through of `CameraView.qml`
itself (same no-`xdotool`/`wmctrl`-available limitation noted in every
prior widget's write-up in this file) - the rendered-PNG check is a
stronger correctness signal for *this specific feature* (pixel data
correctness, not layout) than a screenshot would have been anyway.

**Addendum - a real GUI click-through (by the user, not automation) did
catch a bug the wire-level harness above could not have**:
`checkForNewImage()`'s `events[i].module !== jid` comparison never
matched, so a fetch never even started - no loading/error label, nothing
- while `grab_data()` itself succeeded and the `NewImageEvent` visibly
appeared on the Events page, making it look like event delivery itself
was broken. Root cause: `EventLogModel`'s `module` field is the *local
part only* of the sender's JID (`EventManager.cpp` uses
`QXmppUtils::jidToUser()`), but `cameraDelegate.jid` (from
`ModuleListModel`) is the full bare JID (`"camera@localhost"`, per
`ModuleInfo.h`'s own comment) - `"camera" !== "camera@localhost"` is
always true. Fixed by comparing against `jid.split("@")[0]` instead.
Purely a QML-side bug (a string-format mismatch between two existing,
independently-correct C++ pieces), invisible to every headless C++
harness used throughout this pass - the harnesses called
`VfsEndpointsModel`/`VfsClient`/`FitsImage` directly with the right
filename already in hand, never exercising the
`EventLogModel`-to-`ModuleListModel` JID correlation this bug was in.
Worth remembering for any *future* code that correlates an event's
`module` field against a `ModuleListModel`-sourced `jid` - this is the
first place in the project that did, and got it wrong the first time.

---

### `CameraView.qml` layout pass + global style switch (Material -> Fusion)

**Prompted by direct user feedback on a live screenshot**, not a
self-driven redesign: the ICamera MVP's flat vertical list of
`RowLayout`s (shipped in the earlier "Add ICamera widget (MVP)" commit)
read as "absolutely ugly" once actually seen running. Fixed by porting
`camerawidget.ui`'s own structure (Qt Designer XML, read directly - see
`pyobs-gui/pyobs_gui/qt/camerawidget.ui`) plus a real screenshot of the
legacy app running against this same dev fixture set, both consulted
before writing any QML: a narrow sidebar of titled `GroupBox`es (Window /
Binning & Format / Gain / Exposure), a dominant image area, a third
column for Cooling (mirroring the legacy's own right-hand sidebar
position), status/progress pinned to the very bottom of the sidebar
(not mixed into the Exposure controls), color-coded Expose/Abort buttons,
and small grey "current value" labels next to editable Window/Gain/
ExpTime fields (`WatchedLabel`'s own pattern in the legacy).

**Global style switched from Material to Fusion** (`QQuickStyle::setStyle
("Fusion")` in `main.cpp`, before `QQmlApplicationEngine` construction) -
a second, larger fix that came out of that same screenshot review.
Material's `SpinBox` renders large fixed-size `-`/`+` buttons that don't
shrink with the control; in the sidebar's now-narrower column these ate
most of the width and squeezed the actual number field down to nearly
nothing - confirmed by literally looking at a screenshot, not inferred
from QML alone. Fusion (a classic, compact desktop style - small native
up/down arrows, no oversized touch targets) fixed this app-wide, and
happens to be much closer to the legacy PyQt widget's own native sizing
in the first place.

Real gotchas hit along the way, worth remembering for any future style
work:
- **Setting `Material.theme` anywhere locks the app to the Material
  style**, silently overriding `QT_QUICK_CONTROLS_STYLE` / a runtime
  `QQuickStyle::setStyle()` call - confirmed live: setting the env var
  alone (with `Material.theme: Material.Dark` still present in
  `MainWindow.qml`/`LoginWindow.qml`) had zero visible effect. Removing
  the `Material.theme` lines (and the now-unused `import
  QtQuick.Controls.Material`) was required before the style switch took
  effect at all.
- **`QQuickStyle` needs `Qt6::QuickControls2` linked explicitly** -
  `Qt6::Quick` alone doesn't pull it in; the build fails with a plain
  `fatal error: QQuickStyle: No such file or directory` otherwise. Added
  `QuickControls2` to the `find_package(Qt6 ...)` component list and
  `Qt6::QuickControls2` to `target_link_libraries`.
- **Material-specific attached properties silently become no-ops under a
  different style** - `Material.background`/`Material.foreground` (used
  for the green Expose / red Abort buttons) do nothing once Fusion is
  active, since Fusion's `Button` never reads them. Switched to the
  style-agnostic `palette.button`/`palette.buttonText` (Fusion's own
  theming is built on `QPalette`), which works under any style, not just
  Material.
- **A `RowLayout` child wider than its column's `Layout.maximumWidth`
  doesn't clip - it stretches the whole column past the limit.** The
  `Count:` + `SpinBox` + `Broadcast` `CheckBox` row's combined implicit
  width exceeded the sidebar's 220px cap, which stretched every
  `Layout.fillWidth: true` sibling in the same `GroupBox` (including the
  Expose button) past the sidebar's right edge into the image column -
  caught live from a screenshot showing the green Expose button visibly
  bleeding across the column boundary, not obvious from reading the QML.
  Fixed by splitting cramped rows (`Count`+`Broadcast`, `Exp. time`
  label+value+`SpinBox`) onto their own separate `RowLayout`s/
  `ColumnLayout`s instead of trying to fit everything on one line.

**Live verification note**: `spectacle` (KDE's screenshot tool, already
installed) turned out to work for actually seeing the running app in
this environment, unlike the `xdotool`/`wmctrl`-shaped gap every prior
widget's write-up in this file noted - `spectacle -b -n -f -o
<path>` (background, no notification, fullscreen) or `-a` in place of
`-f` for just the active/focused window. This unblocks real visual
verification for future UI work in this dev environment - update those
older "no GUI click-through" notes' framing if picking up related work,
they're no longer a hard tooling gap, just something not tried yet at
the time.

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

`git@github.com:pyobs/pyobs-polaris.git` — renamed from `pyobs-gui++`
(itself renamed from `pyobs-qml-client` during Phase 0): `++` isn't valid
in a GitHub repo name, which the old name only worked around with a
trailing hyphen (`pyobs-gui-`); the project and its GUI are both just
called Polaris now, sidestepping the problem rather than working around
it again. Currently reports as private to unauthenticated GitHub API
reads, which also means CI run status and release contents can't be
checked from a plain unauthenticated `curl` — needs either the `gh` CLI
with a token, or checking directly on github.com.
