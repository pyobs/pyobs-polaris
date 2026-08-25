# Image display widget (`fits::FitsImageItem`)

Status: implemented, closed.

**Scope**: the third and final slice of TODO.md's "`ICamera` follow-up",
completing the chain `specs/design/vfs-transport.md` and `specs/design/fits-decode.md`
each stopped short of wiring up. `fits::FitsImageItem` is a new
`QQuickPaintedItem` (`src/fits/`, `QML_ELEMENT`) that decodes, stretches,
and renders a FITS image, and `CameraView.qml` now drives it from a real
`NewImageEvent`.

**No existing Qt/QML widget was a fit** (a real question asked and
answered before writing any code, not assumed): the legacy reference
(`../qfitswidget`) is Python + Qt Widgets + `matplotlib`'s
`FigureCanvasQTAgg` + OpenCV + astropy WCS - a heavy widget-based stack,
not a `QQuickItem`, not portable to this project's QML architecture.
KStars/`libkstars`'s `FITSViewer` is the closest mature C++/Qt FITS
viewer, but it's Qt Widgets too, GPL-licensed, and pulls in a large slice
of KDE/KStars infrastructure just for the viewer widget. Nothing
maintained and `QQuickItem`-native exists. Built from scratch instead,
following `plot::PlotItem`'s existing precedent (this project's only
other custom-painted QML item) - a `QQuickPaintedItem` painting a
pre-built `QImage`, not a live-recomputed-every-frame render.

**Design**:
- `fits::FitsStretch.h/.cpp` (new, pure functions, no Qt-object/QML
  dependency - same "independently testable" shape as
  `coordxform`/`FitsImage` before it) - `computeStretch()` (min/max, or a
  simple symmetric-percentile-tail-clip - deliberately *not* DS9-style
  iterative zscale, a materially more involved algorithm not justified
  without a concrete need) and `renderGrayscale()` (maps pixel values
  into a `QImage::Format_Grayscale8`, flipping FITS's bottom-up row order
  to QImage's top-down convention in the same pass, so nothing downstream
  needs to know the two disagree).
- `fits::FitsImageItem.h/.cpp` (new, the actual `QQuickPaintedItem`) -
  `loadFitsBytes(QByteArray)` decodes via `FitsImage::decode()`,
  recomputes the stretch/cached render, and repaints; a failed decode
  leaves whatever was previously displayed in place rather than blanking
  it (a single bad/truncated fetch shouldn't erase the last good frame).
  `stretchMode` is a plain `QString` ("minmax"/"percentile"), not a
  `Q_ENUM` int - matches this project's existing convention for
  QML-facing enum-like state (`comm::XmppClient::status`'s own
  "disconnected|connecting|..." strings) over introducing a new
  `Q_ENUM`-registered type for two values.
- **Zoom/pan are deliberately not implemented in C++.** QML already has
  idiomatic tools for both - `CameraView.qml` wraps the item in a
  `Flickable` (pan, for free) and drives the item's own `width`/`height`
  from a zoom `SpinBox` (`FitsImageItem` just smoothly rescales its
  cached `QImage` into `boundingRect()` on every paint - reimplementing
  flick physics in C++ would only duplicate what `Flickable` already
  does).
- `CameraView.qml` wiring: `NewImageEvent` delivery itself needed no new
  C++ - `EventManager` already subscribes to every event a module's
  disco#info advertises (Phase 6), so this only needed to notice a new
  one arriving for *this module's* jid
  (`xmppClient.events.entriesOfType("NewImageEvent")`, the same
  `Connections { onRowsInserted }` idiom `EventsView.qml` already uses)
  and drive `VfsEndpointsModel::resolveVfsPath()` →
  (`loadPassword()` if the endpoint has one, async) →
  `VfsClient::fetchFile()` → `FitsImageItem::loadFitsBytes()`. Every
  in-flight request is correlated back to its own `Repeater` delegate via
  a `jid|filename` request id and the endpoint id from `resolveVfsPath()`
  - both `VfsClient`'s and `VfsEndpointsModel`'s signals are global, not
  scoped to one delegate, since multiple cameras can legitimately be
  fetching concurrently (possibly even sharing one VFS endpoint's
  password load).

**Testing**: `tests/fits/tst_fitsstretch.cpp` covers `computeStretch()`
(min/max, percentile-tail-clip math checked against hand-computed
indices, non-finite values ignored, empty/all-non-finite fallback) and
`renderGrayscale()` (black/white mapping, the FITS-to-QImage row flip
specifically, flat-image divide-by-zero handling, size-mismatch
rejection). `tests/fits/tst_fitsimageitem.cpp` covers the item's public
API short of `paint()` itself (load success/failure, failure preserving
the previous image, stretch-mode changes recomputing levels) - same
"don't test `paint()` directly" precedent `tst_plotitem.cpp` already
set.

**Live verification**: extended the FITS decode section's harness
further - `grab_data()` → `VfsClient::fetchFile()` →
`FitsImageItem::loadFitsBytes()` end to end against the same
`fixtures/httpfilecache.yaml` + `fixtures/camera.yaml` pair, confirming
`hasImage`/`imageWidth`/`imageHeight`/`blackLevel`/`whiteLevel` all
populated correctly from a real fetched frame. Beyond that, went one step
further than every prior wire-level-only harness in this project: dumped
the actual rendered `QImage` to a PNG and visually inspected it (via
Claude Code's own image-reading capability, not just byte/dimension
assertions) - a clean, correctly-decoded 512x512 grayscale noise field,
exactly matching `DummyCamera`'s synthetic random test image, no
flip/clipping artifacts. No GUI click-through of `CameraView.qml`
itself (same no-`xdotool`/`wmctrl`-available limitation noted in every
prior widget's write-up in this file) - the rendered-PNG check is a
stronger correctness signal for *this specific feature* (pixel data
correctness, not layout) than a screenshot would have been anyway.

**Addendum - a real GUI click-through (by the user, not automation) did
catch a bug the wire-level harness above could not have**:
`checkForNewImage()`'s `events[i].module !== jid` comparison never
matched, so a fetch never even started - no loading/error label, nothing
- while `grab_data()` itself succeeded and the `NewImageEvent` visibly
appeared on the Events page, making it look like event delivery itself
was broken. Root cause: `EventLogModel`'s `module` field is the *local
part only* of the sender's JID (`EventManager.cpp` uses
`QXmppUtils::jidToUser()`), but `cameraDelegate.jid` (from
`ModuleListModel`) is the full bare JID (`"camera@localhost"`, per
`ModuleInfo.h`'s own comment) - `"camera" !== "camera@localhost"` is
always true. Fixed by comparing against `jid.split("@")[0]` instead.
Purely a QML-side bug (a string-format mismatch between two existing,
independently-correct C++ pieces), invisible to every headless C++
harness used throughout this pass - the harnesses called
`VfsEndpointsModel`/`VfsClient`/`FitsImage` directly with the right
filename already in hand, never exercising the
`EventLogModel`-to-`ModuleListModel` JID correlation this bug was in.
Worth remembering for any *future* code that correlates an event's
`module` field against a `ModuleListModel`-sourced `jid` - this is the
first place in the project that did, and got it wrong the first time.

