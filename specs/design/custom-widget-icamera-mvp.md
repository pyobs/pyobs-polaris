# Custom widget: `ICamera` (MVP — exposure control, no image display)

Status: implemented, closed.

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
rendering. The wire-level harness (`specs/steering/environment-setup.md`) is significantly more thorough
than a visual click-through would have been (every state field, all three
capability roles, and all eight RPCs, vs. a screenshot only confirming
layout), so this is a real but narrow gap, not a substitute for the
missing verification - whoever picks up the next widget should either
register a saved account first (one manual login through the GUI persists
it for every widget after) or continue accepting this same limitation
already documented for `ITelescope`'s Move/Offsets click-through.

