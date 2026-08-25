# Real filtering on the Logs page

Status: implemented, closed.

`LogsView.qml`'s single-select "All modules"/one-module `ComboBox`
replaced with real filtering, ported from pyobs-gui's actual
`mainwindow.py`/`logmodel.py` shape (checked directly, not assumed): a
checkbox per known client (`listClients`, a `QListWidget`) feeding a
`QSortFilterProxyModel` (`LogModelProxy.filter_source`) - multi-select
show/hide, not a single active filter. Reuses the existing `knownModules`
idiom (derived from `logEvents`, not a new model) instead of introducing
a `Repeater` over `xmppClient.modules` - this project has no clean idiom
yet for turning a `QAbstractListModel` into a plain JS array outside of
delegate binding (see `EventLogModel::entriesOfType()`'s own comment on
this), and `knownModules` already solves the same problem for the
now-removed `ComboBox`.

**Deliberate divergence, not a bug**: `listClients` is fully
cleared/rebuilt from `self.comm.clients` on every client-list change,
which resets every checkbox back to checked - any filter you'd set is
silently discarded the next time a module connects or disconnects. This
page instead only ever *appends* newly-seen module names to
`knownModules`, so a filter choice (which modules are hidden) survives
new modules coming and going. Trade-off: a module only gets a checkbox
once it has logged at least one entry this session, not the moment it
connects (`listClients` populates from all connected clients regardless
of whether they've logged anything yet).

A minimum-level filter (`ComboBox`: ALL/DEBUG/INFO/WARNING/ERROR/
CRITICAL) was also added - confirmed via `logmodel.py::LogModelProxy`
that the Python reference has **no level filter at all**, only sender
filtering, despite `TODO.md`'s own note mentioning one; added anyway
since this page already computes a level for row coloring, so the
threshold check is nearly free.

Live-verified against two real dummy modules (`DummyRoof`, `DummyCamera`,
started ad hoc against fixture accounts - not new committed fixture
files) rather than just built: screenshotted the running app and
confirmed the level `ComboBox`, per-module checkboxes (correctly labeled,
checked by default), and per-row module attribution all render
correctly. Incidentally surfaced a pre-existing data characteristic, not
a bug in this change: a module's very first startup log line can arrive
with an empty `module` field (an early log message racing the module's
own XMPP JID binding) - the old `ComboBox` would have shown this just as
blankly, the new checkbox list just makes it more visible. **Not
verified**: actually clicking a checkbox/the level `ComboBox` to confirm
the toggle interaction end-to-end - no UI automation tool (`xdotool`/
`ydotool`) was available in this environment and installing one wasn't
requested. The toggle logic itself reuses already-proven QML idioms from
elsewhere in this project (whole-array reassignment for reactivity,
`filter()`/`includes()`/`concat()`), so this is a real but narrow gap,
worth an actual click-test whenever a display with automation tooling is
available.

