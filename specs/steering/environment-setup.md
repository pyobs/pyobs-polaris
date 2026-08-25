# Environment setup (fresh clone / new machine)

Standing contributor-guidance doc — keep it up to date as the setup changes, don't let it drift like a one-off design note would.


## Prerequisites

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
  see `specs/design/configuration-file-and-saved-accounts.md`):
  ```bash
  sudo apt-get install -y libsecret-1-dev pkg-config
  ```
- **CMake 3.21+** and a **C++20** compiler.
- **Conan 2.x.** Most modern distros block a plain `pip install` for the
  system Python (PEP 668, "externally managed environment") — install via
  `pipx install conan` instead, then run `conan profile detect --force`
  once.
- `patchelf` is only needed for cutting a release (see
  `specs/steering/releases.md`), not for day-to-day building.
- **GCC 15.2.0 gotcha**: on a machine where `conan profile detect` picked
  gcc-15 (e.g. Ubuntu 26.04), `conan install . --build=missing` can fail
  building `cfitsio` with `internal compiler error: in fold_convert_loc,
  at fold-const.cc:2665` — a genuine GCC ICE optimizing `Do_Deref` in
  cfitsio 4.6.3's bison-generated `eval_y.c` at default Release (`-O3`),
  not a bug in this project's code. Fix by scoping a lower optimization
  level to just that package, added to `~/.conan2/profiles/default`'s
  `[conf]` section (or pass ad hoc via `-c`):
  ```
  [conf]
  cfitsio/*:tools.build:cflags=['-O1']
  ```

## Build

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

## Live-verification test fixtures

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
   visibility on a real compositor — see
   `specs/design/phase-7-5-app-shell-login-and-sidebar-navigation.md` for
   why that matters.

## AT-SPI-driven live verification (real clicks, not just screenshots)

Every prior phase's write-up notes the same gap: no `xdotool`/`wmctrl`/
`ydotool`/`wtype`/`dotool` in this dev environment, so a live-running GUI
could only be screenshotted (`spectacle -b -n -a -o <path>`) on whatever
page happened to already be showing — never actually driven. That gap is
now closed for anything with a real accessible action, via the AT-SPI
(Linux accessibility) bus rather than any input-injection tool:

**`scripts/screenshot_page.py`** packages the whole flow below (start
fixtures/polaris if needed, connect, kick stale zombie sessions, click
to a named sidebar page, optionally `--click` further visible buttons,
screenshot) into one reusable, idempotent command - see its own
docstring for usage. Written after re-deriving these exact steps by
hand across two separate sessions; reach for it instead of re-deriving
them a third time. The steps themselves, for anything the script
doesn't cover:

1. Launch `polaris` with `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
   QT_ACCESSIBILITY=1` in its environment — without this, Qt only
   registers the app on the AT-SPI bus lazily (once a real screen reader
   client asks), and it never shows up for a script to find.
2. Use `python3` + `gi.repository.Atspi` (`gi.require_version('Atspi',
   '2.0')`, package `gir1.2-atspi-2.0` — already present on this machine)
   to walk `Atspi.get_desktop(0)`'s children for the app named
   `"Polaris"`, find the target node by role/name, and call
   `node.get_action_iface().do_action(i)` for whichever action is
   `"Press"`/`"click"`/`"activate"`. This invokes the control's real Qt
   slot directly (`AbstractButton::clicked()` etc.) — it is not a
   simulated OS-level input event, so it works identically under
   Wayland/X11 and doesn't depend on window manager focus at all.
3. **Stock `QtQuick.Controls` types work with zero code changes** — a
   `Button` already exposes a `"Press"` action out of the box (proven by
   driving the login window's "Connect" button this way). **Any
   `ItemDelegate` doesn't**, and the failure mode is silent, not an
   error: it gets `Accessible.role` `ListItem` by default and the AT-SPI
   bridge simply doesn't synthesize a press action for that role -
   `get_n_actions()` returns `0`. First caught on `MainWindow.qml`'s
   `SidebarItem` (used standalone, not inside a `ListView`); initially
   assumed an `ItemDelegate` used as a real `ListView`'s delegate (a
   genuine list-selection view, e.g. `SettingsView.qml`'s VFS endpoint
   list) would be spared this since it has a real selection model behind
   it - it isn't, `get_n_actions()` returns `0` there too. Fix, in both
   cases: declare `Accessible.role: Accessible.Button` and
   `Accessible.onPressAction: <item>.clicked()` explicitly on the
   component. This is a real accessibility improvement in its own right
   (screen readers get the same benefit), not merely a testing hack -
   worth doing for any future `ItemDelegate`, `ListView`-hosted or not.
4. **Don't reach for `Atspi.generate_keyboard_event`/`generate_mouse_event`**
   (raw XTEST-style synthetic input) as a fallback for elements lacking a
   proper action — both were tried and both are unreliable here:
   `generate_mouse_event` silently no-ops under this Wayland session (KWin
   doesn't accept fake XTEST pointer input without an interactive
   permission grant), and `generate_keyboard_event` *does* land somewhere,
   but not reliably where focus was just set via AT-SPI's own `SetFocus`
   action — one attempt landed a stray `Return` in the hidden login
   window's pre-filled password field and forced a real disconnect
   (recovered cleanly by re-pressing "Connect" the proper way, no data
   lost, but a good demonstration of why this path isn't trustworthy for
   unattended use).
5. Combine with a screenshot (`spectacle -b -n -a -o <path>`, still the
   only working capture mechanism) after each `do_action` press for actual
   pixel confirmation, not just "the click didn't error."

This is how every module page's post-redesign layout (Camera, Telescope,
AutoFocus, Acquisition, AutoGuiding, Mode, Weather, plus Status/Settings)
got genuinely screenshot-verified end to end in one sitting, rather than
relying on "whichever page happened to be showing" luck — see the
`CameraView.qml` layout pass entry below for the redesign this validated
(`specs/design/cameraview-layout-pass-material-to-fusion.md`).

