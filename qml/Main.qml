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
        anchors.centerIn: parent
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

        // Phase 2 debug-only entry point: no presence-driven discovery yet
        // (that's Phase 3), so disco#info has to be triggered by hand to
        // prove the schema parse is correct. Result goes to the console
        // (qInfo(), see comm::logModuleInfo), not this UI.
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
}
