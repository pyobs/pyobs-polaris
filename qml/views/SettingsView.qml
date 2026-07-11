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
    // Named settingsRoot, not root: VfsEndpointsModel::Role registers a
    // "root" role (the VFS root name, e.g. "cache") via roleNames(), and
    // QML auto-exposes every model role as a bare identifier inside a
    // ListView delegate's scope, not just via `model.<role>` - that bare
    // "root" shadows an outer `id: root` for any unqualified reference
    // written inside the endpoint-list delegate below. A real, previously
    // shipped bug caught live: the endpoint list's `onClicked:
    // root.selectEndpoint(...)` silently called `.selectEndpoint()` on
    // the role's *string value* instead, throwing a caught-and-logged
    // TypeError - clicking an endpoint appeared to do nothing at all. See
    // CLAUDE.md's own `Main.qml` id/property-shadowing gotcha for the
    // same family of trap.
    id: settingsRoot

    required property var xmppClient
    required property var vfsEndpoints
    required property var vfsClient

    clip: true

    // "" means the detail panel is in "new endpoint" mode.
    property string selectedEndpointId: ""
    property string keychainNotice: ""
    property string testResult: ""

    function selectEndpoint(id) {
        settingsRoot.selectedEndpointId = id
        settingsRoot.testResult = ""
        passwordField.text = ""

        if (id.length === 0) {
            rootField.text = ""
            baseUrlField.text = ""
            usernameField.text = ""
            storePasswordCheckBox.checked = false
            return
        }

        const endpoint = settingsRoot.vfsEndpoints.endpointById(id)
        if (endpoint.root === undefined) {
            return
        }
        rootField.text = endpoint.root
        baseUrlField.text = endpoint.baseUrl
        usernameField.text = endpoint.username
        storePasswordCheckBox.checked = endpoint.hasStoredPassword
        if (storePasswordCheckBox.checked) {
            settingsRoot.vfsEndpoints.loadPassword(id)
        }
    }

    Connections {
        target: settingsRoot.vfsEndpoints
        function onPasswordReady(id, password) {
            if (id === settingsRoot.selectedEndpointId) {
                passwordField.text = password
            }
        }
        function onCredentialsSaveFailed(id) {
            settingsRoot.keychainNotice = "Could not save the password to the system keychain."
        }
        function onCredentialsForgetFailed(id) {
            settingsRoot.keychainNotice = "Could not remove the saved password from the system keychain."
        }
        function onCredentialsSaved(id) {
            settingsRoot.keychainNotice = ""
        }
        function onCredentialsForgotten(id) {
            settingsRoot.keychainNotice = ""
        }
    }

    Connections {
        target: settingsRoot.vfsClient
        function onFileReady(requestId, data) {
            if (requestId !== "settings-test") {
                return
            }
            // /ping always 200s with a fixed {"status": "ok"} body -
            // reaching fileReady at all is the signal, no need to parse
            // the body (which arrives as an ArrayBuffer, not a JS string,
            // so JSON.parse() on it would need an extra decode step).
            settingsRoot.testResult = "OK - server is reachable"
        }
        function onFileFailed(requestId, errorMessage) {
            if (requestId !== "settings-test") {
                return
            }
            settingsRoot.testResult = "Failed: " + errorMessage
        }
    }

    RowLayout {
        width: settingsRoot.availableWidth
        height: Math.max(settingsRoot.availableHeight, 400)
        spacing: 0

        ColumnLayout {
            // Nested RowLayout/ColumnLayout children default
            // Layout.fillWidth to true (unlike plain Items/Controls,
            // which default to false) - without this explicit override,
            // this column silently claimed a share of the trailing
            // spacer's leftover space instead of staying at 220.
            Layout.fillWidth: false
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
                model: settingsRoot.vfsEndpoints

                delegate: ItemDelegate {
                    id: endpointDelegate
                    width: endpointListView.width
                    highlighted: model.id === settingsRoot.selectedEndpointId
                    text: model.root

                    // Gets Accessible.role ListItem by default even inside
                    // a real ListView, same as MainWindow.qml's sidebar
                    // ItemDelegates - the AT-SPI bridge doesn't synthesize
                    // a "Press" action for that role. See DEVELOPMENT.md's
                    // "AT-SPI-driven live verification" section.
                    Accessible.role: Accessible.Button
                    Accessible.onPressAction: endpointDelegate.clicked()

                    onClicked: settingsRoot.selectEndpoint(model.id)
                }
            }

            ItemDelegate {
                Layout.fillWidth: true
                text: "+ New endpoint"
                highlighted: settingsRoot.selectedEndpointId.length === 0
                onClicked: settingsRoot.selectEndpoint("")
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: "#2d3035" }

        ColumnLayout {
            // Fixed, not Layout.fillWidth - a form this narrow (five short
            // fields) reading edge-to-edge across the whole window is hard
            // to scan; leave the rest of the page blank instead of
            // stretching input fields to fill it.
            Layout.fillWidth: false
            Layout.preferredWidth: 420
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
                visible: settingsRoot.keychainNotice.length > 0
                color: "orange"
                wrapMode: Text.Wrap
                text: settingsRoot.keychainNotice
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label { text: "VFS root name" }
                TextField {
                    id: rootField
                    Layout.fillWidth: true
                    placeholderText: "e.g. cache"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label { text: "Base URL" }
                TextField {
                    id: baseUrlField
                    Layout.fillWidth: true
                    placeholderText: "e.g. http://localhost:37075/"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label { text: "Username" }
                TextField {
                    id: usernameField
                    Layout.fillWidth: true
                    placeholderText: "optional"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label { text: "Password" }
                TextField {
                    id: passwordField
                    Layout.fillWidth: true
                    placeholderText: "optional"
                    echoMode: TextInput.Password
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    text: settingsRoot.selectedEndpointId.length === 0 ? "Save as new endpoint" : "Save changes"
                    enabled: rootField.text.length > 0 && baseUrlField.text.length > 0
                    onClicked: {
                        let id = settingsRoot.selectedEndpointId
                        if (id.length === 0) {
                            id = settingsRoot.vfsEndpoints.addEndpoint(rootField.text, baseUrlField.text, usernameField.text)
                            settingsRoot.selectedEndpointId = id
                        } else {
                            settingsRoot.vfsEndpoints.updateEndpoint(id, rootField.text, baseUrlField.text, usernameField.text)
                        }

                        if (storePasswordCheckBox.checked && passwordField.text.length > 0) {
                            settingsRoot.vfsEndpoints.storePassword(id, passwordField.text)
                        } else if (!storePasswordCheckBox.checked) {
                            settingsRoot.vfsEndpoints.clearStoredPassword(id)
                        }
                    }
                }

                Button {
                    text: "Delete"
                    visible: settingsRoot.selectedEndpointId.length > 0
                    onClicked: {
                        settingsRoot.vfsEndpoints.removeEndpoint(settingsRoot.selectedEndpointId)
                        settingsRoot.selectEndpoint("")
                    }
                }
            }

            // Hits the server's /ping health-check endpoint (pyobs-core
            // >= 2.0.0.dev17's HttpFileCache/BaseVideo) rather than a real
            // VFS file - there's no filename to test against until a real
            // grab_data() has happened elsewhere, and /ping needs no auth
            // and always 200s, unlike the base URL itself (which 404s and
            // is reported as fileFailed the same as a refused connection -
            // see DEVELOPMENT.md's VFS transport write-up).
            RowLayout {
                Layout.fillWidth: true
                visible: settingsRoot.selectedEndpointId.length > 0
                spacing: 8

                Button {
                    text: "Test connection"
                    onClicked: {
                        settingsRoot.testResult = "Testing..."
                        let base = baseUrlField.text
                        if (!base.endsWith("/")) {
                            base += "/"
                        }
                        settingsRoot.vfsClient.fetchFile("settings-test", base + "ping", usernameField.text, passwordField.text)
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: settingsRoot.testResult
                    wrapMode: Text.WrapAnywhere
                }
            }

            Item { Layout.fillHeight: true }
        }

        // Absorbs whatever width is left over in the RowLayout: with
        // neither the endpoint list nor the form column set to
        // Layout.fillWidth, RowLayout redistributes the leftover space
        // onto them anyway rather than leaving it blank - an explicit
        // filler makes the leftover space go somewhere deterministic
        // instead of relying on that default.
        Item { Layout.fillWidth: true; Layout.fillHeight: true }
    }
}
