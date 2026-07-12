import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Self-contained IFilters widget - ports pyobs-gui's filterwidget.py:
// current filter readout, a combo of the filters IFilters capabilities
// declared, and a "Set" button (set_filter). IFilters extends IMotion
// (confirmed against pyobs.interfaces.IFilters source, same inheritance
// shape RoofView.qml's IRoof/IMotion split and CameraView.qml's
// ICamera/IExposure split already use) - subscribes to "IMotion"
// separately (own subscription, ref-counted the same way a page's own
// IMotion subscription would be if it has one) purely to gate "Set" on
// the device actually being initialized, matching filterwidget.py's own
// `initialized` check.
//
// Takes the host's own `statefulInterfaces` role list (not a pre-resolved
// interface) and does its own findInterface() lookups internally, same
// convention every custom widget in this codebase already uses - needed
// here specifically so the "IMotion" version comes from the module's
// real disco#info rather than being guessed/hardcoded.
//
// `moduleName` is unused here (TemperaturesPanel.qml's own plot-window
// title is the only consumer) - declared anyway so every panel registered
// in SidebarPanelRegistry.qml shares one identical property contract; see
// that file's own doc comment for why that matters.
GroupBox {
    id: root

    // Not `required` - see CoolingPanel.qml's own comment for why (loaded
    // dynamically via SidebarPanelRegistry.qml's Repeater, which can only
    // assign these properties *after* construction).
    property var xmppClient: null
    property string jid: ""
    property string moduleName: "" // unused - part of the shared panel contract
    property var statefulInterfaces: []
    property var availableFilters: [] // QVariantList of strings (ModuleListModel::FiltersRole)

    function findInterface(name) {
        const list = root.statefulInterfaces || []
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name === name) {
                return list[i]
            }
        }
        return null
    }

    function fieldOf(entries, key) {
        const list = entries || []
        for (let i = 0; i < list.length; ++i) {
            if (list[i].key === key) {
                return list[i].value
            }
        }
        return undefined
    }

    readonly property var interfaceInfo: root.findInterface("IFilters")
    readonly property var motionInterfaceInfo: root.findInterface("IMotion")

    title: "Filters"
    visible: root.interfaceInfo !== null

    property var subscription: null
    property var motionSubscription: null

    function refreshSubscriptions() {
        if (root.subscription) {
            root.subscription.unsubscribe()
            root.subscription = null
        }
        if (root.motionSubscription) {
            root.motionSubscription.unsubscribe()
            root.motionSubscription = null
        }
        if (root.visible && root.interfaceInfo) {
            root.subscription = root.xmppClient.subscribeState(
                root.jid, "IFilters", root.interfaceInfo.version, root)
        }
        if (root.visible && root.motionInterfaceInfo) {
            root.motionSubscription = root.xmppClient.subscribeState(
                root.jid, "IMotion", root.motionInterfaceInfo.version, root)
        }
    }

    onVisibleChanged: refreshSubscriptions()
    onInterfaceInfoChanged: refreshSubscriptions()
    onMotionInterfaceInfoChanged: refreshSubscriptions()
    Component.onCompleted: refreshSubscriptions()

    readonly property var state: root.subscription ? root.subscription.value : undefined
    readonly property var motionState: root.motionSubscription ? root.motionSubscription.value : undefined

    readonly property string currentFilter: fieldOf(root.state, "filter") || ""
    readonly property string motionStatus: fieldOf(root.motionState, "status") || ""
    // Same initialized-status set filterwidget.py's own update_gui() uses
    // (and every other custom widget here already does, e.g.
    // TelescopeView.qml's motionReady).
    readonly property bool motionReady: motionStatus === "slewing" || motionStatus === "tracking"
        || motionStatus === "idle" || motionStatus === "positioned"

    property bool running: false
    property string lastError: ""

    ColumnLayout {
        width: parent.width
        spacing: 6

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.currentFilter.length > 0 ? root.currentFilter : "-"
            font.bold: true
        }

        ComboBox {
            id: filterCombo
            Layout.fillWidth: true
            model: root.availableFilters
        }

        Button {
            Layout.fillWidth: true
            text: "Set filter"
            // Matches filterwidget.py's own colorize_button(buttonSetFilter,
            // green) - see TelescopeView.qml's Init/Park/Stop comment for
            // the color convention this project uses instead of pyobs-gui's
            // own raw Qt::GlobalColor + black text.
            palette.button: "#2e7d32"
            palette.buttonText: "white"
            enabled: !root.running && root.motionReady && filterCombo.currentText.length > 0
            onClicked: {
                root.running = true
                root.lastError = ""
                root.xmppClient.executeMethod(root.jid, "set_filter", [filterCombo.currentText], function (result) {
                    if (!result.success) {
                        root.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                    }
                    root.running = false
                })
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.lastError.length > 0
            text: root.lastError
            color: "red"
            wrapMode: Text.WrapAnywhere
        }
    }
}
