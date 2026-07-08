import QtQml

// TODO.md's "Plugin mechanism for custom module widgets", step 1: a
// registry mapping either an interface name or a module's bare jid to a
// widget entry {iconGlyph, label, component[, exclusive]} - so
// MainWindow.qml's sidebar/StackLayout can become generic Repeaters
// instead of one hand-written SidebarItem/page pair per widget. Built-in
// widgets register themselves once at startup (MainWindow.qml's own
// Component.onCompleted, today); step 2 will have loaded external .qml
// plugins register the same way, through the same two functions.
QtObject {
    id: root

    // Plain JS array, reassigned (never .push()ed in place) on every
    // registration so Repeaters bound directly to `entries` pick up each
    // new registration - a `property var` doesn't emit its change signal
    // for an in-place array mutation, only for a fresh assignment.
    //
    // Deliberately the *full, unfiltered* list of every registration ever
    // made, not just the ones currently backed by a connected module -
    // MainWindow.qml's sidebar/StackLayout Repeaters both iterate this
    // same array directly (not a connectivity-filtered subset) and toggle
    // per-entry `visible:` themselves via isVisible() below. Filtering the
    // *model* itself (as an earlier version of this file did) means each
    // widget's underlying Component doesn't get created until the exact
    // moment its registration first becomes visible - by which point the
    // module backing it may already carry a full data set, racing its own
    // internal per-module Repeater's initial bulk population against
    // other modules still concurrently connecting. That's precisely what
    // caused a real, live-caught bug (see MainWindow.qml's own note on
    // it): a second, spurious ModeView delegate for a module that should
    // only ever get one. Always instantiating every registered widget
    // eagerly at startup - exactly like every built-in widget already did
    // before this registry existed - sidesteps the race entirely: each
    // widget's own internal Repeater starts against an empty-or-early
    // model and grows one connection at a time, the same timing this
    // codebase's "delegates are updated in place, not recreated" idiom
    // (RoofView.qml et al.) already assumes everywhere else.
    property var entries: []

    // interfaceName: e.g. "IRoof" - the entry is visible whenever any
    // connected module implements it. entry: {iconGlyph, label, component}.
    function registerForInterface(interfaceName, entry) {
        root.entries = root.entries.concat([Object.assign({ interface: interfaceName }, entry)])
    }

    // jid: a specific module's bare jid, e.g. "roof@localhost" - the entry
    // is visible only while that exact module is connected, regardless of
    // which interfaces it implements. entry additionally supports
    // exclusive: true (see isVisible()'s own doc comment below).
    function registerForModule(jid, entry) {
        root.entries = root.entries.concat([Object.assign({ jid: jid }, entry)])
    }

    // Whether one registered `entry` should currently show in the sidebar,
    // against the currently-connected module set (`modules`, i.e.
    // xmppClient.modules) - the same gating the old per-widget hasXModule
    // booleans did (at least one connected module satisfies it).
    //
    // Resolution rule (decided during design discussion, TODO.md): if a
    // module matches both an interface-level and an exact-jid
    // registration, both show by default - composes, consistent with this
    // project's existing "two modules sharing IMode both render" behavior
    // (ModuleListModel/ModeView.qml). A jid-registration can set
    // exclusive: true to suppress the *interface-level* widget for that
    // one module specifically, for a bespoke module-specific widget
    // replacing the generic one.
    //
    // **Known gap, deliberately not wired up in step 1**: "suppress for
    // that one module" means the generic interface-level widget's own
    // internal per-module Repeater (RoofView.qml's etc.) would need to
    // skip that specific jid while still rendering every other matching
    // module - none of today's built-in widgets accept an exclusion list,
    // and retrofitting all five isn't "pure plumbing" (this step's own
    // scope, per TODO.md). Since no jid-level registration exists yet to
    // exercise this (all five built-ins register at the interface level
    // only), this only decides *slot*-level visibility (does the sidebar
    // entry/page count as "shown" at all, unaffected by exclusivity) -
    // actually filtering a widget's own rendering by it is step 2's job,
    // once a real exclusive registration exists to build/test it against.
    function isVisible(entry, modules) {
        return entry.jid !== undefined ? modules.hasModule(entry.jid) : modules.hasInterface(entry.interface)
    }
}
