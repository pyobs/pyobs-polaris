# Sidebar nav made scrollable, not just clipped

Status: implemented, closed.

A follow-up bug report, direct from using the sidebar-freed-up-by-the-
`ToolBar`-move (`specs/design/current-account-and-sign-out-in-header.md`): "the sidebar spills into the log if the window is
not high enough." Root cause: the sidebar's `ColumnLayout` (inside the
nav/content `SplitView`'s horizontal pane) had no `clip` and nothing
scrollable - when a user drags the vertical `SplitView` handle (or just
has a short window) below the nav list's natural content height, QML
doesn't clip a `ColumnLayout` to its allotted space by default, so the
overflowing items simply painted past the horizontal `SplitView`'s
bottom edge, visually overlapping `LogFooter` beneath. Fixed by
wrapping everything below the fixed "Polaris" title in a `ScrollView`
(`Layout.fillWidth`/`fillHeight: true`, `clip: true`, inner
`ColumnLayout` width bound to `sidebarScroll.availableWidth`) - same
idiom `SettingsView.qml` already uses for its own potentially-overflowing
content. Dropped the trailing `Item { Layout.fillHeight: true }` spacer
that used to pad the list out to the pane's full height: inside a
`ScrollView`'s `Flickable`, content sizes to itself and packs at the top
regardless, so the spacer no longer does anything.

Live-verified by temporarily shrinking `ApplicationWindow`'s default
`height: 994` to `480` (all eight built-in module fixtures running, so
the nav list is at its longest), confirming the sidebar now clips
cleanly mid-list (after "Acquisition" in this case) instead of bleeding
into the log footer, then reverting to `994` and re-confirming the
normal-size screenshot is pixel-for-pixel the same as before this fix.

