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

    // Bare JID + name list, populated automatically via presence + disco#info
    // (comm::XmppClient::handlePresence / probeRosterPresence) - no
    // interfaces/capabilities shown yet, that's Phase 4.
    ListView {
        anchors.top: loginColumn.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        clip: true
        model: xmppClient.modules
        delegate: ItemDelegate {
            width: ListView.view.width
            text: model.name + "  (" + model.jid + ")"
        }
    }
}
