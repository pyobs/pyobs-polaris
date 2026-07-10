import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// VFS endpoint configuration - ports the config half of pyobs-web-
// client's SettingsView.vue/useVfsConfig.ts (this project has no
// consumer of it yet, see TODO.md's "ICamera follow-up": comm::VfsClient
// exists and is live-verified, but nothing calls resolveVfsPath()+
// fetchFile() from a NewImageEvent until the FITS-decode/image-display
// widget lands). List-left/details-right, same idiom as
// LoginWindow.qml's account manager - vfsEndpoints is already scoped to
// the current session's bare JID (Main.qml binds
// VfsEndpointsModel.currentJid: xmppClient.jid), so this view never
// touches that itself.
ScrollView {
    id: root

    required property var xmppClient
    required property var vfsEndpoints
    required property var vfsClient

    clip: true

    // "" means the detail panel is in "new endpoint" mode.
    property string selectedEndpointId: ""
    property string keychainNotice: ""
    property string testResult: ""

    function selectEndpoint(id) {
        root.selectedEndpointId = id
        root.testResult = ""
        passwordField.text = ""

        if (id.length === 0) {
            rootField.text = ""
            baseUrlField.text = ""
            usernameField.text = ""
            storePasswordCheckBox.checked = false
            return
        }

        const endpoint = root.vfsEndpoints.endpointById(id)
        if (endpoint.root === undefined) {
            return
        }
        rootField.text = endpoint.root
        baseUrlField.text = endpoint.baseUrl
        usernameField.text = endpoint.username
        storePasswordCheckBox.checked = endpoint.hasStoredPassword
        if (storePasswordCheckBox.checked) {
            root.vfsEndpoints.loadPassword(id)
        }
    }

    Connections {
        target: root.vfsEndpoints
        function onPasswordReady(id, password) {
            if (id === root.selectedEndpointId) {
                passwordField.text = password
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

    Connections {
        target: root.vfsClient
        function onFileReady(requestId, data) {
            if (requestId !== "settings-test") {
                return
            }
            root.testResult = "OK - received " + data.length + " byte(s)"
        }
        function onFileFailed(requestId, errorMessage) {
            if (requestId !== "settings-test") {
                return
            }
            root.testResult = "Failed: " + errorMessage
        }
    }

    RowLayout {
        width: root.availableWidth
        height: Math.max(root.availableHeight, 400)
        spacing: 0

        ColumnLayout {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            spacing: 0

            Label {
                Layout.margins: 12
                text: "VFS Endpoints"
                font.bold: true
            }

            ListView {
                id: endpointListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.vfsEndpoints

                delegate: ItemDelegate {
                    width: endpointListView.width
                    highlighted: model.id === root.selectedEndpointId
                    text: model.root
                    onClicked: root.selectEndpoint(model.id)
                }
            }

            ItemDelegate {
                Layout.fillWidth: true
                text: "+ New endpoint"
                highlighted: root.selectedEndpointId.length === 0
                onClicked: root.selectEndpoint("")
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: "#2d3035" }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: "Maps a VFS root name (the first path segment of paths like grab_data()'s "
                    + "return value) to an HTTP base URL this client can fetch directly."
                color: "grey"
                wrapMode: Text.Wrap
            }

            Label {
                Layout.fillWidth: true
                visible: root.keychainNotice.length > 0
                color: "orange"
                wrapMode: Text.Wrap
                text: root.keychainNotice
            }

            TextField {
                id: rootField
                Layout.fillWidth: true
                placeholderText: "VFS root name (e.g. cache)"
            }

            TextField {
                id: baseUrlField
                Layout.fillWidth: true
                placeholderText: "Base URL (e.g. http://localhost:37075/)"
            }

            TextField {
                id: usernameField
                Layout.fillWidth: true
                placeholderText: "Username (optional)"
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: "Password (optional)"
                echoMode: TextInput.Password
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    text: root.selectedEndpointId.length === 0 ? "Save as new endpoint" : "Save changes"
                    enabled: rootField.text.length > 0 && baseUrlField.text.length > 0
                    onClicked: {
                        let id = root.selectedEndpointId
                        if (id.length === 0) {
                            id = root.vfsEndpoints.addEndpoint(rootField.text, baseUrlField.text, usernameField.text)
                            root.selectedEndpointId = id
                        } else {
                            root.vfsEndpoints.updateEndpoint(id, rootField.text, baseUrlField.text, usernameField.text)
                        }

                        if (storePasswordCheckBox.checked && passwordField.text.length > 0) {
                            root.vfsEndpoints.storePassword(id, passwordField.text)
                        } else if (!storePasswordCheckBox.checked) {
                            root.vfsEndpoints.clearStoredPassword(id)
                        }
                    }
                }

                Button {
                    text: "Delete"
                    visible: root.selectedEndpointId.length > 0
                    onClicked: {
                        root.vfsEndpoints.removeEndpoint(root.selectedEndpointId)
                        root.selectEndpoint("")
                    }
                }
            }

            // Fetches the base URL itself, not a real VFS file - there's
            // no filename to test against until a real grab_data() has
            // happened elsewhere. Proves reachability/auth wiring works
            // (any HTTP response, even a 404, distinguishes "the server
            // answered" from "connection refused/timed out") - see
            // DEVELOPMENT.md's VFS transport write-up.
            RowLayout {
                Layout.fillWidth: true
                visible: root.selectedEndpointId.length > 0
                spacing: 8

                Button {
                    text: "Test connection"
                    onClicked: {
                        root.testResult = "Testing..."
                        root.vfsClient.fetchFile("settings-test", baseUrlField.text, usernameField.text, passwordField.text)
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.testResult
                    wrapMode: Text.WrapAnywhere
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
