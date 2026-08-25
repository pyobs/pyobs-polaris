# Dashboard and `RoofWidget` removed

Status: implemented, closed.

Direct request: Status moved to the top of the sidebar, and Dashboard
dropped entirely rather than kept alongside it - taking `RoofWidget`
(Phase 7's `IRoof` Open/Close/Stop controls) and the original generic
expandable module list (interfaces/live state/commands, Phase 3-5) down
with it, on the reasoning that neither had a second home to move into
that wasn't itself extra unasked-for scope. `ShellView.qml` already
covers generic command execution (module → method → execute → log); nothing
currently replaces per-module live state viewing (`KeyValueCard`/
`subscribeState()`) or dedicated roof control - `comm::StateSubscription`/
`StateSubscriptionManager`/`XmppClient::subscribeState()` are untouched
and still fully covered by `tests/comm/tst_statesubscription.cpp`, just
with no QML caller left; picking a new home for live state viewing (the
Status page? a rebuilt Dashboard? per-interface pages?) is an open
question for whenever that capability is actually needed again, not
decided here.

Deleted: `qml/views/DashboardView.qml`, `qml/widgets/RoofWidget.qml`,
`qml/widgets/KeyValueCard.qml` (the last one orphaned the moment the
first two were gone - nothing else ever used it). `MainWindow.qml`'s
`StackLayout`/sidebar order is now Status (0), Shell (1), Logs (2).
`TODO.md`'s "Loose ends from Phase 7" section (both items were about
`RoofWidget`) is gone too rather than left describing a widget that no
longer exists.

**Follow-up, next request:** roof control came back, but reshaped - as
its own dedicated `qml/views/RoofView.qml` page (index 3) rather than
folded back into a rebuilt Dashboard, and `qml/widgets/KeyValueCard.qml`
came back with it (still the only consumer). The one new piece: the
"Roof" sidebar entry is conditionally visible, shown only while at least
one connected module implements `IRoof` - `ModuleListModel` gained a
plain query, `Q_INVOKABLE bool hasInterface(const QString &)`, and
`MainWindow.qml` recomputes a `hasRoofModule` property from it on every
`rowsInserted`/`rowsRemoved`/`modelReset`/`dataChanged` (same
recompute-on-signal shape as `LogsView.qml`'s own model-driven
`refresh()`, since a `QAbstractListModel` gives QML no live-updating
aggregate query for free). If the last `IRoof` module disconnects while
its page is the active one, `MainWindow.qml` jumps back to Status rather
than leaving the sidebar highlighting a now-hidden entry. Covered by
`tests/comm/tst_modulelistmodel.cpp` (`hasInterface` true/false across
multiple modules); the reactive sidebar-visibility/auto-switch behavior
itself is QML-only and wasn't separately verified live this session (same
X11-access constraints as the Status page's own note (`specs/design/status-page.md`).

**Follow-up, sidebar layout ported from `AppLayout.vue`:** direct
request to match the web client's nav look - an icon before each label,
plus its "Tools"/"Modules" section grouping (Status standalone at top,
Shell/Logs under "TOOLS", Roof under a conditionally-visible "MODULES").
No bundled icon font/theme exists here (unlike the web client's
Bootstrap Icons), so icons are plain Unicode glyphs picked to read the
same at a glance: `●` (status dot, matching the health-badge dots
already used on the Status page itself), `❯` (terminal prompt, Shell),
`▤` (lined page, Logs), `⌂` (house, Roof). `MainWindow.qml` gained two
inline `component`s (Qt 6.5+ syntax, scoped to that one file since
nothing else needs them): `SidebarItem` (an `ItemDelegate` with a custom
`contentItem` laying out icon + label) and `SidebarSectionLabel` (small
uppercase muted header). The "MODULES" header's `visible` is bound to
the same `hasRoofModule` the Roof entry itself already used, so the
header and the entry appear/disappear together.

