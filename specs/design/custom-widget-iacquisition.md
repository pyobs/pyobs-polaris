# Custom widget: `IAcquisition`

Status: implemented, closed.

Second of the three custom widgets tracked in `TODO.md`, ported from
pyobs-gui's `acquisitionwidget.py` - `qml/views/AcquisitionView.qml`,
gated in the sidebar the same way as Roof/Auto Focus
(`MainWindow.qml`'s `hasAcquisitionModule`). Live-verified against a real
`DummyAcquisition` (`fixtures/acquisition.yaml`) end to end: running an
acquisition series, watching both plots update live, the result fields
(RA/Dec/Alt/Az/offset) populating on success, and aborting mid-run.

Simpler than `IAutoFocus` in two respects, both confirmed against the
real disco#info schema before writing any QML: `acquire_target()` takes
no params at all, so this widget didn't need the real-parameter
`executeMethod` overload Phase 8's `IAutoFocus` work added - the existing
paramCount-based overload is enough. And the result
(`AcquisitionResult`) arrives as part of `AcquisitionState` itself
(`state.result`), not a separate event - `acquisitionwidget.py` never
registers one, so `AcquisitionView.qml` doesn't either, sidestepping the
`FocusFoundEvent` JID-format gotcha entirely for this widget (still worth
checking for again in `AutoGuidingView`, see `TODO.md`).

**`PlotItem` grew a real property surface here** (`xFieldIndex`/
`yFieldIndex`, `showLine`, `equalAspect`, `originCrosshair`,
`showStartMarker`/`showLatestMarker`, `xTicksAsIntegers`) to cover
`acquisitionwidget.py`'s two plots: distance-per-attempt (a line, not
just a scatter - `AutoFocusView.qml`'s plot never needed one) and the 2D
offset trajectory (equal-aspect scaling, an origin crosshair, red-square
"start"/green-star "latest" markers). `xFieldIndex`/`yFieldIndex` matter
because `AcquisitionAttempt`'s fields aren't in `(x, y)` position for the
offset plot (`{attempt, distance, offset_applied, offset_frame,
offset_lon, offset_lat}` - offset_lon/lat are indices 4/5, not `PlotItem`'s
default 0/1) - the alternative (reshaping records in QML before handing
them to `PlotItem`) would have meant `.map()`-ing over a value that
crossed the C++→QML boundary, the exact risk class already flagged in the
`specs/design/custom-widget-iautofocus.md`. `setPoints()`/`reparsePoints()` also gained
null-field skipping here (`AcquisitionAttempt.offset_lon`/`offset_lat`
are `optional<float64>`, `None` before an offset frame is known) - a gap
`IAutoFocus`'s always-populated `AutoFocusPoint{focus, value}` never
exposed. Covered by `tests/plot/tst_plotitem.cpp` (new test target,
`QT_QPA_PLATFORM=offscreen`), including a real assertion via the new
test-only `pointCount()`/`pointAt()` accessors - not just "didn't crash."

**The real story of this widget was a `RowLayout` bug that cost most of
the implementation time**, found and fixed only by live screenshot-driven
iteration, not by reasoning about the QML alone:

- First symptom, live: the two plots (meant to sit side by side, matching
  `acquisitionwidget.py`'s `plt.subplots(1, 2)`) rendered with one taking
  almost all the available width and the other squeezed to a barely-
  visible sliver - both `PlotItem`s had identical
  `Layout.fillWidth: true` + `Layout.preferredWidth: 1`. Screenshotting
  the actual running app (via `spectacle -b -n`, this machine's Wayland-
  session screenshot tool, since no window-automation tool was available)
  was what made this obvious in the first place - it hadn't been caught
  by reading the QML.
- Ruled out `PlotItem` as the cause by reproducing the identical lopsided
  split with plain debug-colored `Rectangle`s standing in for both
  `PlotItem`s - confirming this was a `RowLayout` stretch-distribution
  problem, not anything about `PlotItem`'s own (missing) size hints.
- First fix attempt - computing each child's `Layout.preferredWidth`
  directly from the `RowLayout`'s own `id`-referenced width
  (`plotsRow.width`) - **froze the app solid** (window manager reported
  "not responding"). `RowLayout`'s own width is not necessarily
  independent of its children's `preferredWidth`; that binding fed back
  on itself. Recovered by force-killing the process
  (`pkill -9`) and reverting.
- Second fix attempt - a plain `Row` (not `RowLayout`) with each child's
  `width:` computed directly from a stable ancestor
  (`acquisitionDelegate.width`, the `Repeater` delegate's own
  `ColumnLayout`) - didn't freeze, but silently stabilized at a *small,
  wrong* value instead: a temporary `DEBUG root.width=...` label
  (removed once diagnosed) showed `AcquisitionView`'s own root at 365px
  vs. `AutoFocusView`'s root at 676px in the *same* window at the *same*
  size - `acquisitionDelegate.width` turned out not to be the
  externally-driven value it looked like either, so this was the same
  class of circularity as the frozen attempt, just one that happened to
  converge instead of hang.
- Ruled out `Layout.preferredWidth` itself as the culprit by trying
  `Layout.fillWidth: true` alone (no preferredWidth override at all,
  matching how `AutoFocusView.qml`'s single `PlotItem` already works) -
  reproduced the exact same lopsided split. Also tried wrapping each
  `PlotItem` in a plain `Item` (giving *that* the `Layout.*` properties,
  `PlotItem` just `anchors.fill: parent` inside it) on the theory that a
  custom `QQuickPaintedItem` with no `implicitWidth`/size hints of its
  own confuses `RowLayout`'s stretch algorithm - reproduced the same
  failure mode, still with real `PlotItem`s inside. At this point the
  lopsided split had been reproduced with three different child types
  (`PlotItem` directly, `PlotItem` wrapped in `Item`, plain `Rectangle`s
  with no `PlotItem` involved at all) - conclusively a `RowLayout`
  problem in this specific nesting context (`Repeater` delegate inside a
  `ColumnLayout` `StackLayout` page), not a child-type problem, but the
  exact root cause inside `RowLayout`'s stretch-distribution algorithm
  was never actually identified.
- **First resolution: stopped trying to fix `RowLayout` and stacked the
  two plots vertically instead**, via the same plain `ColumnLayout`
  `Layout.fillWidth: true`-per-item mechanism every other page in this
  project (including `AutoFocusView.qml`'s own single plot) already uses
  successfully - shipped and committed as a working, if visually
  different from `acquisitionwidget.py`, layout.
- Stacking two 220px-tall plots vertically pushed the page's total
  content height past a typical window's visible area - the result
  fields/buttons below the plots silently clipped at the window's bottom
  edge. Fixed by wrapping the whole page in a `ScrollView` (`root`'s
  element type, not just a plain `ColumnLayout` like every other page)
  - the first page in this project that needed one, and worth keeping
  regardless of the plot layout question below, since even a single row
  of two plots plus labels/buttons can still exceed a short window.
- **On request, side by side after all** - found on a second attempt, not
  by finally cracking `RowLayout`'s actual bug, but by sidestepping it a
  different way than the two failed attempts above: a plain `Row` (not
  `RowLayout`, same as the failed second attempt) with each `PlotItem`'s
  `width:` computed from `root.availableWidth` instead of
  `acquisitionDelegate.width`. The earlier attempt's circularity was
  specifically about `acquisitionDelegate.width` (a `Repeater` delegate's
  own width, which turned out to be ambiguous when referenced from its
  own descendants) - `root` is the page's own top-level `ScrollView`,
  gets its width authoritatively from `MainWindow.qml`'s `StackLayout`
  from *outside* this file, and nothing inside ever writes back to it, so
  there's no cycle to feed. Confirmed live, stable (no freeze, normal
  CPU), correct split, before asking for confirmation - this is the
  layout `AcquisitionView.qml` actually ships with; the vertical-stack
  fallback above was superseded, not left as an alternate path.
  `TODO.md`'s `IAutoGuiding` entry should be read with this in mind: the
  `root.availableWidth` technique, not vertical stacking, is the
  recommended starting point for that widget's own two plots.
- Two more issues only visible live, not from reading the QML/C++: the
  narrower side-by-side plots' y-axis tick labels (long decimal degree
  values, e.g. `0.0003142`) overlapped the rotated y-axis title text -
  both were being drawn inside the same fixed-width `kMarginLeft = 55`
  zone in `PlotItem::paint()`. Fixed by computing the left margin per-
  paint from the actual widest y-tick label's measured text width
  (`QFontMetrics`) plus a reserved strip for the title, rather than one
  constant shared by both. Separately, `AcquisitionAttempt`'s
  `offset_lon`/`offset_lat` are degrees, which produced exactly those
  impractically long decimal tick labels for values this small - added
  `PlotItem.xScale`/`yScale` (default `1.0`, applied in
  `reparsePoints()`, so no QML-side per-point transform is needed) and
  set them to `3600` on the offset plot, matching
  `autoguidingwidget.py`'s own degrees-to-arcsec convention for the same
  kind of small angular offset. The result row below the plots
  (`RA/Dec offset: (...)`) was switched to arcsec too, for consistency
  with the plot it sits under.

