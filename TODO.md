# pyobs-gui++ — todo

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
be contributed without recompiling `pyobs-gui++`, instead of every new
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

## Custom widget: `ITelescope` (MVP)

**Goal:** `qml/views/TelescopeView.qml`, ported from pyobs-gui's
`telescopewidget.py`, gated in the sidebar the same way as Roof/AutoFocus/
Acquisition/AutoGuiding (`MainWindow.qml`'s `hasTelescopeModule`,
`ModuleListModel::hasInterface("ITelescope")`). `ITelescope` itself is a
bare `IMotion` marker (confirmed against `pyobs.interfaces.ITelescope`
source — no state/commands of its own), so the baseline is identical to
`RoofView.qml`: `IMotion` state in a `KeyValueCard`, Init/Park/Stop via
`executeMethod`. Two more sections stack below it, each gated the same
`findInterface()` → `visible` → `refreshSubscriptions()` way every custom
widget here already does:

- **Move**: visible if the module implements `IPointingRaDec` and/or
  `IPointingAltAz`. A `ComboBox` (populated only with the coordinate types
  the module actually has, mirroring `comboMoveType`'s conditional
  population in `telescopewidget.py:150-159`) switches between an RA/Dec
  page (two decimal-degree `TextField`s — no sexagesimal hms/dms parsing,
  see below) and an Alt/Az page (two `SpinBox`es, alt −90..90 / az
  0..360). Both call `move_radec(ra, dec)` / `move_altaz(alt, az)` through
  the real-param `executeMethod(jid, name, QVariantList, callback)`
  overload already built for `IAutoFocus.auto_focus()` (Phase 8's
  `AutoFocusView.qml`/`VariantBridge`) — no new C++ needed, third/fourth
  call site.
- **Offsets**: visible if the module implements `IOffsetsRaDec` and/or
  `IOffsetsAltAz`, one sub-row per interface present (stacks vertically,
  matching `groupEquatorialOffsets`/`groupHorizontalOffsets` in the Python
  original). Each sub-row subscribes to that interface's state
  (`RaDecOffsetState`/`AltAzOffsetState`), shows the current offset in
  arcsec (same degrees→arcsec convention `AcquisitionView.qml`/
  `AutoGuidingView.qml` already use), and has a `SpinBox` + "Set"/"Reset to
  0" buttons calling `set_offsets_radec`/`set_offsets_altaz`.
- Move/offset controls stay disabled until `IMotion` state reaches the
  same "initialized" set `telescopewidget.py:287-300`'s `update_gui` uses
  (`SLEWING`/`TRACKING`/`IDLE`/`POSITIONED`).

New fixture: `fixtures/telescope.yaml`,
`class: pyobs.modules.telescope.DummyTelescope` — confirmed via source to
implement `ITelescope`/`IPointingRaDec`/`IPointingAltAz`/`IOffsetsRaDec`/
`IFocuser`/`IFilters`/`ITemperatures`, covering everything in this MVP's
scope for live verification **except `IOffsetsAltAz`**, which
`DummyTelescope` doesn't implement — that sub-row will ship without live
coverage unless a different/extended fixture is set up for it; flag this
explicitly in `DEVELOPMENT.md` rather than silently skip it.

**Deliberately out of scope for this pass** (each a real gap vs.
`telescopewidget.py`, not an oversight):

- No sexagesimal RA/Dec text parsing (`"12:34:56.7"` → degrees) — plain
  string parsing, not actually astropy-dependent, but skipped for this
  pass; decimal degrees only.
- No destination-coordinate preview (`_calc_dest_equatorial`/
  `_calc_dest_horizontal` in the Python original).
- No solar-frame pointing (`IPointingHGS`/`IPointingHelioprojective`, the
  3 heliographic/helioprojective pages + orbit elements).
