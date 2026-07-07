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
    required property var appSettings

    // Only set on a keychain failure (see the Connections below) - the
    // "Remember me" checkbox promises the password goes into the system
    // keychain, so a failure there (no backend running, access denied,
    // ...) must be visible instead of just silently not remembering.
    property string keychainNotice: ""

    onClosing: Qt.quit()

    // Pre-fills the last remembered login (if any) and kicks off an async
    // keychain read for its password - see appSettings' own doc comment
    // for why the password never lives in the plain config file itself.
    Component.onCompleted: {
        if (appSettings.rememberLogin) {
            jidField.text = appSettings.lastJid
            rememberCheckBox.checked = true
            appSettings.loadSavedPassword()
        }
    }

    Connections {
        target: appSettings
        function onPasswordReady(password) {
            passwordField.text = password
        }
        function onCredentialsSaveFailed() {
            root.keychainNotice = "Could not save this login to the system keychain - it will not be remembered."
        }
        function onCredentialsForgetFailed() {
            root.keychainNotice = "Could not remove the saved login from the system keychain."
        }
        function onCredentialsSaved() {
            root.keychainNotice = ""
        }
        function onCredentialsForgotten() {
            root.keychainNotice = ""
        }
    }

    // Decides whether to remember or forget this login only once the
    // connection actually succeeds - never on a failed attempt, and never
    // just from typing/toggling the checkbox.
    Connections {
        target: xmppClient
        function onStatusChanged() {
            if (xmppClient.status !== "connected") {
                return
            }
            if (rememberCheckBox.checked) {
                appSettings.rememberCredentials(jidField.text, passwordField.text)
            } else if (appSettings.rememberLogin) {
                appSettings.forgetCredentials()
            }
        }
    }

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

        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            visible: root.keychainNotice.length > 0
            color: "orange"
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            text: root.keychainNotice
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

        CheckBox {
            id: rememberCheckBox
            Layout.fillWidth: true
            text: "Remember this login (password stored in system keychain)"

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
