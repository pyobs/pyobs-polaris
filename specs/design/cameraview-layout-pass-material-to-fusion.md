# `CameraView.qml` layout pass + global style switch (Material -> Fusion)

Status: implemented, closed.

**Prompted by direct user feedback on a live screenshot**, not a
self-driven redesign: the ICamera MVP's flat vertical list of
`RowLayout`s (shipped in the earlier "Add ICamera widget (MVP)" commit)
read as "absolutely ugly" once actually seen running. Fixed by porting
`camerawidget.ui`'s own structure (Qt Designer XML, read directly - see
`pyobs-gui/pyobs_gui/qt/camerawidget.ui`) plus a real screenshot of the
legacy app running against this same dev fixture set, both consulted
before writing any QML: a narrow sidebar of titled `GroupBox`es (Window /
Binning & Format / Gain / Exposure), a dominant image area, a third
column for Cooling (mirroring the legacy's own right-hand sidebar
position), status/progress pinned to the very bottom of the sidebar
(not mixed into the Exposure controls), color-coded Expose/Abort buttons,
and small grey "current value" labels next to editable Window/Gain/
ExpTime fields (`WatchedLabel`'s own pattern in the legacy).

**Global style switched from Material to Fusion** (`QQuickStyle::setStyle
("Fusion")` in `main.cpp`, before `QQmlApplicationEngine` construction) -
a second, larger fix that came out of that same screenshot review.
Material's `SpinBox` renders large fixed-size `-`/`+` buttons that don't
shrink with the control; in the sidebar's now-narrower column these ate
most of the width and squeezed the actual number field down to nearly
nothing - confirmed by literally looking at a screenshot, not inferred
from QML alone. Fusion (a classic, compact desktop style - small native
up/down arrows, no oversized touch targets) fixed this app-wide, and
happens to be much closer to the legacy PyQt widget's own native sizing
in the first place.

Real gotchas hit along the way, worth remembering for any future style
work:
- **Setting `Material.theme` anywhere locks the app to the Material
  style**, silently overriding `QT_QUICK_CONTROLS_STYLE` / a runtime
  `QQuickStyle::setStyle()` call - confirmed live: setting the env var
  alone (with `Material.theme: Material.Dark` still present in
  `MainWindow.qml`/`LoginWindow.qml`) had zero visible effect. Removing
  the `Material.theme` lines (and the now-unused `import
  QtQuick.Controls.Material`) was required before the style switch took
  effect at all.
- **`QQuickStyle` needs `Qt6::QuickControls2` linked explicitly** -
  `Qt6::Quick` alone doesn't pull it in; the build fails with a plain
  `fatal error: QQuickStyle: No such file or directory` otherwise. Added
  `QuickControls2` to the `find_package(Qt6 ...)` component list and
  `Qt6::QuickControls2` to `target_link_libraries`.
- **Material-specific attached properties silently become no-ops under a
  different style** - `Material.background`/`Material.foreground` (used
  for the green Expose / red Abort buttons) do nothing once Fusion is
  active, since Fusion's `Button` never reads them. Switched to the
  style-agnostic `palette.button`/`palette.buttonText` (Fusion's own
  theming is built on `QPalette`), which works under any style, not just
  Material.
- **A `RowLayout` child wider than its column's `Layout.maximumWidth`
  doesn't clip - it stretches the whole column past the limit.** The
  `Count:` + `SpinBox` + `Broadcast` `CheckBox` row's combined implicit
  width exceeded the sidebar's 220px cap, which stretched every
  `Layout.fillWidth: true` sibling in the same `GroupBox` (including the
  Expose button) past the sidebar's right edge into the image column -
  caught live from a screenshot showing the green Expose button visibly
  bleeding across the column boundary, not obvious from reading the QML.
  Fixed by splitting cramped rows (`Count`+`Broadcast`, `Exp. time`
  label+value+`SpinBox`) onto their own separate `RowLayout`s/
  `ColumnLayout`s instead of trying to fit everything on one line.

**Live verification note**: `spectacle` (KDE's screenshot tool, already
installed) turned out to work for actually seeing the running app in
this environment, unlike the `xdotool`/`wmctrl`-shaped gap every prior
widget's write-up in this file noted - `spectacle -b -n -f -o
<path>` (background, no notification, fullscreen) or `-a` in place of
`-f` for just the active/focused window. This unblocks real visual
verification for future UI work in this dev environment - update those
older "no GUI click-through" notes' framing if picking up related work,
they're no longer a hard tooling gap, just something not tried yet at
the time.

