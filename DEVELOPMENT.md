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
  system default location (e.g. `~/.config/pyobs/pyobs-gui++.conf` on
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
  on the account's `id` under service `"pyobs-gui++"`. On Linux this needs
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
  `pyobs-gui++` binary for releases (`.github/workflows/build.yml`'s
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
