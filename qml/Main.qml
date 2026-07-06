import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import pyobs.gui

ApplicationWindow {
    width: 640
    height: 480
    visible: true
    title: "pyobs-gui++"

    // Explicit, not ambient: relying on the system palette is what caused
    // light-on-light/dark-on-dark contrast bugs here in the first place
    // (Controls picked up the desktop's dark theme while the plain Window
    // background stayed hardcoded white). Force dark mode deliberately.
    Material.theme: Material.Dark

    XmppClient {
        id: xmppClient
    }

    ColumnLayout {
        id: loginColumn
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: 12
        spacing: 12

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "status: " + xmppClient.status
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: xmppClient.status === "error"
            color: "red"
            text: xmppClient.errorMessage
        }

        TextField {
            id: jidField
            Layout.preferredWidth: 280
            placeholderText: "JID (e.g. user@example.com)"
        }

        TextField {
            id: passwordField
            Layout.preferredWidth: 280
            placeholderText: "Password"
            echoMode: TextInput.Password
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Connect"
            enabled: xmppClient.status !== "connecting"
            onClicked: xmppClient.connectToServer(jidField.text, passwordField.text)
        }

        CheckBox {
            Layout.alignment: Qt.AlignHCenter
            text: "Skip TLS certificate verification (insecure, dev only)"
            checked: xmppClient.insecureSkipTlsVerification
            onToggled: xmppClient.insecureSkipTlsVerification = checked
        }

        // Manual override, kept from Phase 2: still useful for testing a
        // JID by hand. Live modules now populate the ListView below on
        // their own via presence (Phase 3) - this isn't the only way to
        // reach fetchModuleInfo() anymore.
        TextField {
            id: discoveryJidField
            Layout.preferredWidth: 280
            placeholderText: "Module bare JID (e.g. telescope@localhost)"
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Fetch module info (debug, see console)"
            enabled: xmppClient.status === "connected" && discoveryJidField.text.length > 0
            onClicked: xmppClient.fetchModuleInfo(discoveryJidField.text, discoveryJidField.text + "/pyobs")
        }
    }

    // Module list, populated automatically via presence + disco#info
    // (comm::XmppClient::handlePresence / probeRosterPresence, Phase 3).
    // Expanding a row subscribes (Phase 4) to every interface that has a
    // state block and renders it generically via KeyValueCard - zero
    // interface-specific code, matches ModuleStateCard.vue's role.
    ListView {
        anchors.top: loginColumn.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        clip: true
        model: xmppClient.modules
        delegate: ColumnLayout {
            id: moduleDelegate
            width: ListView.view.width
            spacing: 0

            required property string jid
            required property string name
            required property var statefulInterfaces

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
                        property var subscription: xmppClient.subscribeState(
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
            }
        }
    }
}