- No SIMBAD/JPL Horizons/MPC coordinate lookups.
- No `CompassMoveWidget`-equivalent jog control.
- No Filter/Focus/Temperatures sidebar (`IFilters`/`IFocuser`/
  `ITemperatures` — new interfaces this project hasn't touched at all
  yet, though `DummyTelescope` does implement all three so a fixture
  exists for whenever this is picked up).

---

## Custom widget: `ICamera` (MVP — exposure control, no image display)

**Goal:** `qml/views/CameraView.qml`, ported from pyobs-gui's
`camerawidget.py` — exposure control and status for `ICamera` modules,
gated in the sidebar the same way as the other custom widgets
(`hasCameraModule`, `ModuleListModel::hasInterface("ICamera")`). This is
the largest widget planned so far: `ICamera` itself is `IData + IExposure`
(confirmed from source), but a real camera module combines it with up to
seven more capability interfaces the Python reference widget shows/hides
groups for individually. Split deliberately into this MVP (control only)
and a follow-up below (actual image display) — the image-display half
needs three genuinely new project-wide capabilities (VFS transport, FITS
decode, an image-viewer widget), each large enough to deserve its own
design pass rather than being smuggled into "the camera widget."

**Exposure status/control** (`IExposure`/`IData`/`IAbortable`):
- `IExposure` state (`ExposureStatus`: `IDLE`/`EXPOSING`/`READOUT`/
  `ERROR`, `progress`, `exposure_time_left`) drives a progress bar +
  status label, same subscribe-and-render shape as every other widget
  (`update_gui()`'s `IDLE`/`EXPOSING`/`READOUT` branching in the Python
  original).
- Expose button calls `IData.grab_data(broadcast)` — a single-shot RPC
  returning a filename string, no batch-exposure command exists on the
  wire. The "take N exposures" loop (`spinCount`) is therefore client-side
  only, same as the Python original: call `grab_data`, wait for it to
  return, decrement, repeat — not a single RPC with a count param.
- Abort (`IAbortable.abort()`, gated on the module actually implementing
  it) — same "abort sequence" vs. "abort exposure" label distinction
  `camerawidget.py::update_gui` already has (aborting mid-sequence zeroes
  the client-side counter instead of calling `abort()`, only the last
  exposure of a sequence actually sends the RPC).
