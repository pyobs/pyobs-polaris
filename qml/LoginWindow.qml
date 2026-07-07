import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Ports pyobs-web-client's LoginView.vue / App.vue's status-driven
// swap between LoginView and AppLayout - just as two literal top-level
// windows here rather than one page swapping its body, matching normal
// desktop-app conventions (a login window, then a separate main window).
//
// List-left/details-right account manager, not a single form: saved
// accounts (SavedAccountsModel) are a separate concern from "connect
// right now" - the Connect button always just connects with whatever's
// currently in the fields, never implicitly saving anything. Saving/
// editing/deleting an account is a deliberate, separate action via the
// buttons below the fields. This is what makes "connect without storing
// credentials" the default, not a special case.
ApplicationWindow {
    id: root
    width: 640
    height: 640
    title: "pyobs-gui++ - Sign in"

    Material.theme: Material.Dark

    required property var xmppClient
    required property var accountsModel
    required property var appSettings

    // "" means the detail panel is in "new connection" mode (nothing
    // selected on the left).
    property string selectedAccountId: ""
    // Set by quickConnect() while waiting for that account's password to
    // load, so the passwordReady handler below knows to also connect
    // immediately instead of just prefilling the field.
    property string quickConnectPendingId: ""

    // Only set on a keychain failure (see the Connections below) - the
    // "Store password" checkbox promises the password goes into the
    // system keychain, so a failure there (no backend running, access
    // denied, ...) must be visible instead of just silently not storing.
    property string keychainNotice: ""

    onClosing: Qt.quit()

    function selectAccount(id) {
        root.selectedAccountId = id
        passwordField.text = ""

        if (id.length === 0) {
            jidField.text = ""
            labelField.text = ""
            storePasswordCheckBox.checked = false
            serverOverrideCheckBox.checked = false
            hostField.text = ""
            portField.text = ""
            root.xmppClient.insecureSkipTlsVerification = false
            return
        }

        const account = root.accountsModel.accountById(id)
        jidField.text = account.jid
        labelField.text = account.label
        storePasswordCheckBox.checked = account.hasStoredPassword
        serverOverrideCheckBox.checked = account.host.length > 0
        hostField.text = account.host
        portField.text = account.port > 0 ? String(account.port) : ""
        root.xmppClient.insecureSkipTlsVerification = account.insecureSkipTls
        if (account.hasStoredPassword) {
            root.accountsModel.loadPassword(id)
        }
    }

    // "" (skip DNS SRV lookup entirely) unless the override checkbox is on
    // - see XmppClient::connectToServer()'s doc comment for why this
    // exists at all.
    function overrideHost() {
        return serverOverrideCheckBox.checked ? hostField.text : ""
    }

    function overridePort() {
        return serverOverrideCheckBox.checked && portField.text.length > 0 ? parseInt(portField.text, 10) : 0
    }

    // The list row's own connect icon: true one-click reconnect for an
    // account with a stored password, without requiring select-then-
    // click-Connect via the detail panel.
    function quickConnect(id) {
        root.quickConnectPendingId = id
        root.selectAccount(id)
    }

    Component.onCompleted: {
        const lastId = root.appSettings.lastSelectedAccountId
        if (lastId.length > 0 && root.accountsModel.accountById(lastId).jid !== undefined) {
            root.selectAccount(lastId)
        }
    }

    Connections {
        target: accountsModel
        function onPasswordReady(id, password) {
            if (id !== root.selectedAccountId) {
                return
            }
            passwordField.text = password
            if (root.quickConnectPendingId === id) {
                root.quickConnectPendingId = ""
                root.xmppClient.connectToServer(jidField.text, password, root.overrideHost(), root.overridePort())
            }
        }
        function onPasswordLoadFailed(id) {
            if (root.quickConnectPendingId === id) {
                root.quickConnectPendingId = ""
            }
        }
        function onCredentialsSaveFailed(id) {
            root.keychainNotice = "Could not save the password to the system keychain."
        }
        function onCredentialsForgetFailed(id) {
            root.keychainNotice = "Could not remove the saved password from the system keychain."
        }
        function onCredentialsSaved(id) {
            root.keychainNotice = ""
        }
        function onCredentialsForgotten(id) {
            root.keychainNotice = ""
        }
    }

    // Only remembers which account was last used (to preselect it next
    // launch) - never saves/stores anything on its own. Saving is only
    // ever the explicit button below.
    Connections {
        target: xmppClient
        function onStatusChanged() {
            if (xmppClient.status === "connected") {
                root.appSettings.lastSelectedAccountId = root.selectedAccountId
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            spacing: 0

            Label {
                Layout.margins: 12
                text: "Accounts"
                font.bold: true
            }

            ListView {
                id: accountListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.accountsModel

                delegate: ItemDelegate {
                    width: accountListView.width
                    highlighted: model.id === root.selectedAccountId
                    onClicked: root.selectAccount(model.id)

                    contentItem: RowLayout {
                        spacing: 4

                        Label {
                            Layout.fillWidth: true
                            text: model.label.length > 0 ? model.label : model.jid
                            elide: Text.ElideRight
                        }

                        ToolButton {
                            text: "▶"
                            enabled: model.hasStoredPassword
                            ToolTip.visible: hovered
                            ToolTip.text: "Connect"
                            onClicked: root.quickConnect(model.id)
                        }
                    }
                }
            }

            ItemDelegate {
                Layout.fillWidth: true
                text: "+ New connection"
                highlighted: root.selectedAccountId.length === 0
                onClicked: root.selectAccount("")
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: "#2d3035" }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
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
                Layout.fillWidth: true
                visible: root.xmppClient.status === "error"
                color: "red"
                wrapMode: Text.Wrap
                text: root.xmppClient.errorMessage
            }

            Label {
                Layout.fillWidth: true
                visible: root.keychainNotice.length > 0
                color: "orange"
                wrapMode: Text.Wrap
                text: root.keychainNotice
            }

            TextField {
                id: jidField
                Layout.fillWidth: true
                placeholderText: "JID (e.g. user@example.com)"
            }

            TextField {
                id: labelField
                Layout.fillWidth: true
                placeholderText: "Label (optional, shown in the list)"
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
                id: storePasswordCheckBox
                Layout.fillWidth: true
                text: "Store password in system keychain"

                contentItem: Label {
                    text: parent.text
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: parent.indicator.width + parent.spacing
                }
            }

            CheckBox {
                id: serverOverrideCheckBox
                Layout.fillWidth: true
                text: "Override server address (skip DNS SRV lookup)"

                contentItem: Label {
                    text: parent.text
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: parent.indicator.width + parent.spacing
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: serverOverrideCheckBox.checked
                spacing: 8

                TextField {
                    id: hostField
                    Layout.fillWidth: true
                    placeholderText: "Host (e.g. monet.saao.ac.za)"
                }

                TextField {
                    id: portField
                    Layout.preferredWidth: 80
                    placeholderText: "5222"
                    validator: IntValidator { bottom: 1; top: 65535 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    text: root.selectedAccountId.length === 0 ? "Save as new account" : "Save changes"
                    enabled: jidField.text.length > 0
                    onClicked: {
                        let id = root.selectedAccountId
                        const host = root.overrideHost()
                        const port = root.overridePort()
                        const insecureSkipTls = root.xmppClient.insecureSkipTlsVerification
                        if (id.length === 0) {
                            id = root.accountsModel.addAccount(jidField.text, labelField.text, host, port, insecureSkipTls)
                            root.selectedAccountId = id
                        } else {
                            root.accountsModel.updateAccount(id, jidField.text, labelField.text, host, port, insecureSkipTls)
                        }

                        const account = root.accountsModel.accountById(id)
                        if (storePasswordCheckBox.checked && passwordField.text.length > 0) {
                            root.accountsModel.storePassword(id, passwordField.text)
                        } else if (!storePasswordCheckBox.checked && account.hasStoredPassword) {
                            root.accountsModel.clearStoredPassword(id)
                        }
                    }
                }

                Button {
                    text: "Delete"
                    visible: root.selectedAccountId.length > 0
                    onClicked: {
                        root.accountsModel.removeAccount(root.selectedAccountId)
                        root.selectAccount("")
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Button {
                id: connectButton
                Layout.fillWidth: true
                text: root.xmppClient.status === "connecting" ? "Connecting..." : "Connect"
                enabled: root.xmppClient.status !== "connecting" && jidField.text.length > 0 && passwordField.text.length > 0
                onClicked: root.xmppClient.connectToServer(jidField.text, passwordField.text, root.overrideHost(), root.overridePort())
            }
        }
    }
}
