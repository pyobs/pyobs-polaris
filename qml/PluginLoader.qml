import QtQuick

// TODO.md's "Plugin mechanism for custom module widgets", step 2: loads
// external .qml files from a configurable directory
// (AppSettings::pluginsDirectory / pluginFiles()) at startup, and has each
// one register a widget into step 1's WidgetRegistry - the same way
// built-in widgets already do (just from outside this repo instead of
// from MainWindow.qml's own Component.onCompleted).
//
// Plugin file contract (see DEVELOPMENT.md's "Plugin mechanism, step 2"
// write-up for the full worked example and the reasoning behind it): a
// plugin .qml file's root type must be a plain QtObject exposing:
//   - `targetInterface` (string) XOR `targetJid` (string) - exactly one,
//     never both/neither - which of WidgetRegistry's two registration
//     kinds this is (registerForInterface() vs. registerForModule()).
//   - `iconGlyph` (string), `label` (string) - sidebar entry text.
//   - `exclusive` (bool, optional, only meaningful for a targetJid
//     registration) - see WidgetRegistry.qml's own doc comment on
//     isVisible() for what this does and does not affect yet.
//   - `widget` (Component) - the actual widget UI, instantiated later via
//     Loader exactly like a built-in widget's own Component (see
//     MainWindow.qml's roofComponent et al.) - can freely reference the
//     plugin root's own `xmppClient` property (below) via closure, since
//     it's declared within the same file.
//
// Each plugin root is instantiated with `xmppClient` bound to the app's
// real XmppClient - the exact same C++ context every built-in widget
// already gets (XmppClient exposes `modules`, `subscribeState()`,
// `executeMethod()` - everything a widget needs), not a narrower curated
// API invented just for plugins. No new native types are available to
// plugins beyond that - QML + inline JS only, same as any other QML file
// in this project (no Qt6::Widgets is linked here at all - see
// DEVELOPMENT.md's Phase 0 notes).
//
// Security note: this loads arbitrary local QML/JS with no sandboxing -
// acceptable for a user-supplied local plugins folder (the only thing
// AppSettings::pluginsDirectory can ever point at), not a mechanism for
// running untrusted/network-sourced plugin code.
QtObject {
    id: root

    required property var xmppClient
    required property var registry

    // `fileUrls`: AppSettings::pluginFiles()'s return value - already
    // file:// URL strings, one per *.qml file found. A malformed/errored
    // plugin file is logged and skipped, not fatal - one broken
    // third-party file shouldn't take the whole app down.
    function loadAll(fileUrls) {
        for (const fileUrl of fileUrls) {
            root.loadOne(fileUrl)
        }
    }

    function loadOne(fileUrl) {
        const component = Qt.createComponent(fileUrl)
        if (component.status === Component.Loading) {
            // Local file:// components load synchronously in practice,
            // but this is handled defensively rather than assumed.
            component.statusChanged.connect(() => root.finishLoading(component, fileUrl))
            return
        }
        root.finishLoading(component, fileUrl)
    }

    function finishLoading(component, fileUrl) {
        if (component.status === Component.Error) {
            console.warn("Plugin failed to load:", fileUrl, component.errorString())
            return
        }
        if (component.status !== Component.Ready) {
            return
        }

        const instance = component.createObject(root, { xmppClient: root.xmppClient })
        if (instance === null) {
            console.warn("Plugin failed to instantiate:", fileUrl)
            return
        }

        root.registerInstance(instance, fileUrl)
    }

    function registerInstance(instance, fileUrl) {
        const hasInterface = typeof instance.targetInterface === "string" && instance.targetInterface.length > 0
        const hasJid = typeof instance.targetJid === "string" && instance.targetJid.length > 0
        if (hasInterface === hasJid) {
            console.warn("Plugin must set exactly one of targetInterface/targetJid:", fileUrl)
            return
        }

        const entry = {
            iconGlyph: instance.iconGlyph || "",
            label: instance.label || "",
            component: instance.widget,
        }
        if (hasInterface) {
            root.registry.registerForInterface(instance.targetInterface, entry)
        } else {
            entry.exclusive = instance.exclusive === true
            root.registry.registerForModule(instance.targetJid, entry)
        }
    }
}
