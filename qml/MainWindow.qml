import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-web-client's AppLayout.vue: a left sidebar nav (Status,
// Shell, Logs, plus a conditionally-visible Roof entry) plus a main
// content area showing whichever page is selected - RouterView's
// equivalent here is a plain StackLayout, since this project has no
// separate routing concept.
ApplicationWindow {
    id: root
    width: 900
    height: 700
    title: "pyobs-gui++"

    Material.theme: Material.Dark

    required property var xmppClient

    // Gates the "Roof" sidebar entry - only relevant while a connected
    // module actually implements IRoof. ModuleListModel::hasInterface() is
    // a plain query, not a live binding, so it's explicitly recomputed on
    // every model change rather than evaluated once.
    property bool hasRoofModule: xmppClient.modules.hasInterface("IRoof")

    function refreshHasRoofModule() {
        root.hasRoofModule = root.xmppClient.modules.hasInterface("IRoof")
    }

    Connections {
        target: xmppClient.modules
        function onRowsInserted() { root.refreshHasRoofModule() }
        function onRowsRemoved() { root.refreshHasRoofModule() }
        function onModelReset() { root.refreshHasRoofModule() }
        function onDataChanged() { root.refreshHasRoofModule() }
    }

    // The last IRoof module can disconnect while its page is open - jump
    // back to Status rather than leaving the sidebar highlighting a
    // now-hidden entry.
    onHasRoofModuleChanged: {
        if (!hasRoofModule && stack.currentIndex === 3) {
            stack.currentIndex = 0
        }
    }

    onClosing: Qt.quit()

    RowLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout {
            Layout.preferredWidth: 180
            Layout.fillHeight: true
            spacing: 0

            Label {
                Layout.margins: 12
                text: "pyobs-gui++"
                font.bold: true
            }

            ItemDelegate {
                Layout.fillWidth: true
                text: "Status"
                highlighted: stack.currentIndex === 0
                onClicked: stack.currentIndex = 0
            }

            ItemDelegate {
                Layout.fillWidth: true
                text: "Shell"
                highlighted: stack.currentIndex === 1
                onClicked: stack.currentIndex = 1
            }

            ItemDelegate {
                Layout.fillWidth: true
                text: "Logs"
                highlighted: stack.currentIndex === 2
                onClicked: stack.currentIndex = 2
            }

            ItemDelegate {
                Layout.fillWidth: true
                text: "Roof"
                visible: root.hasRoofModule
                highlighted: stack.currentIndex === 3
                onClicked: stack.currentIndex = 3
            }

            Item { Layout.fillHeight: true }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2d3035" }

            ColumnLayout {
                Layout.margins: 12
                Layout.fillWidth: true
                spacing: 4

                Label {
                    Layout.fillWidth: true
                    text: root.xmppClient.jid
                    color: "grey"
                    elide: Text.ElideMiddle
                }

                Button {
                    Layout.fillWidth: true
                    text: "Sign out"
                    onClicked: root.xmppClient.disconnectFromServer()
                }
            }
        }

        Rectangle { Layout.fillHeight: true; width: 1; color: "#2d3035" }

        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 0

            StatusView {
                Layout.margins: 16
                xmppClient: root.xmppClient
            }

            ShellView {
                Layout.margins: 16
                xmppClient: root.xmppClient
            }

            LogsView {
                Layout.margins: 16
                xmppClient: root.xmppClient
            }

            RoofView {
                Layout.margins: 16
                xmppClient: root.xmppClient
            }
        }
    }
}
