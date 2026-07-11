import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Dedicated page for IRoof modules, promoted from the former RoofWidget
// (previously embedded in the now-removed Dashboard) on direct request -
// only reachable via the sidebar while at least one connected module
// implements IRoof (see MainWindow.qml's hasRoofModule). IRoof declares
// zero commands/state beyond what IMotion already provides (see
// DEVELOPMENT.md) - no azimuth reading exists on the wire for this
// interface (confirmed from source, not an oversight), unlike
// roofwidget.ui's own labelAzimuth field, so there's nothing to port
// there. This page is a status readout plus three hand-designed buttons
// (executeMethod): Open (init), Close (park), Stop (stop_motion).
//
// Layout: one "Status" GroupBox wrapping status + the three buttons,
// ported from roofwidget.ui's own groupBox_2 (read directly), same
// GroupBox treatment as CameraView.qml/TelescopeView.qml. Button colors
// also read directly from that file's own per-button QPalette overrides
// - green Open, yellow Close, red Stop (not red Close/red Stop the way
// Camera's Expose/Abort split might suggest - Close isn't the
// destructive action here, Stop is).
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    Label {
        text: "Roof"
        font.bold: true
        font.pixelSize: 16
    }

    Repeater {
        model: root.xmppClient.modules

        // This Repeater's model is the real ModuleListModel (a
        // QAbstractListModel), not a plain JS array - Qt updates each
        // delegate's required role properties in place on dataChanged()
        // rather than destroying/recreating the whole delegate set. That
        // means a plain `property var subscription: <expression>` binding
        // here would silently leak an orphaned StateSubscription every
        // time the row updates (the binding re-runs, but nothing
        // destroys the previous one) - explicitly unsubscribe the old one
        // first, every time.
        delegate: ColumnLayout {
            id: roofDelegate
            Layout.fillWidth: true

            required property string jid
            required property string name
            required property var statefulInterfaces

            function findInterface(interfaceName) {
                const list = statefulInterfaces || []
                for (let i = 0; i < list.length; ++i) {
                    if (list[i].name === interfaceName) {
                        return list[i]
                    }
                }
                return null
            }

            readonly property var motionInterface: findInterface("IMotion")
            visible: findInterface("IRoof") !== null

            property var subscription: null

            function refreshSubscription() {
                if (subscription) {
                    subscription.unsubscribe()
                    subscription = null
                }
                if (visible && motionInterface) {
                    subscription = root.xmppClient.subscribeState(
                        jid, "IMotion", motionInterface.version, roofDelegate)
                }
            }

            onVisibleChanged: refreshSubscription()
            onMotionInterfaceChanged: refreshSubscription()
            Component.onCompleted: refreshSubscription()

            property string running: "" // action currently in flight, "" if none
            property string lastError: ""

            function run(action, paramCount) {
                roofDelegate.running = action
                roofDelegate.lastError = ""
                root.xmppClient.executeMethod(jid, action, paramCount, function (result) {
                    if (!result.success) {
                        roofDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                    }
                    roofDelegate.running = ""
                })
            }

            RowLayout {
                Label {
                    text: roofDelegate.name
                    font.bold: true
                }
                Label {
                    text: roofDelegate.jid
                    color: "grey"
                }
            }

            readonly property var motionState: roofDelegate.subscription ? roofDelegate.subscription.value : undefined

            function fieldOf(entries, key) {
                const list = entries || []
                for (let i = 0; i < list.length; ++i) {
                    if (list[i].key === key) {
                        return list[i].value
                    }
                }
                return undefined
            }

            readonly property string motionStatus: fieldOf(motionState, "status") || ""

            GroupBox {
                title: "Status"
                Layout.leftMargin: 8
                Layout.preferredWidth: 260

                ColumnLayout {
                    width: parent.width
                    spacing: 6

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: roofDelegate.motionStatus.toUpperCase()
                        font.bold: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            Layout.fillWidth: true
                            text: "Open"
                            palette.button: "#2e7d32"
                            palette.buttonText: "white"
                            enabled: roofDelegate.running === ""
                            onClicked: roofDelegate.run("init", 0)
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Close"
                            palette.button: "#f9a825"
                            palette.buttonText: "black"
                            enabled: roofDelegate.running === ""
                            onClicked: roofDelegate.run("park", 0)
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Stop"
                            palette.button: "#c62828"
                            palette.buttonText: "white"
                            enabled: roofDelegate.running === ""
                            onClicked: roofDelegate.run("stop_motion", 1)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: roofDelegate.lastError.length > 0
                        text: roofDelegate.lastError
                        color: "red"
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
