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

## ACL / permitted-methods gating

**Goal:** hide/disable controls the current XMPP user's ACL doesn't allow,
matching pyobs-gui's own `base.py` (`BaseWidget._fetch_permitted_methods()`/
`permitted(method)`): every widget there fetches
`IModule.get_permitted_methods()` once per module and gates each button
(Init/Park/Stop/Move/every Set/Reset button, per-widget) on membership in
that cached set, falling back to "everything permitted" if the fetch
fails or the method isn't implemented.

**Why this isn't already covered elsewhere in this doc:** never designed
against, not a deliberate clean-room cut - only noticed when directly
asked to compare `TelescopeView.qml` against `telescopewidget.py`
control-by-control. Confirmed wire-available, not a limitation of this
project's XMPP-only approach: `get_permitted_methods` is a real command
every `IModule` advertises in disco#info (visible in this project's own
fixture dumps, e.g. `camera@localhost`'s: `interface IModule v1: command
get_permitted_methods ( )`) - so this is a genuine, currently-unaddressed
capability gap between the two clients, not a scope cut worth recording
as "out of scope".

**Why this is cross-cutting, not page-specific:** pyobs-gui's
`permitted()` lives on `BaseWidget`, the common base every one of its
widgets inherits - every page in this project (`RoofView`/
`TelescopeView`/`CameraView`/`AutoFocusView`/`AcquisitionView`/
`AutoGuidingView`/`ModeView`/`WeatherView`, and any future
`SidebarPanelRegistry` panel) would need the same gating on every
RPC-triggering button, not just `TelescopeView.qml`'s Init/Park/Stop/
Move/offset buttons that prompted noticing this.

**Shape once designed:**
- Fetch `get_permitted_methods()` once per module - likely folded into
  the existing disco#info discovery flow (`XmppClient`/`Discovery.cpp`),
  not per-widget, to avoid every widget showing the same module
  redundantly re-fetching the same list.
- Cache the result (or `null`/absent on failure - "treat everything as
  permitted", matching pyobs-gui's own fail-open default) somewhere
  QML-reachable, most naturally a new `ModuleListModel` role mirroring
  `InterfacesRole`/`CapabilitiesRole`'s existing narrow-role precedent.
- Every `Button.enabled` expression that currently only checks motion
  status/interface presence would additionally check permission - a
  mechanical but genuinely *wide* change (every page at once), which is
  exactly why the plumbing should be designed once and applied
  project-wide in a single pass rather than gating pages one at a time.
- Method-name matching must exactly match whatever string
  `get_permitted_methods()` actually returns per method - confirm
  against a live pyobs-core module, not assumed from source (this
  project's own standing rule for wire behavior).

**Deliberately not in scope even once this ships:** actual ACL
*configuration* - that's a pyobs-core/server-side concept this project
never writes to, only reflects what the server already reports.

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

**Still explicitly out of scope even once unblocked**: JPL Horizons/MPC
lookups (network dependency, unrelated to any of this), the compass
widget. SIMBAD name resolution - once listed alongside these two - is
done (`comm::SimbadClient`, talks SIMBAD's own TAP/ADQL service directly
rather than pulling in astroquery, see `DEVELOPMENT.md`'s own write-up);
JPL Horizons/MPC remain out of scope purely because nothing in this
project needs their APIs specifically yet, not because of any technical
blocker SIMBAD's own solution didn't already clear. The rest of
telescopewidget.ui's own fourth sidebar (Filter/Focus/Temperatures) is
done - see `DEVELOPMENT.md`'s `TelescopeView.qml`/`CameraView.qml`
follow-ups.

---

## `ICamera` follow-up: image display, VFS — done

**Goal (met):** the actual image-preview half of `camerawidget.py`
(`DataDisplayWidget`) — shipped in three separate pieces since each
needed a genuinely new project-wide capability, not a widget-local
addition:

- **VFS (virtual file system) client transport** (see `DEVELOPMENT.md`'s
  "VFS transport" write-up): `config::VfsEndpointsModel` (a new
  per-account, keychain-backed Settings page, mirroring
  `SavedAccountsModel`'s pattern) maps a VFS root name to an HTTP base
  URL, and `comm::VfsClient` fetches it via `QNetworkAccessManager`, live-
  verified byte-for-byte against a real `grab_data()`-produced file served
  by a real `pyobs.modules.utils.HttpFileCache`. Only the `http` backend
  is modeled — same reasoning as `pyobs-web-client`'s `useVfsConfig.ts`,
  which this ported: a desktop/browser client can only ever reach
  `HttpFile`, never `LocalFile`/`SFTPFile`/`SMBFile`/etc. directly, so
  those aren't a "not yet" gap, they're permanently out of scope for a
  client-side VFS reader.
- **FITS decode** (see `DEVELOPMENT.md`'s "FITS decode" write-up):
  `fits::FitsImage` (new `src/fits/`, plain C++ class, no QML surface of
  its own) decodes a complete in-memory FITS file via `cfitsio` (added as
  this project's first real Conan dependency, `conanfile.txt`) into
  row-major `double` pixel data + header cards, uniformly regardless of
  on-disk `BITPIX`. Live-verified against a real `grab_data()` →
  `VfsClient::fetchFile()` round trip: decoded dimensions/header
  values/pixel min-max all matched an independent `astropy` read of the
  same bytes exactly.
- **The image display widget** (see `DEVELOPMENT.md`'s "Image display
  widget" write-up): `fits::FitsImageItem` (`QQuickPaintedItem`,
  `src/fits/`, following `plot::PlotItem`'s existing precedent) decodes,
  stretches (min/max or percentile-clip), and renders a `NewImageEvent`'s
  image into `CameraView.qml`. Zoom/pan are QML-side (`Flickable` +
  resizing the item), not reimplemented in C++. Wired end to end:
  `grab_data()` → `NewImageEvent` → `VfsEndpointsModel::resolveVfsPath()`
  → `VfsClient::fetchFile()` → `FitsImageItem::loadFitsBytes()`.
  Live-verified with a rendered PNG of a real fetched frame visually
  inspected, not just "didn't crash".

**`FitsHeadersWidget` remains intentionally out of scope** — ignored on
direct instruction, not merely deferred alongside the rest of this item.
Kept as its own bullet only as a record of why it's a materially
different problem (the GUI would have to answer an incoming RPC, not
just issue outgoing ones) whenever it does come back into scope:

- **`FitsHeadersWidget` — ignored for now, record only:**
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

**Follow-up, image controls — done:** ported the rest of
`datadisplaywidget.py`/`.ui` and `qfitswidget`'s own toolbar
(`fitswidget.ui`) that weren't part of the original wiring above, in two
passes:

- **Auto-update/Auto-save/Save-to** bottom row (`fits::FitsFileWriter`
  for the actual disk I/O, `QtQuick.Dialogs`' `FileDialog`/`FolderDialog`
  for picking the destination - Auto-update gates the *whole* fetch, not
  just display, matching `_on_new_data()`'s own early-return exactly),
  plus a "Custom" cuts mode (`fits::FitsImageItem::setManualLimits()`)
  with editable Lo/Hi spin boxes mirroring `qfitswidget`'s
  `spinLoCut`/`spinHiCut`.
- **Direct follow-up request** ("make [cuts] the same as in pyobs-gui,
  and also add tone-curve stretch, colormap and trimsec"), once the gap
  from the first pass was pointed out live:
  - **Cuts presets now match `comboCuts` exactly**
    (100.0/99.9/99.0/95.0%/Custom, `FitsImageItem::setPercentilePreset()`/
    `enterCustomMode()`) - the separate "Min/Max" mode from the first
    pass was dropped entirely, since 100.0% percentile already *is* the
    literal min/max (see `FitsStretch.h`), matching `comboCuts` having no
    separate entry for it either.
  - **Tone-curve `Stretch:` combo** (linear/log/sqrt/squared/asinh,
    `fits::ToneCurve`) - applied to the already black/white-normalized
    [0,1] value rather than the raw pixel value the way `qfitswidget`'s
    `FuncNorm` does (same qualitative brightness-compression shape,
    without needing its masked-array handling for non-positive raw
    values - see `FitsStretch.h`'s own comment).
  - **Colormap selection + reversed checkbox** (`fits::Colormap`) - a
    small curated set (Gray/Viridis/Hot/Cool/Jet), not an attempt at
    matplotlib's ~150-map library `comboColormap` offers - vendoring a
    colormap library for that would be a lot of dependency weight for no
    functional gain over a practical subset.
  - **`trimsec` checkbox** (`fits::applyTrimSec()`, default on matching
    `checkTrimSec`'s own `.ui` default) - zeroes pixels outside the
    header's `TRIMSEC` rectangle before both stretch computation and
    render, same as `qfitswidget`'s `_trim_image()`.
  - **Real bug caught mid-pass, now fixed**: `computeStretch()` didn't
    exclude non-positive pixels, so a `TRIMSEC`-zeroed border pulled the
    black level down to 0 on every trimmed image - `qfitswidget`'s own
    `_trim_image()` filters `trimmed_data > 0` for exactly this reason,
    now matched here too (see `FitsStretch.h`'s comment on
    `computeStretch()` for the full tradeoff this implies for
    legitimately non-positive science pixels).
  - **Also caught live** (not by a unit test): two QML scoping bugs -
    `cutsComboIndexFor()` was accidentally defined on the wrong `id`-less
    `ColumnLayout` rather than `cameraDelegate`, and `ComboBox.indexOfValue()`
    turned out unreliable for these object-array models (silently left
    `currentIndex` at -1, blank combo text, no QML warning at all) - see
    `DEVELOPMENT.md`'s write-up for both.

`fits::FitsStretch` now covers everything `qfitswidget`'s own toolbar
does except full matplotlib colormap parity (deliberately out of scope,
see above) and `qfitswidget`'s own live pixel-value/WCS mouse-hover
readout (never in scope for this project's `ICamera` port at all - not
listed as a gap anywhere above, and still isn't one now).
