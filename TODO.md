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

## Custom widget: `IMode`

**Goal:** `qml/views/ModeView.qml`, ported from pyobs-gui's
`modewidget.py` — one row per mode "group" a module exposes (each group:
current mode + a picker to change it), gated in the sidebar the same way
as the other custom widgets (`MainWindow.qml`'s `hasModeModule`,
`ModuleListModel::hasInterface("IMode")`).

- `IMode`'s capabilities (`ModeCapabilities.modes: dict[str, list[str]]`,
  group name → available mode options) are **static**, fetched once via
  disco#info — this project already stores per-interface capabilities on
  `ModuleInfo::capabilities` (Phase 2/4), but doesn't expose them
  generically to QML yet, only one specific field (`IModule`'s `version`,
  via `VersionRole`, for the Status page). Needs a new narrowly-scoped
  role on `ModuleListModel`, e.g. `ModeGroupsRole`: a `QVariantList` of
  `{"group": ..., "modes": [...]}` entries decoded from
  `capabilities["IMode"]`, empty list if the module hasn't reported
  `IMode` capabilities — same "add the role once something actually
  renders it" discipline `ModuleListModel.h`'s own header comment already
  states, not a generic capabilities-dump role.
- **Unblocked 2026-07-08**: the upstream change landed
  (`pyobs-core@3a0a70c3`, `develop`, pushed to `origin/develop`) -
  `IMode.set_mode(self, mode: str, group: str = "", ...)` now takes the
  **group name itself**, confirmed directly against source again after
  landing (not just trusting the earlier plan): `DummyMode.set_mode`
  defaults `group=""` to `next(iter(self._mode_options.keys()))` and
  raises `ValueError` for an unknown group name, exactly as originally
  described before the false start recorded below. `ModeGroupsRole`'s
  `QVariantList` doesn't need to preserve wire order for *correctness* -
  a group's position in that list is never sent anywhere, only its name
  is. (A stable *display* order is still nice to have, just not
  load-bearing.)
- Groups are tracked by name throughout, with nothing to resolve at the
  RPC call site either - `ModeView.qml`'s per-group loop, current-mode
  lookup (`ModeState.modes` is itself keyed by name), and the `set_mode`
  call all use the same group name string directly. No index anywhere in
  this widget.
- **False start, kept for the record**: this doc briefly (2026-07-08)
  claimed this same string-`group` shape already existed upstream before
  it actually did, got caught by re-verifying against source, and the
  item was marked blocked pending the user landing the real change above
  - see git history on this file for the full note if it matters later.
- Live current mode per group comes from `IMode` state
  (`ModeState.modes: dict[str, str]`, group name → current mode),
  subscribed the same way every other widget subscribes state, read via
  the existing `fieldOf()` pattern.
