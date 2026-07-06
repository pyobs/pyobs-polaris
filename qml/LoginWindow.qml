import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Ports pyobs-web-client's LoginView.vue / App.vue's status-driven
// swap between LoginView and AppLayout - just as two literal top-level
// windows here rather than one page swapping its body, matching normal
// desktop-app conventions (a login window, then a separate main window).
ApplicationWindow {
    id: root
    width: 360
    height: 420
    title: "pyobs-gui++ - Sign in"

    Material.theme: Material.Dark

    required property var xmppClient

    onClosing: Qt.quit()

    ColumnLayout {
        anchors.centerIn: parent
        anchors.margins: 12
        width: 280
        spacing: 12

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "pyobs-gui++"
            font.bold: true
            font.pixelSize: 20
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "status: " + root.xmppClient.status
            color: "grey"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            visible: root.xmppClient.status === "error"
            color: "red"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            text: root.xmppClient.errorMessage
        }

        TextField {
            id: jidField
            Layout.fillWidth: true
            placeholderText: "JID (e.g. user@example.com)"
        }

        TextField {
            id: passwordField
            Layout.fillWidth: true
            placeholderText: "Password"
            echoMode: TextInput.Password
            onAccepted: connectButton.clicked()
        }

        CheckBox {
            Layout.fillWidth: true
            text: "Skip TLS certificate verification (insecure, dev only)"
            checked: root.xmppClient.insecureSkipTlsVerification
            onToggled: root.xmppClient.insecureSkipTlsVerification = checked

            contentItem: Label {
                text: parent.text
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
                leftPadding: parent.indicator.width + parent.spacing
            }
        }

        Button {
            id: connectButton
            Layout.fillWidth: true
            text: root.xmppClient.status === "connecting" ? "Connecting..." : "Connect"
            enabled: root.xmppClient.status !== "connecting" && jidField.text.length > 0 && passwordField.text.length > 0
            onClicked: root.xmppClient.connectToServer(jidField.text, passwordField.text)
        }
    }
}
