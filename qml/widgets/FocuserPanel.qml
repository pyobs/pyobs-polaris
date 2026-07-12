import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Self-contained IFocuser widget - ports pyobs-gui's focuswidget.py:
// current focus/focus-offset readout plus Set focus/Set offset/Reset
// offset buttons (set_focus/set_focus_offset). IFocuser extends IMotion
// (confirmed against pyobs.interfaces.IFocuser source) - same "own
// IMotion subscription just to gate the buttons" shape as
// FiltersPanel.qml, see that file's own comment for why.
//
// Takes the host's own `statefulInterfaces` role list and does its own
// findInterface() lookups internally, same convention as FiltersPanel.qml.
//
// `moduleName`/`availableFilters` are unused here - declared anyway so
// every panel registered in SidebarPanelRegistry.qml shares one identical
// property contract; see that file's own doc comment for why.
GroupBox {
    id: root

    // Not `required` - see CoolingPanel.qml's own comment for why (loaded
    // dynamically via SidebarPanelRegistry.qml's Repeater, which can only
    // assign these properties *after* construction).
    property var xmppClient: null
    property string jid: ""
    property string moduleName: "" // unused - part of the shared panel contract
    property var statefulInterfaces: []
    property var availableFilters: [] // unused - part of the shared panel contract

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

    readonly property var interfaceInfo: root.findInterface("IFocuser")
    readonly property var motionInterfaceInfo: root.findInterface("IMotion")

    title: "Focuser"
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
                root.jid, "IFocuser", root.interfaceInfo.version, root)
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

    readonly property var currentFocus: fieldOf(root.state, "focus")
    readonly property var currentFocusOffset: fieldOf(root.state, "focus_offset")
    readonly property string motionStatus: fieldOf(root.motionState, "status") || ""
    readonly property bool motionReady: motionStatus === "slewing" || motionStatus === "tracking"
        || motionStatus === "idle" || motionStatus === "positioned"

    property bool running: false
    property string lastError: ""

    function run(action, params) {
        root.running = true
        root.lastError = ""
        root.xmppClient.executeMethod(root.jid, action, params, function (result) {
            if (!result.success) {
                root.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
            }
            root.running = false
        })
    }

    // "Was synced" idiom, same as CameraView.qml's Cooling setpoint/
    // TelescopeView.qml's offsets: only overwritten by a fresh server
    // push if it still shows the last value this widget last synced,
    // so an in-progress edit isn't clobbered by an unrelated update.
    property real lastSyncedFocus: NaN

    onCurrentFocusChanged: {
        if (root.currentFocus === undefined || root.currentFocus === null) {
            return
        }
        const wasSynced = isNaN(lastSyncedFocus) || Math.round(focusSpin.value) === Math.round(lastSyncedFocus * 1000)
        lastSyncedFocus = root.currentFocus
        if (wasSynced) {
            focusSpin.value = Math.round(root.currentFocus * 1000)
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Focus:" }
            Label {
                Layout.fillWidth: true
                text: (root.currentFocus !== undefined && root.currentFocus !== null)
                    ? root.currentFocus.toFixed(3) + " mm" : "-"
                color: "grey"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Offset:" }
            Label {
                Layout.fillWidth: true
                text: (root.currentFocusOffset !== undefined && root.currentFocusOffset !== null)
                    ? root.currentFocusOffset.toFixed(3) + " mm" : "-"
                color: "grey"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            SpinBox {
                id: focusSpin
                Layout.fillWidth: true
                from: -100000
                to: 100000
                editable: true
                textFromValue: (value) => (value / 1000).toFixed(3)
                valueFromText: (text) => Math.round(parseFloat(text) * 1000)
            }
            Label { text: "mm" }
        }

        Button {
            Layout.fillWidth: true
            text: "Set focus"
            // Matches focuswidget.py's own colorize_button() calls (green
            // Set focus/Set offset, yellow Reset offset) - see
            // TelescopeView.qml's Init/Park/Stop comment for the color
            // convention this project uses instead of pyobs-gui's own raw
            // Qt::GlobalColor + black text.
            palette.button: "#2e7d32"
            palette.buttonText: "white"
            enabled: !root.running && root.motionReady
            onClicked: root.run("set_focus", [focusSpin.value / 1000])
        }

        RowLayout {
            Layout.fillWidth: true
            SpinBox {
                id: offsetSpin
                Layout.fillWidth: true
                from: -100000
                to: 100000
                value: 0
                editable: true
                textFromValue: (value) => (value / 1000).toFixed(3)
                valueFromText: (text) => Math.round(parseFloat(text) * 1000)
            }
            Label { text: "mm" }
        }

        RowLayout {
            Layout.fillWidth: true
            Button {
                Layout.fillWidth: true
                text: "Set offset"
                palette.button: "#2e7d32"
                palette.buttonText: "white"
                enabled: !root.running && root.motionReady
                onClicked: root.run("set_focus_offset", [offsetSpin.value / 1000])
            }
            Button {
                Layout.fillWidth: true
                text: "Reset offset"
                palette.button: "#f9a825"
                palette.buttonText: "black"
                enabled: !root.running && root.motionReady
                onClicked: {
                    offsetSpin.value = 0
                    root.run("set_focus_offset", [0])
                }
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
