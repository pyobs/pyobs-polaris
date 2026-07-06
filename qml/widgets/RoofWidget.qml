import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Phase 7: pyobs-web-client's RoofView.vue, ported almost exactly. IRoof
// needs no custom UI of its own - it declares zero commands/state beyond
// what IMotion already provides (see DEVELOPMENT.md), so this widget is
// just KeyValueCard (Phase 4, for the module's IMotion state) plus three
// hand-designed buttons (Phase 5's executeMethod): Open (init), Close
// (park), Stop (stop_motion). Proves "generic by default, custom where it
// earns its place" alongside the still-fully-generic module list in
// Main.qml, not instead of it.
ColumnLayout {
    id: root

    required property var xmppClient

    Label {
        text: "Roof"
        font.bold: true
    }

    Label {
        Layout.fillWidth: true
        visible: repeater.count === 0
        text: "No IRoof modules online."
        color: "grey"
        font.italic: true
    }

    Repeater {
        id: repeater
        model: root.xmppClient.modules

        // This Repeater's model is the real ModuleListModel (a
        // QAbstractListModel), not a plain JS array like the nested
        // Repeater in Main.qml's generic list - Qt updates each
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

            KeyValueCard {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                value: roofDelegate.subscription ? roofDelegate.subscription.value : undefined
            }

            RowLayout {
                Button {
                    text: "Open"
                    enabled: roofDelegate.running === ""
                    onClicked: roofDelegate.run("init", 0)
                }
                Button {
                    text: "Close"
                    enabled: roofDelegate.running === ""
                    onClicked: roofDelegate.run("park", 0)
                }
                Button {
                    text: "Stop"
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
