# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Polaris** (repo: `pyobs-polaris`) is a clean-room C++/QML desktop client
for **pyobs 2.0** (an observatory control framework), modeled directly on
`pyobs-web-client`
(TypeScript/Vue): no dependency on `pyobs-core` itself — everything is
built from XMPP presence + disco#info discovered live over the wire
(QXmpp instead of Strophe.js). Generic rendering by default; hand-written
QML widgets opt in per-interface only where a custom UI earns its place
(`IRoof`, `IAutoFocus`, `IAcquisition`, `IAutoGuiding`, `IMode`,
`IWeather` so far).

Reference implementation to port from (clone separately, next to this
repo — not vendored):
`git clone git@github.com:/pyobs/pyobs-web-client.git`
- `src/pyobs-codec.ts` — value↔XML codec, schema parsing
- `src/composables/useXmpp.ts` — connection, discovery, state
  subscription, RPC, presence
- `src/components/ModuleStateCard.vue` + `KeyValueCard.vue` — generic
  rendering
- `src/views/RoofView.vue` — the pattern for a custom, interface-specific
  widget built on top of the generic plumbing

**`DEVELOPMENT.md` is the primary reference** for this project: full
environment setup, a phase-by-phase history of every completed feature
with its design decisions and gotchas, the plugin file contract, and the
release process. `TODO.md` tracks what's planned next. Read the relevant
section of `DEVELOPMENT.md` before touching an area you haven't worked in
— many non-obvious constraints (Qt version skew, QML scoping traps, wire
protocol quirks) are documented there and nowhere else. If a change
reveals something `DEVELOPMENT.md`/`TODO.md` didn't anticipate, **fix
those docs too, not just the code**.

## Build, test, run

```bash
# One-time per machine:
pipx install conan && conan profile detect --force

# Generates CMakeUserPresets.json (gitignored) - must run before the
# cmake --preset step below.
conan install . --build=missing

cmake --preset conan-release -DCMAKE_BUILD_TYPE=Release
cmake --build --preset conan-release
ctest --output-on-failure --test-dir build/Release

./build/Release/polaris
```

The first configure fetches and builds `qxmpp` (~100 source files) and
`QtKeychain` from source via CMake `FetchContent` — this is the slow part
of a clean build (several minutes). Both are pinned in
`cmake/Dependencies.cmake` (kept separate from `CMakeLists.txt` so CI's
build cache only busts on an actual dependency-version bump, not on every
new source file added to the executable/qml-module lists).

Run a single test binary directly, e.g.:
```bash
./build/Release/tests/tst_statesubscription
ctest --test-dir build/Release -R tst_wirevalue --output-on-failure
```

### Prerequisites (Linux; developed/CI'd on Ubuntu 26.04)
- Qt 6.5+ system packages (always links against **system** Qt, never
  bundled): `qt6-base-dev qt6-base-dev-tools qt6-declarative-dev
  qt6-declarative-dev-tools`
