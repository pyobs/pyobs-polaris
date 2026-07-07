# pyobs-gui++ — todo

What's planned next. See `DEVELOPMENT.md` for how to build, and for the
design decisions/gotchas behind everything already done (Phases 0–7.5).

Each item below should be its own PR/commit, buildable and runnable on its
own before moving to the next, and verified against a live ejabberd server
and real pyobs modules — not just unit tests. Never assume the schema
shape from memory of the Python/TS side; verify against source and the
real wire protocol. If an item's design turns out to need something not
anticipated here, fix this doc, don't just fix the code.

---

## New page: all incoming events

**Goal:** `qml/views/EventsView.qml`, ported from pyobs-gui's
`eventswidget.py` — a page showing every incoming event across all
connected modules, not just `LogEvent` (which `LogsView.qml` already
covers). Always visible in the sidebar's TOOLS group alongside Shell/Logs
(not interface-gated — events aren't module-type-specific, unlike Roof/
Auto Focus/Acquisition/Auto Guiding).

- `EventLogModel` (Phase 6) already logs **every** event centrally, not
  just `LogEvent` — `LogsView.qml`/`LogFooter.qml` just happen to filter
  down to one type via `entriesOfType("LogEvent")`. This page needs the
  same thing but unfiltered, minus `LogEvent` itself (excluded the same
  way pyobs-gui's own `eventswidget.py::_handle_event` explicitly ignores
  it — Logs/the footer already cover it, and it fires often enough to
  drown out everything else in a generic view). Needs one small addition:
  `EventLogModel::entries()`, a `Q_INVOKABLE` returning every event in the
  same `{type, module, timestamp, uuid, data}` shape `entriesOfType()`
  already produces, just without the type filter — `EventsView.qml`'s own
  `refresh()` then does `.filter(e => e.type !== "LogEvent")` client-side,
  same recompute-on-`rowsInserted`/`modelReset` pattern `LogsView.qml`
  already uses.
- Columns: Time, Module, Type, Data — matches `eventswidget.py`'s
  `tableEvents` (Time/Sender/Event/Data). `data` is a `QVariantMap`
  crossing the C++/QML boundary the same way `LogEvent`'s `data.level`/
  `data.message` already do in `LogsView.qml` — render it via
  `JSON.stringify(modelData.data)` rather than iterating it, matching
  `DEVELOPMENT.md`'s "Roof state display bug" finding that `JSON.stringify`
  is safe for values crossing this boundary (unlike `Array.isArray()`).
- Per-module filter `ComboBox`, same `knownModules`-from-filtered-list
  pattern as `LogsView.qml`. Also add a per-type filter `ComboBox`
  (`knownTypes`, same computed-property idiom) — a generic "all events"
  view has far more type variety than the Logs page's single-type view,
  so a type filter earns its place here in a way it wouldn't have there.
