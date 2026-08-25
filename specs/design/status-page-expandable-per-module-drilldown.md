# Status page: expandable per-module drill-down

Status: implemented, closed.

Direct request, answering the open question left by "Dashboard and
`RoofWidget` removed" (`specs/design/dashboard-and-roofwidget-removed.md`): bring back `DashboardView.vue`'s
expand/collapse per-module drill-down (interface badges, live state,
capabilities), but onto `StatusView.qml` rather than resurrecting a
Dashboard - this page was already the natural home once Dashboard was
gone, and there's still no second consumer for `subscribeState()`/
`KeyValueCard` to justify a separate page.

Ports `DashboardView.vue` fairly literally: collapsed by default (`▸`/`▾`
chevron, whole row clickable via a `MouseArea` painted *behind* the row's
`RowLayout` so its own "Clear error" `Button` still gets first claim on
the click - the standard "background click-catcher declared first"
stacking trick), plus "Expand all"/"Collapse all" buttons. Expanded state
is a plain JS object used as a Set (`expandedJids`), always reassigned
wholesale rather than mutated in place, same reasoning as everywhere else
in this codebase that a QML binding only re-evaluates on property
*reassignment*.

Three new pieces on `ModuleListModel`, since none of its existing
narrowly-scoped roles (`VersionRole`, `ModeGroupsRole`, etc.) were meant
for a generic dump: `InterfacesRole` ("interfaces", every declared
interface + version, unlike `StatefulInterfacesRole`'s state-only
filter - the badge row), `CapabilitiesRole` ("capabilities", every
interface's *whole* decoded capabilities dict bridged via
`codec::toQVariant`, keyed `ifaceName`/`value` - not `interface`/`value`,
because `interface` is an ES/QML reserved word and breaks a `required
property` of that name on a Repeater delegate bound directly to the
list), and `Q_INVOKABLE QStringList jids()`, the same "QML gets no
generic random-access iteration over a `QAbstractListModel`" escape hatch
as `hasInterface()`/`allCommands()`, needed for "Expand all" to build its
full jid set without per-row access into the model.

Live state subscriptions follow `RoofView.qml`'s manual lifecycle
pattern (`Component.onCompleted` subscribe / `Component.onDestruction`
unsubscribe via a `property var subscription: null`), but sidestep that
file's own documented footgun (a `property var subscription: <expr>`
binding re-running without unsubscribing the old one first, when its
dependencies change while the *same* delegate instance persists) by
construction rather than by care: the inner `Repeater`'s `model` is
`expanded ? statefulInterfaces : []`, and `ModuleListModel::data()`
allocates a brand-new `QVariantList` on every call, so any relevant
change is a full model-reference swap - `Repeater` (over a plain array,
unlike `ListView` over a real `QAbstractItemModel`) always destroys and
fully recreates every delegate on that, never mutates one in place. A
subscription is created and torn down exactly once per delegate
instance, never resubscribed out from under itself.

Verified live end-to-end using `scripts/screenshot_page.py Status
<out.png> --click "Expand all"` (see that script's own header for the
AT-SPI technique) against the `telescope` fixture plus this dev machine's
other already-running fixtures: badges, per-interface live state (real
`IWeather`/`IRunning`/... field values, not placeholders), and
`"<Interface> capabilities"` sections all rendered correctly, and
`--click "Collapse all"` afterward tore every subscription back down
cleanly (chevrons back to `▸`, no leaked `KeyValueCard`s, no QML
`TypeError`/binding-loop warnings in the log). One red herring while
checking that log: several *other* dummy modules (`autoguiding`,
`acquisition`, etc.) logged `"Could not subscribe to state node
pyobs:state:telescope:IPointingAltAz:1 after 30 attempts"` at the same
timestamp - initially alarming, but it's cross-module `pyobs-core`-side
chatter (those dummy modules apparently probe for a guiding-target
telescope on their own, independent of any GUI client) that lines up with
`telescope` having only just been started for this session, not
something this page's code could cause - every `subscribeState()` call
here is scoped to its own row's own `jid`, never another module's.

