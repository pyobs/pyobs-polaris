import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

Window {
    width: 640
    height: 480
    visible: true
    title: "pyobs-gui++"

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