- Per-group UI: current-mode `ComboBox` (options = that group's static
  mode list from capabilities), following `AutoGuidingView.qml`'s
  live-editable-`SpinBox` idiom — only overwritten by a fresh state push
  if it still shows the last value *this page itself* synced from the
  server (so an in-progress user pick isn't clobbered), sends
  `set_mode(mode, group)` on `activated` via the real-param
  `executeMethod` overload (built for `IAutoFocus`, reused since) - both
  params are strings now, this project's first real RPC call with more
  than one string-typed param, worth confirming
  `VariantBridge::fromQVariant` round-trips `WireType::String` correctly
  for both against a live fixture before assuming it "just works" from
  reading the code, matching this project's verify-against-the-wire
  discipline.
- `ComboBox`es disabled until `IMotion` state reaches the same
  "initialized" set (`SLEWING`/`TRACKING`/`IDLE`/`POSITIONED`) every other
  motion-gated widget already checks (`modewidget.py::update_gui`'s
  `initialized` check) — subscribe `IMotion` state and render it via
  `KeyValueCard`, same as `RoofView.qml`.

New fixture: `fixtures/mode.yaml`, `class: pyobs.modules.utils.DummyMode`
— confirmed via source to implement `IMode`/`IMotion` with three real
groups out of the box ("Size", "Speed", "Movement", each with its own
option list), and `set_mode` genuinely cycles `IMotion` through
`SLEWING`→`POSITIONED` (a 3s delay) — good live coverage for both the
capabilities→`ComboBox` wiring and the motion-gating behavior, no fixture
gaps this time.

**Deliberately out of scope**: `ModeChangedEvent` handling —
`modewidget.py`'s own comment calls it "backwards compat with modules
that still send `ModeChangedEvent`", with `IMode` state subscription as
the actual primary path already; this project subscribes state
everywhere else already and has no reason to special-case one legacy
event fallback here.

---

## Real parameterized command execution in Shell

**Moved down one slot from its original "simplest" position**: its plan
changed (see below) in a way that adds real scope - a hand-rolled parser
and a new-to-this-project autocomplete popup UI, not just wiring
existing parts together the way `IMode` does. Re-sort, per this doc's
own intro, rather than leave a now-inaccurate complexity ranking.

**Plan changed, on direct instruction**: not a port of `pyobs-web-client`'s
`ShellView.vue` (per-`WireType` parameter widgets: bool/enum/number/string
fields you fill in, then click Execute) anymore - instead, port
pyobs-gui's actual `ShellWidget`/`CommandInputWidget`/
`pyobs.utils.shellcommand.ShellCommand`: a single-line command prompt
(`module.command(arg1, arg2, ...)` syntax, typed and executed like a
shell, not clicked through module/method pickers) with autocomplete and
command history. `ShellView.qml`'s current module-picker-then-method-
picker-then-click UI is replaced entirely, not extended.

**Ported from the Python reference, confirmed against its actual
source (not assumed):**
- `CommandInputWidget` (a `QLineEdit` subclass): Enter executes and
  clears the field, Up/Down cycle a local command history array (not
  persisted across sessions) - `commandExecuted.emit(cmd)` on Enter maps
  to a QML `TextField`'s `Keys.onReturnPressed`/`Keys.onUpPressed`/
  `Keys.onDownPressed`, no C++ needed for this part.
- `ShellCommand.parse()` (`pyobs/utils/shellcommand.py`, read directly,
  not inferred): a small hand-rolled tokenizer-based grammar -
  `module.command(` then zero or more positional args, each either a
  `NUMBER` (optional unary `-`) or a quoted `STRING`, comma-separated,
  closing `)`. **Positional only** - no named params, no bool/enum
  literals as a distinct token type (a bare `true`/`ACQUISITION` would
  need to arrive as a quoted string and get coerced against the target
  `FieldSchema.type` at encode time, same as every other real-param path
  in this project already does via `VariantBridge::fromQVariant`).
- Autocomplete: pyobs-gui's `CommandModel` (a `QAbstractTableModel` feeding
  a `QCompleter` in `PopupCompletion` mode) enumerates every
  `module.command` pair across all connected modules/interfaces
  (deduped by name - same "first interface declaring a command wins"
  convention this project's own dispatch-by-name-alone already uses,
  confirmed again here) and shows a popup table of name / param
  signature / doc while typing.

**Not `QCompleter` - checked, and it doesn't fit this project**:
`QCompleter` lives in `QtWidgets` (`Q_WIDGETS_EXPORT`, confirmed directly
against the installed Qt6 headers), not exposed to QML at all, and this
project links only `Qt6::Quick`/`Qt6::Xml`/`Qt6::Network` today - no
`Qt6::Widgets` anywhere in `CMakeLists.txt`. Pulling in the whole
Widgets module for one non-visual utility class would be a real,
architecturally inconsistent new dependency for a project that's
otherwise pure QML end to end. `ComboBox { editable: true }` (the
closest built-in QML equivalent) doesn't fit either - it only filters a
flat list of full strings, not a live multi-column name/signature popup.
Build this as a plain QML-native popup instead: a `Popup` anchored under
the command `TextField`, containing a `ListView` bound to a filtered JS
array recomputed on `TextField.onTextChanged` - the same "plain array +
`filter()`" idiom `LogsView.qml`/`EventsView.qml` already use repeatedly,
not a new pattern, and no new Qt module.

**Confirmed gap vs. the Python reference, not fixable from the wire
alone**: pyobs-gui's completion popup's third column is the command's
Python docstring first line (`inspect.getmembers`/`member.__doc__`) -
this project's `codec::CommandSchema`/`FieldSchema` (checked directly:
`{name, type, unit}`, no doc/description field anywhere in
`InterfaceSchema.h`) has no equivalent on the wire at all. disco#info
was never going to carry Python docstrings - the completion popup here
can only ever show `module.command(param: type, ...)` (built from
`FieldSchema.name`/`.type`, with `WireType::Kind::Optional` distinguishing
required from optional params - already representable, just not yet
QML-exposed), never a description. Not a bug to chase, a real ceiling.