- Broadcast checkbox, with the same confirm-dialog nicety
  (`broadcast_changed`'s "new images will not be processed/saved, are you
  sure?" warning when unchecking) — cheap to keep, real safety value.

**Capability-gated control groups**, each `visible` only if the module
implements the interface (mirrors `groupWindowing`/`groupBinning`/
`groupImageFormat`/`groupExpTime`/`groupGain`'s `setVisible()` calls in
`camerawidget.py::open`):
- `IImageType`: `ComboBox` of the `ImageType` enum (`BIAS`/`DARK`/
  `OBJECT`/`SKYFLAT`/`FOCUS`/`ACQUISITION`/`GUIDING`), `set_image_type()`.
  Keep the `BIAS` → zero-and-disable-exposure-time UX nicety
  (`image_type_changed`).
- `IExposureTime`: live-editable exposure-time control — directly reuses
  `AutoGuidingView.qml`'s existing "only overwritten by a server push if
  still showing the last value *this page* synced" idiom, not a new
  pattern.
- `IBinning`: `ComboBox` populated from capabilities (`f"{b.x}x{b.y}"`
  strings, same as the Python original), `set_binning(x, y)` parsed back
  out of the selected string.
- `IWindow`: four fields (left/top/width/height) bounded by capabilities'
  `full_frame_x/y/width/height` (adjusted by the current binning factor,
  matching `set_full_frame()`'s own division), plus a "Full Frame" reset
  button.
- `IGain`: two fields (gain, offset).

**Real fix vs. the reference, not a faithful port — confirmed by reading
the actual code, not assumed**: `camerawidget.py`'s own `_window_changed`
and `_gain_changed` handlers are dead stubs — `print("ok")` and nothing
else. The "modified" visual indicator
(`spinWindowLeft.init_modified(...).committed.connect(...)`) fires, but
**`set_window()`/`set_gain()`/`set_offset()` are never actually called
anywhere in that widget** — editing those fields in the real pyobs-gui
app does nothing on the wire. This client should actually wire the RPC
calls up correctly rather than reproduce that gap; noted here explicitly
so it isn't mistaken for an oversight if the behavior looks different
from the reference during review.

- `IImageFormat`: `ComboBox` populated from capabilities
  (`image_formats`), `set_image_format()`.

**Sidebar** (`add_to_sidebar` equivalent, capability-gated same as
`ITelescope`'s planned sidebar):
- `ICooling` — new, small, direct port of `coolingwidget.py`
  (checkbox + setpoint spin box + Apply → `set_cooling(enabled,
  setpoint)`, status label showing current setpoint/power or "OFF").
  Nothing shared with other widgets, worth building here.
- `IFilters`/`ITemperatures` — **the same components already deferred
  from the `ITelescope` MVP's own "out of scope" list** (see that item
  above) apply here too, unchanged. Building either widget first covers
  both; don't design these twice.
- `FitsHeadersWidget` (the client-editable OBJECT/USER/custom-header
  panel) — ignored for now, not planned. See the follow-up section below
  for why it's a materially different problem from the rest of this
  widget, if it comes back into scope later.

**Fixture**: `fixtures/camera.yaml`, `class:
pyobs.modules.camera.DummyCamera` (`BaseCamera, IWindow, IBinning,
ICooling, IGain, IImageFormat` — `BaseCamera` itself already provides
`ICamera`/`IExposureTime`/`IImageType`). Good coverage, but confirmed two
real gaps from reading the class declaration, not just the method list:
`abort()` exists on `BaseCamera` but its own docstring says "derived
class must implement `IAbortable` for this" — `DummyCamera` doesn't
declare it, so it won't appear in disco#info and the Abort button's
gating won't be live-testable against this fixture. `IFilters` is
likewise not declared. Same class of gap as `ITelescope`'s
`IOffsetsAltAz` note — flag it, don't silently skip verifying what can be
verified.

---

## `ITelescope` follow-up: libnova, destination preview, solar-frame pointing

**Goal:** unblock the coordinate-transform-dependent items deferred from
the `ITelescope` MVP above, in one follow-up PR rather than piecemeal,
since destination preview and solar-frame pointing both need the same
observer-location + Alt/Az↔RA/Dec transform plumbing.

- Vendor **libnova** via CMake `FetchContent` (pinned git tag, built
  against system libs) — same treatment as `qxmpp`/`qtkeychain` (see
  `DEVELOPMENT.md`'s Phase 0 summary), not a Conan dependency. Chosen over
  ERFA/NOVAS/SPICE: it's the library KStars/INDI already use for this
  exact problem (telescope-pointing Alt/Az↔RA/Dec, sidereal time,
  VSOP87 solar/planetary positions) rather than a general-purpose
  data-reduction toolkit (ERFA) or heavier ephemeris/catalog system
  (NOVAS, SPICE — SPICE also needs downloaded kernel files, hundreds of
  MB, only worth it if JPL Horizons' network lookup itself needs
  replacing).
- Destination-coordinate preview: show the Alt/Az a typed-in RA/Dec target
  corresponds to (and vice versa) before committing to Move, using the
  logged-in observer's location — ports `_calc_dest_equatorial`/
  `_calc_dest_horizontal`.
- Solar-frame pointing: `IPointingHGS`/`IPointingHelioprojective` pages,
  needs libnova's solar position (VSOP87) on top of the coordinate
  transform.
- Still explicitly out of scope even after this: SIMBAD/JPL Horizons/MPC
  lookups (network dependency, unrelated to libnova), the compass widget,
  the Filter/Focus/Temperatures sidebar.

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
