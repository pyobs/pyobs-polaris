# New page: all incoming events

Status: implemented, closed.

`qml/views/EventsView.qml`, ported from pyobs-gui's `eventswidget.py` - a
generic dump of every incoming event across all connected modules, not
just `LogEvent` (which `LogsView.qml`/`LogFooter.qml` already cover on
their own pages). Always visible in the sidebar's TOOLS group, after
Logs - not interface-gated, since events aren't module-type-specific the
way Roof/Auto Focus/etc. are. Sidebar/`StackLayout` indices for Roof/Auto
Focus/Acquisition/Auto Guiding shifted from 3-6 to 4-7 to make room.

`EventLogModel` (Phase 6) already logs every event centrally -
`entries()` (new `Q_INVOKABLE`, factored to share `toVariantMap()` with
the existing `entriesOfType()` rather than duplicate the per-entry
`QVariantMap` construction) is the unfiltered counterpart, same
`{type, module, timestamp, uuid, data}` shape. `LogEvent` itself is
excluded client-side (`EventsView.qml`'s own `refresh()`, `.filter(e =>
e.type !== "LogEvent")`), matching `eventswidget.py::_handle_event`'s own
explicit skip - confirmed live that this actually works, not just
assumed: triggering a real module command (`ITelescope.init()`) produces
both a fresh `LogEvent` (visible only in the Logs page/footer) and a
`MotionStatusChangedEvent` (visible only in this new page), at the same
moment, from the same module.

`data` (a `QVariantMap` crossing the C++/QML boundary) renders via
`JSON.stringify()`, same as `LogEvent`'s own fields already do in
`LogsView.qml` - confirmed live this also holds for a genuinely nested
payload (`MotionStatusChangedEvent`'s data includes a nested `interfaces`
dict, not just flat scalar fields like `LogEvent`), not only the flat
case already proven.

**First shipped with module/type filtering** (the same multi-select
checkbox `Flow` idiom `LogsView.qml`'s own filtering uses), **then
removed on direct request** - this page is meant as a flat, unfiltered
dump of everything, unlike the Logs page. Removing the filter `Flow`s
also surfaced a real layout bug, fixed at the same time: the `Type`
column had no `elide`, so a long event name (e.g.
`MotionStatusChangedEvent`) painted straight over the `Data` column
next to it - `RowLayout` doesn't clip siblings from each other, only
`ListView.clip` clips the whole delegate from the view's own edge.
Fixed with `elide: Text.ElideRight` (plus a wider `Layout.preferredWidth`
in place of the removed filter, and a small `font.bold` to keep it
scannable) instead of just widening the column further, since a
sufficiently long type name would always eventually recreate the
problem otherwise.

Live-verified end to end against two real running modules (`camera`,
`telescope`, already up from an unrelated session) rather than just
built: connected the app, confirmed the Events page and sidebar entry
render correctly with nothing yet received, then drove real RPC calls
(`ITelescope.init()`, `IOffsetsRaDec.set_offsets_radec()`) via a
throwaway script (this project's `ShellView` still can't send real
params yet - see the Shell TODO item - so a script was the only way to
exercise commands with real, non-null arguments) and confirmed the
resulting `MotionStatusChangedEvent`/`OffsetsRaDecEvent` appeared
correctly while the simultaneous `LogEvent`s correctly did not (same
`LogEvent`-exclusion check as the filtered version), then re-verified
after the filtering removal that the `Type` column no longer overlaps
`Data` for a real long event name. The page's default-route wiring
itself needed a temporary local edit to verify each time
(`StackLayout.currentIndex` briefly forced to the new page, since no
click-automation tool was available in this environment either - same
gap noted in `specs/design/logs-page-real-filtering.md`) - reverted before
committing both times, confirmed via a clean rebuild + full `ctest` pass
afterward.