**Also confirmed**: `ShellCommand.execute()`'s `proxy.execute(command,
*params)` is just `pyobs.comm.proxy.Proxy`'s own generic "call this
method by name with positional args" convenience wrapper (read directly
- `Proxy.execute()` forwards to the same per-method RPC dispatch every
other proxy call already uses), not a distinct wire-level "generic
execute" RPC. Confirms this doesn't need new C++ - the existing
real-param `executeMethod(jid, methodName, QVariantList, callback)`
overload (built for `IAutoFocus`, reused by `IMode`/`ITelescope`'s plans)
is the correct target, once parsed args are matched positionally against
the command's `CommandSchema.params` and encoded via
`VariantBridge::fromQVariant` per param.

**Still needed, carried over from the original plan** (this is *more*
load-bearing now, not less): `ModuleListModel`'s `commands` role only
exposes `{interface, name, paramCount}` (Phase 5) - needs full
`CommandSchema`s (param name/type/optionality) both to render meaningful
autocomplete signatures and to know each positional arg's target
`WireType` for encoding.

**Result log**: keep `ShellView.qml`'s existing scrolling, green/success-
red/error-colored log rendering below the prompt - already matches
`ShellCommandResponse.color` (`lime`/`red`) exactly, nothing to change
there.

---

## Custom widget: `IWeather`

**Goal:** `qml/views/WeatherView.qml`, one tile per sensor a connected
weather module reports, gated in the sidebar the same way as the other
custom widgets (`hasWeatherModule`, `ModuleListModel::hasInterface
("IWeather")`).

**Read this before porting `weatherwidget.py` literally**: that widget
targets an *older* `IWeather` shape that no longer exists in the current
pyobs-core (the installed venv's `IWeather.py` was checked directly, not
assumed from the Python widget) — `get_current_weather()` (a plain RPC,
polled every 10s, returning a loose `dict` with arbitrary string sensor
keys and a per-sensor `good` flag) is gone entirely. The current
interface is `state = WeatherState{good: bool, readings:
list[WeatherSensorReading{sensor: WeatherSensors, value: float, unit:
str, time}]}` — a proper dataclass pushed via normal state publication.
This is a straightforward win: no RPC polling needed at all, just a plain
state subscription like every other widget already does, actually
simpler than the reference implementation rather than harder.

- `WeatherSensors` (`pyobs.utils.enums.WeatherSensors`) is a fixed
  11-member enum: `TIME`, `TEMPERATURE`, `HUMIDITY`, `PRESSURE`,
  `WINDDIR`, `WINDSPEED`, `RAIN`, `SKYTEMP`, `DEWPOINT`, `PARTICLES`,
  `SKYMAG`. `readings` only ever contains entries for sensors the station
  actually has (module-dependent, not fixed) — render one tile per
  reading *present*, not a fixed 11-tile grid, same dynamic-count idiom
  `TemperaturesWidget`'s Python original already established (see
  `DEV_telescopewidget_layout.md`'s note on it) and this project's own
  dynamic-row precedents elsewhere.
- **Two real divergences from `weatherwidget.py`'s `AVERAGE_SENSOR_FIELDS`
  display map, confirmed from source, not assumptions**: `sunalt` (sun
  altitude) existed in the old widget's field list but has **no
  equivalent in the current `WeatherSensors` enum at all** — drop it, not
  a gap to fill. `SKYMAG` (sky brightness, mag/arcsec², per `Weather`
  module's own `FITS_HEADERS` comment) is **new** and has no display
  entry in the old widget to port — needs a fresh label/unit, not copied
  from anywhere.
- **Real behavior change, not a missing feature**: the old widget colored
  each sensor tile red/green from a per-sensor `cur[f]["good"]` flag that
  **no longer exists** on `WeatherSensorReading` — the current schema
  only has one *overall* `WeatherState.good: bool`. This widget colors
  the whole tile group (or a single "Weather OK"/"Weather BAD" banner)
  from that one flag; there is no wire data left to color individual
  sensors independently, so don't try to preserve that part of the
  original's behavior.
- Sensor labels/units: port `AVERAGE_SENSOR_FIELDS`'s label text (minus
  `sunalt`, plus a new `SKYMAG` entry) - units can be read directly off
  the wire from each `WeatherSensorReading.unit` field instead of a
  separate hardcoded map, since the module already sends it (`Weather`'s
  own `SENSOR_UNITS` proves the unit is module-owned, not a client-side
  constant) - simpler than the Python original's own hardcoded
  `AVERAGE_SENSOR_FIELDS` unit strings.

**Fixture gap - flag this clearly before starting**: unlike every
previous custom widget, there is **no `Dummy*` module implementing
`IWeather`** anywhere in pyobs-core. The only implementation
(`pyobs.modules.weather.Weather`) is a real HTTP client (`WeatherApi
(url)`) for the separate `pyobs-weather` service - it has no
self-contained simulated-data mode, `_get_readings()` always sources from
a live `_api.get_current_status()` call. Live verification would need
either standing up a throwaway fake HTTP server that mimics
`pyobs-weather`'s response shape (real extra infra, not just a fixture
YAML), or accepting this widget ships without the "verified live" bar
this project holds everything else to, covered only by schema-level
decode tests. Worth resolving *before* implementation starts, not
discovering mid-PR - this may be a reason to write a minimal mock
`pyobs-weather` HTTP responder as part of this item's own scope, rather
than skip live verification entirely.

**Deliberately out of scope**: Start/Stop controls, even though
`IWeather` now extends `IStartStop` (`start`/`stop`/`is_running`, toggling
whether bad weather blocks observations) and formally supports them -
`weatherwidget.py` never had them (this capability was added to the
interface after that widget was written), and the ask here was a page
that *shows* the weather, not one that controls the module. Worth a
follow-up once this ships.

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
