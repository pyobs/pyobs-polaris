# Custom widget: `ITelescope` (MVP)

Status: implemented, closed.

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

