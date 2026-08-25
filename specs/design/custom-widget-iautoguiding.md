# Custom widget: `IAutoGuiding`

Status: implemented, closed.

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

