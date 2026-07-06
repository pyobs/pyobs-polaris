import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-web-client's DashboardView.vue: the fully generic module
// list (any interface, zero interface-specific code, see DEVELOPMENT.md
// Phase 3/4/5) plus RoofWidget (Phase 7) stacked above it - "generic by
// default, custom where it earns its place", both shown together rather
// than one replacing the other.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    Label {
        text: "Dashboard"
        font.bold: true
        font.pixelSize: 16
    }

    RoofWidget {
        Layout.fillWidth: true
        Layout.preferredHeight: 220
        xmppClient: root.xmppClient
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.xmppClient.modules
        delegate: ColumnLayout {
            id: moduleDelegate
            width: ListView.view.width
            spacing: 0

            required property string jid
            required property string name
            required property var statefulInterfaces
            required property var commands

            ItemDelegate {
                Layout.fillWidth: true
                text: moduleDelegate.name + "  (" + moduleDelegate.jid + ")"
                onClicked: moduleDelegate.expanded = !moduleDelegate.expanded
            }

            property bool expanded: false

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                visible: moduleDelegate.expanded

                // Gating the Repeater's model on `expanded` (rather than
                // just the child items' visibility) means subscribeState()
                // only runs while a row is actually expanded, and the
                // resulting StateSubscriptions - parented to each
                // interfaceBlock below - are destroyed (unsubscribing
                // automatically, see StateSubscription's destructor) the
                // moment the row collapses, not just hidden.
                Repeater {
                    model: moduleDelegate.expanded ? moduleDelegate.statefulInterfaces : []

                    delegate: ColumnLayout {
                        id: interfaceBlock
                        Layout.fillWidth: true

                        required property var modelData

                        // Evaluated once at delegate creation, not a live
                        // binding: subscribeState()'s arguments never change
                        // for this delegate's lifetime.
                        property var subscription: root.xmppClient.subscribeState(
                            moduleDelegate.jid, modelData.name, modelData.version, interfaceBlock)

                        Label {
                            text: interfaceBlock.modelData.name
                            font.bold: true
                        }

                        KeyValueCard {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            value: interfaceBlock.subscription ? interfaceBlock.subscription.value : undefined
                        }
                    }
                }

                // Phase 5 debug entry point: every param goes through as
                // null (see comm::XmppClient::executeMethod) - fine for
                // every real IRoof/IMotion command, whose params are all
                // declared optional. Result/fault goes to xmppClient's
                // lastRpcResult label above, not per-row here.
                Flow {
                    Layout.fillWidth: true

                    Repeater {
                        model: moduleDelegate.expanded ? moduleDelegate.commands : []

                        delegate: Button {
                            required property var modelData
                            text: modelData.interface + "." + modelData.name
                            onClicked: root.xmppClient.executeMethod(moduleDelegate.jid, modelData.name, modelData.paramCount)
                        }
                    }
                }
            }
        }
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        visible: root.xmppClient.lastRpcResult.length > 0
        text: root.xmppClient.lastRpcResult
        wrapMode: Text.WrapAnywhere
        Layout.preferredWidth: 280
    }
}
