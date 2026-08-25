# Resizable sidebar

Status: implemented, closed.

Direct request: the sidebar was a fixed-width (`Layout.preferredWidth:
180`) child of a plain `RowLayout`, with a manual 1px `Rectangle` as a
purely visual divider between it and the page content - no way to
resize it at all, unlike the log footer (`specs/design/persistent-log-footer.md`, already a `SplitView`
pane). `MainWindow.qml`'s nav+content `RowLayout` is now itself a
horizontal `SplitView` nested inside the existing vertical one (the
outer `SplitView` still splits nav+content from the log footer; the new
inner one splits the sidebar from the page content) - the sidebar
`ColumnLayout` and content `StackLayout` become `SplitView` panes
(`SplitView.preferredWidth: 180`/`SplitView.minimumWidth: 140` and
`SplitView.fillWidth: true` respectively) the exact same way `LogFooter`
already does for height. The manual `Rectangle` divider is gone -
`SplitView`'s own handle replaces it, both as the visual divider and as
the actual drag target.

Live-verified rendering (correct default width, sidebar content and
content pane both intact, handle visible) but **not** the actual
drag-to-resize interaction - same class of gap as the Logs/Events pages
above (no `xdotool`/`ydotool` in this environment), compounded here by
`MainWindow` only being reachable past a real login, which needed its
own temporary workaround to get past non-interactively: `LoginWindow.qml`'s
`Component.onCompleted` briefly grew an extra `root.quickConnect(lastId)`
call (reusing the existing one-click-reconnect path the account list's
own ▶ button already calls) to skip straight to a connected `MainWindow`
without a click - reverted before committing, confirmed via a clean
rebuild + full `ctest` pass afterward, same discipline as every other
temporary verification edit in this file.

