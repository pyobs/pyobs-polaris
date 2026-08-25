# Status page

Status: implemented, closed.

Ad hoc, not in original plan - ports `pyobs-gui`'s (the Python/PySide6
desktop client, `statuswidget.py`) `StatusWidget`: a flat "is everything
OK" overview of every connected module - name, `IModule` capabilities'
`version`, and live presence-derived health (ready/error/local), with a
one-click "Clear error" (just `IModule.reset_error`, already a generic
command). Deliberately *not* a port of `StatusWidget`'s full `QTreeWidget`
(interfaces/capabilities/state drill-down) - that lived, differently, in
`DashboardView.qml`'s expandable module rows at the time this page was
written; duplicating it here would just have been two paths to the same
data. (`DashboardView.qml` itself is gone as of `specs/design/dashboard-and-roofwidget-removed.md` -
this note is kept for why Status was scoped narrowly, not because the
alternative still exists.)

The one genuinely new piece: this project's presence handling
(`XmppClient::handlePresence`) previously only ever distinguished
available vs. `QXmppPresence::Unavailable` (add/remove from
`ModuleListModel`) - it never looked at `<show/>`/`<status/>`, so there
was no READY/ERROR/LOCAL concept anywhere in the C++ side yet, unlike the
Python/`pyobs-core` side which has always had it. Wire-level mapping
(confirmed against `pyobs-core`'s `xmppcomm.py` `_got_online`/
`_got_presence_update`/`_set_presence`): `show=dnd` → error,
`show=away`/`xa` → local, anything else (including plain available) →
ready; `<status/>` text is the error string. `QXmppPresence` exposes this
directly (`availableStatusType()`/`statusText()`) - no new wire parsing
needed. An unavailable module is still fully removed from the list rather
than kept around as a "closed" row (matches this project's existing
presence-removal behavior; the Python `ModuleState.CLOSED` state has
correspondingly no representation here).

`ModuleInfo` gained `presenceState`/`presenceError` fields, set from the
presence stanza that triggers either a fresh `fetchModuleInfo()` (new
module) or, more often, `ModuleListModel::updatePresence()` - an in-place
role update with no disco#info re-fetch, since most presence traffic for
an already-known module is just a state change, not new schema. `version`
is not a new network round trip either: it was already sitting in
`ModuleInfo::capabilities["IModule"]` (a `WireDict` with `label`/
`version`) from the existing disco#info fetch, just never surfaced
through a model role before.

Covered by `tests/comm/tst_modulelistmodel.cpp` (new-module defaults,
version lookup with/without `IModule` capabilities present,
`updatePresence()` in-place update + its unknown-JID `false` return).
Live data flow (disco#info parse producing `capabilities.IModule` with a
real version string) reconfirmed against the `telescope` fixture; the
actual on-screen page itself wasn't visually verified this session - the
app's window didn't appear in the real X11 session's window tree when
launched (same class of issue as Phase 7.5's window-visibility gotcha),
and this display is the user's actual desktop session (visible other
windows include a private chat client), so no broader screenshot was
attempted either. Worth an actual look next time a clean display is
available.