- Reuses `xmppClient.events.clear()` (already exists) for the Clear
  button — shared with `LogsView.qml`'s own Clear, since both pages read
  the same underlying model; already-existing shared-model behavior
  (see `LogFooter.qml`'s own note on this), not a new risk.
- Sidebar: new `SidebarItem` in `MainWindow.qml`'s TOOLS group, after
  Logs — shifts `StackLayout` indices for Roof/Auto Focus/Acquisition/
  Auto Guiding from 3–6 to 4–7, including their `onHasXModuleChanged`
  fallback-to-Status `currentIndex` checks.

**Deliberately out of scope**: `eventswidget.py`'s "send a synthetic
event" feature (`comboEvent` + `SendEventDialog`, reflecting over
`pyobs.events.__dict__` to build a form and publish an event as if from a
module). This project's event *discovery* is per-module via disco#info
(`EventSchema`), not a static Python module listing — there's no
equivalent enumeration of "every possible event type" to build that combo
from, and the actual ask here was a page that *shows* incoming events, not
one that sends them.

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
- **Wire-order gotcha, worth flagging explicitly before building this**:
  `set_mode(mode: str, group: int = 0)`'s `group` param is a **positional
  index** into the capabilities dict's key order (confirmed against both
  `modewidget.py::set_mode` — `self._mode_groups = list(caps.modes.keys())`
  then `proxy.set_mode(new_value, group_index)` — and the reference
  `DummyMode` module's own `_group_name(group)`, `list(self._mode_options
  .keys())[group]`), not the group name itself. `codec::WireValue`'s dict
  alternative already preserves wire order for exactly this class of
  reason (Phase 1.5) — `ModeGroupsRole`'s `QVariantList` must preserve
  that same order so a group's position always matches what the module
  expects.
- **Track groups by name internally, resolve to index only at the RPC
  call site** — not by threading the raw position through the UI/delegate
  code. `ModeView.qml`'s per-group loop, current-mode lookup
  (`ModeState.modes` is itself keyed by name, not position), etc. should
  all key off the group *name*, matching how the wire actually identifies
  a group everywhere except this one param. Only the `executeMethod`
  call itself does `groupNames.indexOf(name)` against the same
  order-preserved `ModeGroupsRole` list to get the position `set_mode`
  needs — this can't avoid depending on wire order (the protocol itself
  is positional here, not something this client controls), but it
  contains that fragility to one call site instead of spreading "position
  is meaning" through bindings.
- Live current mode per group comes from `IMode` state
  (`ModeState.modes: dict[str, str]`, group name → current mode),
  subscribed the same way every other widget subscribes state, read via
  the existing `fieldOf()` pattern.
- Per-group UI: current-mode `ComboBox` (options = that group's static
  mode list from capabilities), following `AutoGuidingView.qml`'s
  live-editable-`SpinBox` idiom — only overwritten by a fresh state push
  if it still shows the last value *this page itself* synced from the
  server (so an in-progress user pick isn't clobbered), sends
  `set_mode(mode, groupNames.indexOf(group))` on `activated` via the
  real-param `executeMethod` overload (built for `IAutoFocus`, reused
  since). This is the **first string-typed real RPC param** this project
  sends (`IAutoFocus`/`IAutoGuiding`'s real params were all numeric) —
  worth confirming `VariantBridge::fromQVariant` actually round-trips
  `WireType::String` correctly against a live fixture before assuming it
  "just works" from reading the code, matching this project's
  verify-against-the-wire discipline.
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

**Fixture gap - the biggest one of any widget planned so far, flag this
clearly before starting**: unlike every previous custom widget, there is
**no `Dummy*` module implementing `IWeather`** anywhere in pyobs-core.
The only implementation (`pyobs.modules.weather.Weather`) is a real
HTTP client (`WeatherApi(url)`) for the separate `pyobs-weather` service
- it has no self-contained simulated-data mode, `_get_readings()` always
sources from a live `_api.get_current_status()` call. Live verification
would need either standing up a throwaway fake HTTP server that mimics
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

## Real parameterized command execution in Shell

**Goal:** `ShellView.qml`'s module → method → execute → log flow should
let you actually fill in command parameters and run them, the same way
`pyobs-web-client`'s `ShellView.vue` does — not just the current
all-null-params execution every entry point in this project uses so far
(see Phase 5/7.5 in `DEVELOPMENT.md`). Port `ShellView.vue`'s actual
parameter-entry behavior (per-`WireType` widgets: bool/enum/number/string)
rather than reinventing the UI from scratch.

- `ModuleListModel`'s `commands` role currently only exposes
  `{interface, name, paramCount}` (Phase 5) — needs to expose full
  `CommandSchema`s (param names/types/optionality) for real widgets to be
  built from.
- `codec::valueToXml` (Phase 5) already handles schema-aware encoding for
  non-null values; this is mostly new QML-side parameter UI plus wiring
  real values through `executeMethod` instead of `WireValue::null()` for
  every param.

---

## Real filtering on the Logs page

**Goal:** `LogsView.qml` gains real filtering (per-module checkboxes,
level filter, etc. — see `pyobs-gui`'s `mainwindow.py`'s `listClients`
checkbox list feeding `LogModelProxy` for the shape to port), beyond its
current single "All modules"/one-module `ComboBox`.

- `qml/widgets/LogFooter.qml` (the persistent bottom-of-window log tail,
  see `DEVELOPMENT.md`) is a **deliberate duplicate** of `LogsView.qml`'s
  current unfiltered rendering, not a shared component - once this lands,
  the two are expected to diverge (the footer stays a simple unfiltered
  tail; the Logs page gets the real filter UI), not be reconciled back
  into one.
