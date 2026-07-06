import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-web-client's AppLayout.vue: a left sidebar nav (Dashboard,
// Shell, Logs) plus a main content area showing whichever page is
// selected - RouterView's equivalent here is a plain StackLayout, since
// this project has no separate routing concept.
ApplicationWindow {
    id: root
    width: 900
    height: 700
    title: "pyobs-gui++"

    Material.theme: Material.Dark

    required property var xmppClient

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
                text: "Dashboard"
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

            DashboardView {
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
        }
    }
}
