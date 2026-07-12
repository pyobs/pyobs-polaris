pragma Singleton
import QtQml

// General form of what CameraView.qml's/TelescopeView.qml's per-module
// sidebar column used to hand-wire directly (Cooling/Temperatures/
// Filters/Focuser, one hardcoded GroupBox-or-*Panel per interface): a
// registry mapping an interface name to a self-contained sidebar-panel
// Component, so a host page's sidebar becomes a generic Repeater instead
// of a growing list of hardcoded panel types - "widgets can decide
// whether they need a sidebar, and just add other widgets there" (direct
// request). Registered once at startup (MainWindow.qml's own
// Component.onCompleted, alongside WidgetRegistry's own registrations).
//
// Deliberately its own type, not a reuse of WidgetRegistry.qml, despite
// the superficial similarity - the two solve different problems.
// WidgetRegistry's entries are top-level sidebar-nav-entry/page pairs,
// each visible whenever *any* connected module satisfies it, and each
// widget's own internal Repeater iterates every module itself
// (RoofView.qml et al.). A sidebar panel here is the opposite shape: it's
// already being instantiated *inside* one specific module's own
// per-module delegate (cameraDelegate/telescopeDelegate), so there is no
// module-iteration or global-visibility concept to register - visibility
// is inherently "does *this* module implement the interface", which each
// panel already answers for itself (`visible: interfaceInfo !== null`,
// computed from its own `statefulInterfaces` binding). That's also why
// entries here carry no iconGlyph/label/exclusive - a sidebar panel isn't
// a navigation target, just a conditionally-visible chunk of UI.
//
// Every registered panel shares one identical property contract -
// xmppClient, jid, moduleName, statefulInterfaces, availableFilters -
// even though any given panel only reads some of them (see e.g.
// FocuserPanel.qml's own "unused - part of the shared panel contract"
// properties). That uniformity is what lets the consuming Repeater
// (CameraView.qml/TelescopeView.qml) set all five on every loaded panel
// generically, without needing to special-case which properties a
// particular registration's component actually cares about.
QtObject {
    id: root

    // Plain JS array, reassigned (never .push()ed in place) on every
    // registration - same "property var doesn't emit changed for an
    // in-place array mutation" reasoning as WidgetRegistry.qml's own
    // entries.
    property var entries: []

    // interfaceName: e.g. "ITemperatures" - used by the host page to
    // decide whether *any* registered panel applies to a given module (so
    // the sidebar column itself can collapse to nothing rather than
    // reserve empty horizontal space - see e.g. CameraView.qml's
    // hasAnySidebarPanel()), not for visibility of the individual panel
    // itself (each panel already re-derives that on its own, see the
    // class comment above). component: a Component whose root item
    // implements the shared property contract documented above.
    function registerPanel(interfaceName, component) {
        root.entries = root.entries.concat([{ interface: interfaceName, component: component }])
    }
}
