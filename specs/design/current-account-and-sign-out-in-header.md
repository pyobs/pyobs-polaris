# Current account + "Sign out" moved into a `header: ToolBar`

Status: implemented, closed.

Direct user request: these lived in a `ColumnLayout` pinned to the
bottom of the sidebar (`MainWindow.qml`), below a `Item { Layout.
fillHeight: true }` spacer that pushed them down regardless of how many
Tools/Modules entries were above. Moved to a `RowLayout` inside
`ApplicationWindow`'s `header: ToolBar` instead, right-aligned via a
leading `Item { Layout.fillWidth: true }` spacer - frees the sidebar's
full height for nav, and keeps account context visible in the same
place regardless of sidebar content. `ApplicationWindow` already had a
`header` slot available (this project's root has been an
`ApplicationWindow`, not a plain `Window`, since it needed a real scene
graph root - see `Main.qml`'s own doc comment), so no structural change
was needed beyond adding the `ToolBar` itself. Live-verified via the
AT-SPI screenshot tool: JID and "Sign out" render top-right, and
"Sign out" still correctly calls `xmppClient.disconnectFromServer()`
and drops back to the login window from its new location - stock
`Button`/`ToolBar` need no `Accessible.role` wiring, per point 3 of
`specs/steering/environment-setup.md`'s AT-SPI section.

