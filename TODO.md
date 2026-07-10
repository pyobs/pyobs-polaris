# pyobs-polaris — todo

What's planned next. See `DEVELOPMENT.md` for how to build, and for the
design decisions/gotchas behind everything already done (Phases 0–7.5).

Each item below should be its own PR/commit, buildable and runnable on its
own before moving to the next, and verified against a live ejabberd server
and real pyobs modules — not just unit tests. Never assume the schema
shape from memory of the Python/TS side; verify against source and the
real wire protocol. If an item's design turns out to need something not
anticipated here, fix this doc, don't just fix the code.

Ordered by estimated implementation complexity, simplest first — not by
priority. Re-sort if a "simple" item turns out to need more than
expected, or vice versa; this ordering is a judgment call made once, not
a guarantee.

---

## Plugin mechanism for custom module widgets

**Goal:** let a widget for a given interface (or a given specific module)
be contributed without recompiling `polaris`, instead of every new
widget requiring a hand-edited PR against this repo (as `IWeather`/
`ITelescope`/`ICamera` below all are). Motivated by pyobs's own
extensibility — modules can expose arbitrary custom interfaces beyond the
built-ins this project ships views for, and those can't all be maintained
in-tree.

**Steps 1 and 2 are done** (see `DEVELOPMENT.md`'s "Plugin mechanism,
step 1" and "step 2" write-ups) - `WidgetRegistry.qml` +
`MainWindow.qml`'s generic Repeaters, and `PluginLoader.qml` +
`AppSettings::pluginsDirectory`/`pluginFiles()`. A worked, real,
live-verified example plugin lives at
`examples/plugins/TelescopeQuickView.qml`. Only step 3 remains, and it's
explicitly speculative - re-sort or drop this item once it's clear
whether a concrete need for it ever actually comes up.

3. **Native C++ plugin loading — speculative, don't start without a
   concrete need.** Real Qt QML plugins (own `qmldir` + shared library,
   loaded via `QQmlEngine`'s import path) for the rare case a QML-only
   plugin can't cover — e.g. a new `QQuickPaintedItem`-style widget akin
   to `PlotItem.h`. Reopens ABI/Qt-version matching between host and
   plugin binary, a real new class of build/deployment problem this
   project has avoided so far (everything today is one statically-linked
   binary — no `QPluginLoader`/`dlopen` anywhere). Unlike steps 1–2, the
   general "let third parties contribute widgets" ask alone doesn't
   justify this; only build it once a specific widget actually needs
   native code a QML plugin can't provide.

**Deliberately out of scope**: any plugin marketplace/discovery UI,
hot-reloading native plugins, or a permission/sandboxing model beyond
"it's a local file/library the user placed there themselves."

---

## Solar-frame pointing (`IPointingHGS`/`IPointingHelioprojective`) — blocked

**Split out of the original "`ITelescope` follow-up: libnova, destination
preview, solar-frame pointing" item** once libnova vendoring + the
destination-coordinate preview shipped (see `DEVELOPMENT.md`) - this piece
alone is blocked, not merely deferred, so it gets its own entry rather
than silently vanishing from the backlog.

**Why it's blocked:** zero live-testable coverage anywhere in the pyobs
ecosystem, confirmed by reading source across every sibling repo, not
assumed. `IPointingHGS` has never been implemented by any module,
anywhere - the interface exists purely speculatively. `IPointingHelioprojective`
is implemented by exactly one module, `SolarTelescope`
(`pyobs-iagvt/pyobs_iagvt/modules/solartelescope.py`) - hardware-backed (a
real siderostat device), not usable as a dev fixture, and in a different
sibling repo from pyobs-core. `DummyTelescope` implements neither. Unlike
every other partial-coverage caveat already documented in this project
(`ITelescope`'s own `IOffsetsAltAz`, `ICamera`'s `IAbortable`/`IFilters` -
each a single sub-row shipped schema-verified-only), this would mean
shipping two full interfaces' worth of Move UI with **no way to verify
any of it** against a real module, ever, in this dev environment - judged
too large a gap to accept silently (user-confirmed decision, not a
unilateral call).

**What would unblock it** (either is sufficient):
- A new lightweight mock module added to pyobs-core implementing
  `IPointingHGS` and/or `IPointingHelioprojective` (mirrors how
  `pyobs.modules.weather.MockWeather` unblocked `IWeather` - see
  `DEVELOPMENT.md`), maintained upstream, not client-side.
- Dev access to a real `SolarTelescope` deployment/hardware environment.

**If/when unblocked**, the actual widget work: `TelescopeView.qml`'s Move
`ComboBox` gains "HGS"/"Helioprojective" entries alongside the existing
RA/Dec and Alt/Az pages (visible only if the module implements the
relevant interface, same capability-gating shape every other Move option
already uses); `move_hgs_lon_lat(lon, lat)`/`move_helioprojective(theta_x,
theta_y)` (both plain degrees on the wire - confirmed from source, not the
arcsec the legacy Python widget's spin boxes happened to display) via the
same real-param `executeMethod` call sites as `move_radec`/`move_altaz`.
Full destination-coordinate transform to/from these frames (the legacy
`telescopewidget.py`'s HGS↔Helioprojective conversion, via `sunpy`'s
`Heliographic Stonyhurst`/`Helioprojective` frame machinery) is out of
scope even then unless something concrete needs it - libnova has no
built-in support for either frame, that math would need to be ported or a
new dependency added, and the legacy widget's own version of this
specific piece (`_calc_dest_heliographic_stonyhurst`/
`_calc_dest_helioprojective_radial`) turned out to be an incomplete
stub when actually read (just shows the Sun's current position, doesn't
convert the typed value) - not a trustworthy reference to port from
as-is.

**Still explicitly out of scope even once unblocked**: SIMBAD/JPL
Horizons/MPC lookups (network dependency, unrelated to any of this), the
compass widget, the Filter/Focus/Temperatures sidebar.

---

## `ICamera` follow-up: image display, VFS

**Goal:** the actual image-preview half of `camerawidget.py`
(`DataDisplayWidget`) — deliberately split out of the MVP above because
each piece needs a genuinely new project-wide capability, not a widget-
local addition. `FitsHeadersWidget` (the client-editable header-injection
sidebar panel) is intentionally **not** included in this follow-up either
— ignored for now, on direct instruction, not merely deferred alongside
the rest of this list. Its own bullet below is kept only as a record of
why it's a materially different problem (the GUI would have to answer an
incoming RPC, not just issue outgoing ones) whenever it does come back
into scope.

- **VFS (virtual file system) client transport.** `grab_data()` returns
  only a filename reference — `DataDisplayWidget._on_new_data` fetches
  the actual pixels via `self.vfs.read_fits(event.filename)`.
  `pyobs.vfs` is a pluggable multi-backend abstraction (confirmed via
  source: `file`/`http`/`sftp`/`smb`/`ssh`/`archive`/`mem`/`temp`/
  `buffered` backends all exist) configured server-side — which backend
  a real deployment actually uses isn't discoverable from disco#info the
  way everything else in this project has been so far, so this needs its
  own design pass (probably starting with just the `http` backend, the
  most broadly deployable one, not all of them at once).
- **FITS decode.** This project's own Phase 0 notes already anticipated
  `cfitsio` as a future Conan dependency for exactly this reason (see
  `DEVELOPMENT.md`) — nothing else in this project has needed it yet.
- **An actual astronomical image display widget** (stretch/zoom/pan,
  `QFitsWidget`'s equivalent) — a genuinely new, non-trivial UI
  component, not an extension of `PlotItem` (which draws scatter/line
  plots of numeric points, not 2D pixel data).
- **`FitsHeadersWidget` — ignored for now (see intro above), record only:**
  it inverts this project's client-only role. `get_fits_headers()` is
  called *on the GUI* by the exposing module (via `IFitsHeaderBefore`-
  style callback registration) to collect user-entered OBJECT/USER/
  custom headers *before* an exposure completes - meaning the GUI itself
  has to answer an incoming RPC, not just issue outgoing ones. Every
  single thing this client does today is request/subscribe-only;
  becoming an RPC responder is a first, and would deserve its own design
  discussion whenever/if this comes back into scope.
- `DataDisplayWidget`'s `ISpectrograph` branch (matplotlib spectrum plot
  instead of image display) is a different device family entirely -
  explicitly out of scope here, worth a separate widget/TODO item of its
  own if ever needed, not folded into `ICamera`'s.

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
