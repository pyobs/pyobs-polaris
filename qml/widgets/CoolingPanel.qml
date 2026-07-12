import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Self-contained ICooling widget - moved verbatim out of CameraView.qml's
// old inline third-column GroupBox once TelescopeView.qml's own sidebar
// needed the exact same "self-contained sidebar panel" shape as
// TemperaturesPanel.qml/FiltersPanel.qml/FocuserPanel.qml (see
// SidebarPanelRegistry.qml's own doc comment for the registry this now
// registers into). ICooling extends ITemperatures, not IMotion
// (confirmed against pyobs.interfaces.ICooling source) - unlike
// FiltersPanel.qml/FocuserPanel.qml, there's no separate motion-status
// gating here, matching this widget's original inline behavior exactly.
//
// One deliberate behavior change from the original inline version: errors
// now show in this panel's own inline Label instead of CameraView.qml's
// shared page-level error banner - consistent with every other sidebar
// panel already doing the same, and with each panel owning its own
// concerns independently of whichever page happens to embed it.
//
// Takes the host's own `statefulInterfaces`/`availableFilters` role lists
// (the latter unused here, kept only so every registered panel shares an
// identical property contract - see SidebarPanelRegistry.qml) and does
// its own findInterface() lookup internally, same convention as every
// other panel.
GroupBox {
    id: root

    // Not `required`, even though every registered panel is always
    // supposed to have all five set: SidebarPanelRegistry.qml's consuming
    // Repeater loads this via `Loader.sourceComponent` and assigns these
    // in `onLoaded` (i.e. *after* construction, since the values depend
    // on which per-module delegate is doing the loading) - a `required`
    // property must be satisfiable *during* construction, which a Loader
    // has no way to do, and fails hard ("Required property X was not
    // initialized", the panel silently never appearing) if declared that
    // way. Caught live, not by the build.
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

    readonly property var interfaceInfo: root.findInterface("ICooling")

    title: "Cooling"
    visible: root.interfaceInfo !== null

    property var subscription: null

    function refreshSubscription() {
        if (root.subscription) {
            root.subscription.unsubscribe()
            root.subscription = null
        }
        if (root.visible && root.interfaceInfo) {
            root.subscription = root.xmppClient.subscribeState(root.jid, "ICooling", root.interfaceInfo.version, root)
        }
    }

    onVisibleChanged: refreshSubscription()
    onInterfaceInfoChanged: refreshSubscription()
    Component.onCompleted: refreshSubscription()

    readonly property var state: root.subscription ? root.subscription.value : undefined

    readonly property bool currentEnabled: !!fieldOf(root.state, "enabled")
    readonly property var currentSetpoint: fieldOf(root.state, "setpoint")
    readonly property var currentPower: fieldOf(root.state, "power")

    property bool lastSyncedEnabled: false
    property real lastSyncedSetpoint: NaN
    property string lastError: ""

    onCurrentEnabledChanged: {
        const wasSynced = coolingCheck.checked === lastSyncedEnabled
        lastSyncedEnabled = currentEnabled
        if (wasSynced) {
            coolingCheck.checked = currentEnabled
        }
    }

    onCurrentSetpointChanged: {
        if (currentSetpoint === undefined || currentSetpoint === null) {
            return
        }
        const wasSynced = isNaN(lastSyncedSetpoint) || Math.round(setpointSpin.value) === Math.round(lastSyncedSetpoint * 10)
        lastSyncedSetpoint = currentSetpoint
        if (wasSynced) {
            setpointSpin.value = Math.round(currentSetpoint * 10)
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            CheckBox {
                id: coolingCheck
                text: "Enabled"
            }
            Item { Layout.fillWidth: true }
            Label {
                text: root.currentEnabled
                    ? (root.currentPower !== undefined && root.currentPower !== null ? root.currentPower + "%" : "")
                    : "OFF"
                color: "grey"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Setpoint:" }
            Label {
                text: root.currentEnabled && root.currentSetpoint !== undefined && root.currentSetpoint !== null
                    ? root.currentSetpoint.toFixed(1) + "°C" : "-"
                color: "grey"
            }
            Item { Layout.fillWidth: true }
            SpinBox {
                id: setpointSpin
                from: -1000
                to: 500
                editable: true
                textFromValue: (value) => (value / 10).toFixed(1)
                valueFromText: (text) => Math.round(parseFloat(text) * 10)
            }
            Label { text: "°C" }
        }

        Button {
            Layout.fillWidth: true
            text: "Apply"
            onClicked: {
                root.lastError = ""
                root.xmppClient.executeMethod(
                    root.jid, "set_cooling", [coolingCheck.checked, setpointSpin.value / 10],
                    function (result) {
                        if (!result.success) {
                            root.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                        }
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
