# Plugin mechanism, step 1: internal widget registry

Status: implemented, closed.

`WidgetRegistry.qml` (new, plain `QtObject`) + `MainWindow.qml` changes
only - step 1 of TODO.md's "Plugin mechanism for custom module widgets"
item, no external `.qml` loading yet (that's step 2). Replaces
`MainWindow.qml`'s five hand-written `hasXModule` boolean/`SidebarItem`/
`StackLayout`-page triples (Roof/AutoFocus/Acquisition/AutoGuiding/Mode)
with a registry (`registerForInterface(name, entry)`/
`registerForModule(jid, entry)`, `entry: {iconGlyph, label, component[,
exclusive]}`) and two generic `Repeater`s (sidebar items, StackLayout
pages) driven by it. Built-ins register themselves once in
`Component.onCompleted`; a new `ModuleListModel::hasModule(bareJid)`
backs the jid-registration half the same "QML gets no generic
random-access iteration" way `hasInterface()` already does.

**A real, live-caught duplicate-rendering bug drove the final design, not
the first draft that compiled cleanly and looked right in isolation.**
First attempt: `widgetRegistry.visibleEntries(modules)` *filtered*
`entries` down to only the currently-connected ones, and both Repeaters
iterated that filtered result - meaning a widget's `Component` wasn't
even instantiated until its registration first became visible, by which
point the module backing it could already carry a full data set while
*other* modules were still concurrently connecting. Live-verified (real
ejabberd server, `mode`/`camera`/`telescope` all connecting within the
same couple of seconds, screenshotted via `spectacle -b -n` - this
machine's Wayland-session tool, same as the Acquisition widget's own
`RowLayout` bug write-up in `specs/design/custom-widget-iacquisition.md`) and caught a real defect: the "Mode" page
showed the exact same `mode@localhost` card **twice**. Bisected by
diffing against a build of the pre-refactor `MainWindow.qml` (confirmed
that version shows the card once, so this was newly introduced, not
latent) and by instrumenting both `refreshVisibleWidgets()` and
`ModeView.qml`'s own per-module delegate with temporary `console.log()`s
(removed before committing): exactly one `Loader`/`ModeView` *instance*
was created, but *that one instance's own* internal `Repeater { model:
xmppClient.modules }` created two delegates for the same jid - its
initial bulk population (the model already had rows by the time this
lazily-created widget finally came into existence) raced a `dataChanged`
for that same row from another module concurrently connecting elsewhere
in the shared model, and the duplicate delegate survived.

Two candidate fixes were tried in sequence, live-verified each time
(the first didn't actually work - recorded here since it's a real dead
end worth not repeating): reassigning `visibleWidgets` to a same-content
array on every redundant `dataChanged` was *also* real (confirmed via
the same `console.log()` instrumentation) and looked plausible as the
cause, but suppressing those redundant reassignments (comparing by
reference before writing) did **not** fix the duplicate - the race is in
the lazily-created widget's own *first* construction, not in how many
times it gets rebuilt afterward. The actual fix: stop filtering the
Repeaters' `model` by visibility at all. `widgetRegistry.entries` (the
full, unfiltered registration list) now backs both Repeaters directly,
so every registered widget is instantiated eagerly at startup - exactly
matching how all five built-ins already behaved *before* this registry
existed (`xmppClient.modules` starts empty, each widget's own internal
Repeater grows one connection at a time, never racing a concurrent
connection against its own construction). `WidgetRegistry.isVisible(entry,
modules)` now only toggles a parallel `visibilityByEntry` boolean array
used for each `SidebarItem`'s own `visible:` - it no longer controls
whether a `Component` exists at all. Confirmed fixed live, same
screenshot method, same three concurrently-connecting modules.

A second, independent bug surfaced by the same live check, before it ever
reached a screenshot: `registerForInterface()`/`registerForModule()`
originally used `entries.push(...)` - an in-place mutation of a `property
var` array, which does **not** emit that property's change signal in
QML. A `Repeater` bound directly to `entries` would never see any of the
five startup registrations at all. Fixed by reassigning
(`entries = entries.concat([...])`) instead - the same "plain array,
reassign don't mutate" discipline this project already uses elsewhere for
reactive `property var` arrays (e.g. `ShellView.qml`'s own `log`/
`history`).

**Resolution rule implemented, not fully wired up - a deliberate,
documented gap, not an oversight**: `WidgetRegistry.isVisible()`'s doc
comment covers this in full. In short, "a jid-registration can mark
`exclusive: true` to suppress the interface-level widget for that one
module" only ever affects registry-level *slot* visibility today, not a
generic widget's own internal per-module rendering (that would mean
retrofitting an exclusion list into every one of `RoofView.qml`/
`AutoFocusView.qml`/`AcquisitionView.qml`/`AutoGuidingView.qml`/
`ModeView.qml`'s internal `Repeater`s, well beyond this step's "pure
plumbing, no behavior change" scope) - moot for now anyway, since no
jid-level registration exists yet to exercise it. Revisit once step 2
lands a real one.