- `libsecret-1-dev pkg-config` (QtKeychain's Linux Secret Service backend)
- CMake 3.21+, C++20 compiler
- Conan 2.x via `pipx` (plain `pip install` is PEP-668-blocked on most
  distros)
- `patchelf` only needed for cutting a release, not day-to-day building

### Live verification, not just unit tests
Every completed phase in `DEVELOPMENT.md` was verified against a **real
ejabberd server and real running pyobs-core modules**, not just unit
tests — this project's whole premise is that the wire protocol is the
source of truth. Keep that bar for new work: `fixtures/*.yaml` holds the
dummy-module configs used so far (each includes the shared
`fixtures/_comm.yaml` XMPP block); start one with `pyobs
fixtures/<module>.yaml` from a `pyobs-core` venv, register a matching
XMPP account (`ejabberdctl register <user> localhost <password>`), and
verify live. Add a new `fixtures/<module>.yaml` whenever a new
interface-specific widget needs its own dummy module, rather than
reaching for an external/uncommitted config.

A headless C++ test-harness technique (see `DEVELOPMENT.md`'s
"Live-verification test fixtures" section) is used to verify wire
behavior without a GUI: hand-compile a standalone `QCoreApplication`/
`QGuiApplication` + `QQmlApplicationEngine` program linking directly
against the already-built `libQXmppQt6.so` under
`build/Release/_deps/qxmpp-build/src/`. For loading real `.qml` files
this way, point `QQmlEngine::addImportPath()` at a copy of the generated
`build/Release/pyobs/polaris/` dir with the `prefer :/qt/qml/...` line
stripped from its `qmldir` — otherwise it silently fails to resolve with
no warnings. This technique cannot confirm actual window visibility on a
real compositor (offscreen QPA is a harness artifact, not proof of a UI
bug).

### CI notes
- Runner is pinned to `ubuntu-26.04`, not `ubuntu-latest` (which lags
  ~2 years behind on Qt6 apt packages — already caused two build breaks).
- `tst_savedaccountsmodel`'s two keychain-backed tests skip themselves
  under CI (checks the `CI` env var) — a bare runner has no D-Bus
  keyring; getting a real headless Secret Service running was tried and
  abandoned (see `DEVELOPMENT.md`).
- Releases: push a `vX.Y.Z` tag and CI builds, tests, `patchelf`-fixes the
  RUNPATH, tars up the binary + vendored `.so`s, and creates the GitHub
  release automatically (`.github/workflows/build.yml`). System Qt6 is
  never bundled — documented as a runtime requirement in release notes.

## Architecture

### Directory layout
- `src/codec/` — schema-less wire value model + XML↔value codec (no Qt
  networking dependency; pure data/parsing)
- `src/comm/` — QXmpp-based connection, discovery, PubSub state
  subscription, RPC, and event handling (depends on `codec/`)
- `src/config/` — `QSettings`-backed app config and saved-accounts model
  (keychain-backed password storage)
- `src/plot/` — QML-exposed plotting item
- `src/shell/` — parses `module.command(arg1, arg2, ...)` shell syntax
- `qml/` — `Main.qml` (entry point) → `LoginWindow.qml` /
  `MainWindow.qml`, `qml/views/*View.qml` (one per rendered
  interface/page), `qml/widgets/` (shared generic components),
  `WidgetRegistry.qml` + `PluginLoader.qml` (plugin mechanism)
- `tests/` — Qt Test suite, mirrors `src/`'s subdirectory structure
  1:1; each test binary lists its own source deps explicitly in
  `tests/CMakeLists.txt` rather than linking a shared lib
- `fixtures/` — dummy `pyobs-core` module configs for live verification
- `examples/plugins/` — a worked example external QML widget plugin

### The wire protocol is schema-less by design
`codec::WireValue` (`src/codec/WireValue.h`) is a `std::variant`, not
`QVariant` — deliberately, because `dict`/dataclass-root values decode to
an **ordered** name/value list (`WireDict = std::vector<std::pair<QString,
WireValue>>`), and `QVariantMap` (a `QMap`) sorts by key, which would
silently reorder fields relative to the wire/declaration order that
`KeyValueCard.qml` (mirroring `pyobs-web-client`'s `KeyValueCard.vue`)
depends on for display order. `codec::InterfaceSchema` (from disco#info)
is the opposite: its `enums`/`commands` maps are looked up by name, never
iterated for display, so a plain sorted `QMap` is fine there.

### Generic-first rendering, opt-in custom widgets
The default path for any interface is fully generic: disco#info discovery
→ schema parse → PubSub state subscription → `KeyValueCard.qml` renders
whatever fields the schema says exist, no interface-specific code
required. A hand-written `qml/views/*View.qml` only exists where the
generic rendering doesn't earn its keep (e.g. `IRoof`'s
open/close/stop buttons). New interfaces should default to relying on the
generic path; only add a custom view when there's a concrete UX reason,
matching the precedent in `DEVELOPMENT.md`'s phase write-ups.

### Connection & subscription lifecycle (`src/comm/`)
- `XmppClient` (QML singleton-ish, exposed as `pyobs.polaris`'s `XmppClient`
  element) is a thin wrapper around `QXmppClient`, exposing `status`
  (`"disconnected"|"connecting"|"connected"|"error"`, matching
  `useXmpp.ts`'s `XmppStatus` exactly), the live `ModuleListModel`, and
  RPC/subscribe entry points.
- `StateSubscriptionManager` and `EventManager` are registered as
  `QXmppClientExtension`s on the one `QXmppClient` (via
  `addNewExtension`), which is how `QXmppPubSubManager`'s event dispatch
  finds them — they're owned by the client, not by `XmppClient`.
- PubSub state subscriptions are **ref-counted** per node
  (`pyobs:state:{module}:{Interface}:{version}`): multiple QML widgets
  watching the same interface on the same module share one server
  subscription; the last watcher's destruction triggers the real
  unsubscribe. Mirrors `useXmpp.ts`'s `subscribeState()` exactly,
  including retry-with-backoff-then-fetch-current-value.
- Module discovery is presence-driven: `XmppClient::handlePresence()`
  does a disco#info fetch only for modules not seen before; an
  already-known module's presence update just updates its state in
  place. `probeRosterPresence()` handles the case of connecting *after*
  modules are already online (live presence pushes are change-events
  only).
- RPC (`executeMethod`) has three overloads: fire-and-forget (Phase 5,
  every param sent as `null` — works because pyobs-core's commands
  declare all params optional), a callback-reporting overload (Phase 7,
  `{success, errorClass, errorMessage}`), and a real-parameter overload
  that looks up the command's `CommandSchema` from the module's
  disco#info and encodes each arg via `codec::fromQVariant`. Dispatch is
  always by method name alone — pyobs-core routes RPC without an
  interface qualifier.

### Plugin mechanism (`WidgetRegistry.qml` + `PluginLoader.qml`)
Two-step design (see `TODO.md`/`DEVELOPMENT.md`'s "Plugin mechanism"
sections for the full rationale):
1. `WidgetRegistry.qml` — an in-memory registry mapping either an
   interface name (`registerForInterface`) or a specific module's bare
   JID (`registerForModule`, supports `exclusive: true`) to a
   `{iconGlyph, label, component}` entry. Built-in widgets register
   themselves in `MainWindow.qml`'s `Component.onCompleted`. Every
   registered widget's `Component` is instantiated **eagerly at
   startup**, regardless of whether a matching module is connected yet —
   deliberately, to avoid a real, previously-caught race where filtering
   the registry itself let two independent per-module `Repeater`s
   initialize against different partial states.
2. `PluginLoader.qml` — loads external `*.qml` files from
   `AppSettings::pluginsDirectory` (non-recursive) at startup. Each
   plugin's root type must be a `QtObject` exposing exactly one of
   `targetInterface`/`targetJid`, plus `iconGlyph`, `label`, `widget`
   (Component), and optional `exclusive`. Plugins get the same
   `XmppClient` instance every built-in widget uses — no narrower API —
   but no sandboxing: this is for a user-supplied local plugins folder,
   not untrusted/network-sourced code. `examples/plugins/` has a worked
   example.

### QML entry point structure
`Main.qml`'s root is a plain `QtObject`, not `Item` — as the
`QQmlApplicationEngine` root it never gets a `QQuickWindow` scene graph,
and (on this project's Qt 6.10.2/KWin-Wayland dev setup) that silently
breaks visibility of `Window` children declared inside it. It owns one
`XmppClient` (must survive the login→main-window handoff) and toggles
`LoginWindow`/`MainWindow` visibility on `xmppClient.status`. Also note:
do not write `property var xmppClient: XmppClient { id: xmppClient }` —
sharing the property and id name causes the RHS to resolve to the
enclosing object's own not-yet-assigned property instead of the id,
binding silently to nothing.

### `qmltyperegistrar` include-path gotcha
`qmltyperegistrar` emits `#include <HeaderName.h>` using only the
basename of whatever header the `.cpp` that defines a `QML_ELEMENT` class
originally included — so **every directory containing a `QML_ELEMENT`
header must be added directly** to
`target_include_directories(polaris PRIVATE ...)` in
`CMakeLists.txt`. When adding a new `QML_ELEMENT` type in a new
subdirectory, add that directory there too, or the build fails with a
missing-header error that has nothing to do with the actual new code.

### Dependency policy
- **System Qt6** always — never vendored/bundled, even in release
  tarballs (documented as a runtime requirement instead).
- **qxmpp** and **QtKeychain**: vendored via CMake `FetchContent`, pinned
  in `cmake/Dependencies.cmake` (kept separate from the rest of
  `CMakeLists.txt` purely for CI cache-key scoping — see that file's own
  header comment). Not Conan dependencies: qxmpp's ConanCenter recipe
  would rebuild all of Qt from source, conflicting with the system-Qt
  requirement above.
- **Conan** is the dependency manager for everything else (currently
  nothing — `conanfile.txt` has no `[requires]` yet; future candidates
  like `cfitsio` will go there).
