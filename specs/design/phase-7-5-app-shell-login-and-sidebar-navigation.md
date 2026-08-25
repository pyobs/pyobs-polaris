# Phase 7.5 — app shell: login window + sidebar navigation

Status: implemented, closed.

Replaced the single flat window every prior phase piled onto with two
literal top-level `ApplicationWindow`s (`LoginWindow.qml`,
`MainWindow.qml`), matching normal desktop conventions rather than the web
client's single-page router-view swap. `MainWindow.qml`'s sidebar +
`StackLayout` hosts `DashboardView.qml` (existing module list +
`RoofWidget`), `ShellView.qml` (module → method → execute → log, still
all-null params, see `TODO.md`), and `LogsView.qml` (ports `LoggingView.vue`
— filters to `type === 'LogEvent'` with a per-module dropdown and
level-colored rows, `EventLogModel::entriesOfType(type)` added since
`QAbstractListModel` gives QML no generic random-access iteration for
free).

Two real gotchas found here:

- **A PubSub notification's `from` attribute is not reliably the
  publishing module's JID.** Subscribing to a module's event node makes
  ejabberd immediately replay its last published item as a catch-up
  delivery — and that catch-up delivery's `from` is the shared pubsub
  component (`pubsub.<domain>`), not the original publisher, even when the
  replayed item is only seconds old. Only a live, freshly-pushed
  notification correctly carries the publisher's own bare JID. This is
  exactly the scenario `pyobs-core`'s own `xmppcomm.py` already guards
  against (`_handle_event()` discards anything older than 30s "to avoid
  resent events after a reconnect") — `EventManager::handlePubSubEvent`
  now applies the identical filter. Covered by
  `tst_eventmanager::ignoresStaleEvents()`.
- **`Main.qml`'s root must be `QtObject`, not `Item`.** `Item` is a visual
  type that expects to belong to a `QQuickWindow`'s scene graph; as the
  `QQmlApplicationEngine` root it never gets one, which silently breaks
  visibility of the `Window` children declared inside it (`LoginWindow`/
  `MainWindow` get created with no errors, but never map on the real
  compositor). This was originally misdiagnosed as an artifact of testing
  under `QT_QPA_PLATFORM=offscreen` and dismissed as not-a-real-bug — it
  reproduces identically on a real KDE Plasma/Wayland session, confirmed
  by querying KWin's own window list live. A second, unrelated bug was
  introduced while first fixing this: giving the `XmppClient` instance a
  property name identical to the `id` used to reference it elsewhere
  (`property var xmppClient: XmppClient {}`, then `xmppClient: xmppClient`
  on `LoginWindow`) is a self-shadowing reference — the RHS resolves to
  that object's own not-yet-assigned property of the same name before
  falling back to the outer scope. Keep the `id`-based reference pattern
  (`XmppClient { id: xmppClient }`); if `QtObject`'s lack of a default
  property means the child needs to live in some property, give that
  property a *different* name than the `id`.

