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
    }
}
