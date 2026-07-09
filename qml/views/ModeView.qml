import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Dedicated page for IMode modules, ported from pyobs-gui's modewidget.py
// (ModeWidget) - see TODO.md. Only reachable via the sidebar while at
// least one connected module implements IMode (see MainWindow.qml's
// hasModeModule). One row per mode "group" the module reports via its
// static IMode capabilities (ModuleListModel::ModeGroupsRole) - a
// ComboBox per group, populated from that group's static option list,
// showing/setting the live current mode from IMode state
// (ModeState.modes, group name -> current mode). Controls stay disabled
// until IMotion state reaches the same "initialized" set
// modewidget.py::update_gui already uses.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    Label {
        text: "Mode"
        font.bold: true
        font.pixelSize: 16
    }

    Repeater {
        model: root.xmppClient.modules

        // Same in-place-update caveat as every other custom widget's
        // Repeater (RoofView.qml/AutoFocusView.qml/AutoGuidingView.qml):
        // this model is a real QAbstractListModel, so delegates are
        // updated in place rather than recreated - explicitly
        // unsubscribe/re-fetch rather than relying on bindings alone.
        delegate: ColumnLayout {
            id: modeDelegate
            Layout.fillWidth: true

            required property string jid
            required property string name
            required property var statefulInterfaces
            required property var modeGroups

            function findInterface(interfaceName) {
                const list = statefulInterfaces || []
                for (let i = 0; i < list.length; ++i) {
                    if (list[i].name === interfaceName) {
                        return list[i]
                    }
                }
                return null
            }

            // Same indexed-loop safety note as every other custom
            // widget's fieldOf() (see RoofView.qml/AutoFocusView.qml) -
            // only ever called on an already-reactive `property var`
            // capture, never directly inline on a subscription's
            // `.value`.
            function fieldOf(entries, key) {
                const list = entries || []
                for (let i = 0; i < list.length; ++i) {
                    if (list[i].key === key) {
                        return list[i].value
                    }
                }
                return undefined
            }

            readonly property var modeInterface: findInterface("IMode")
            readonly property var motionInterface: findInterface("IMotion")
            visible: modeInterface !== null

            property var modeSubscription: null
            property var motionSubscription: null

            function refreshSubscriptions() {
                if (modeSubscription) {
                    modeSubscription.unsubscribe()
                    modeSubscription = null
                }
                if (motionSubscription) {
                    motionSubscription.unsubscribe()
                    motionSubscription = null
                }
                if (visible && modeInterface) {
                    modeSubscription = root.xmppClient.subscribeState(
                        jid, "IMode", modeInterface.version, modeDelegate)
                }
                if (visible && motionInterface) {
                    motionSubscription = root.xmppClient.subscribeState(
                        jid, "IMotion", motionInterface.version, modeDelegate)
                }
            }

            onVisibleChanged: refreshSubscriptions()
            onModeInterfaceChanged: refreshSubscriptions()
            onMotionInterfaceChanged: refreshSubscriptions()
            Component.onCompleted: refreshSubscriptions()

            readonly property var modeState: modeSubscription ? modeSubscription.value : undefined
            readonly property var motionState: motionSubscription ? motionSubscription.value : undefined

            // dict[str, str] (group -> current mode), itself decoded as a
            // {key, value}-entry list the same way modeState/motionState
            // are - one more fieldOf() lookup per group below.
            readonly property var modesByGroup: fieldOf(modeState, "modes")

            readonly property string motionStatus: fieldOf(motionState, "status") || ""
            readonly property bool initialized: motionStatus === "slewing" || motionStatus === "tracking"
                || motionStatus === "idle" || motionStatus === "positioned"

            property string lastError: ""

            RowLayout {
                Label {
                    text: modeDelegate.name
                    font.bold: true
                }
                Label {
                    text: modeDelegate.jid
                    color: "grey"
                }
            }

            KeyValueCard {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                value: modeDelegate.motionState
            }

            Repeater {
                model: modeDelegate.modeGroups || []

                delegate: RowLayout {
                    id: groupRow
                    Layout.leftMargin: 8

                    required property string group
                    required property var modes

                    readonly property string currentMode: modeDelegate.fieldOf(modeDelegate.modesByGroup, group) || ""

                    // Live-editable idiom (AutoGuidingView.qml/
                    // AutoFocusView.qml's exposure-time SpinBoxes): only
                    // overwritten by a fresh server push if the combo box
                    // still shows the last value *this row* last synced
                    // from the server, so an in-progress user pick isn't
                    // clobbered by an unrelated state update.
                    property string lastSyncedMode: ""

                    onCurrentModeChanged: {
                        if (currentMode === "") {
                            return
                        }
                        const wasSynced = lastSyncedMode === "" || combo.currentText === lastSyncedMode
                        lastSyncedMode = currentMode
                        if (wasSynced) {
                            const idx = combo.indexOfValue(currentMode)
                            if (idx >= 0) {
                                combo.currentIndex = idx
                            }
                        }
                    }

                    Label {
                        Layout.preferredWidth: 90
                        text: groupRow.group
                    }

                    ComboBox {
                        id: combo
                        model: groupRow.modes || []
                        enabled: modeDelegate.initialized
                        onActivated: {
                            modeDelegate.lastError = ""
                            root.xmppClient.executeMethod(
                                modeDelegate.jid, "set_mode", [currentText, groupRow.group],
                                function (result) {
                                    if (!result.success) {
                                        modeDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                    }
                                })
                        }
                    }
                }
            }

            Label {
                Layout.leftMargin: 8
                Layout.fillWidth: true
                visible: modeDelegate.lastError.length > 0
                text: modeDelegate.lastError
                color: "red"
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    Item { Layout.fillHeight: true }
}
