import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-web-client's AppLayout.vue: a left sidebar nav (Status,
// then a "Tools" group - Shell/Logs - then a conditionally-visible
// "Modules" group for device-specific pages like Roof) plus a main
// content area showing whichever page is selected - RouterView's
// equivalent here is a plain StackLayout, since this project has no
// separate routing concept. Icon glyphs are plain Unicode characters
// (no bundled icon font/theme here, unlike the web client's Bootstrap
// Icons), chosen to read the same at a glance: a status dot, a
// terminal prompt, a lined page, a house.
ApplicationWindow {
    id: root
    width: 900
    height: 700
    title: "pyobs-gui++"

    Material.theme: Material.Dark

    // A sidebar entry: an icon glyph before the label, matching
    // AppLayout.vue's `d-flex align-items-center gap-2` links. Kept as an
    // inline component (Qt 6.5+) since it's only ever used within this
    // one file's sidebar, not a general-purpose widget.
    component SidebarItem: ItemDelegate {
        id: sidebarItem
        property string icon: ""

        Layout.fillWidth: true

        contentItem: RowLayout {
            spacing: 8

            Label {
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
                text: sidebarItem.icon
            }

            Label {
                Layout.fillWidth: true
                text: sidebarItem.text
                elide: Text.ElideRight
            }
        }
    }

    // Section header above a group of sidebar entries, matching
    // AppLayout.vue's small uppercase muted "Tools"/"Modules" labels -
    // callers pass the text already uppercased.
    component SidebarSectionLabel: Label {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.leftMargin: 12
        Layout.bottomMargin: 2
        color: "grey"
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1
    }

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

    // Vertical split between the normal nav+content area and a persistent
    // log tail docked below it on every page - ports pyobs-gui's
    // MainWindow (mainwindow.py's splitterLog, always showing tableLog
    // beneath the nav/content splitter regardless of which page is
    // selected).
    SplitView {
        anchors.fill: parent
        orientation: Qt.Vertical

        RowLayout {
            SplitView.fillHeight: true
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

                SidebarItem {
                    icon: "●"
                    text: "Status"
                    highlighted: stack.currentIndex === 0
                    onClicked: stack.currentIndex = 0
                }

                SidebarSectionLabel { text: "TOOLS" }

                SidebarItem {
                    icon: "❯"
                    text: "Shell"
                    highlighted: stack.currentIndex === 1
                    onClicked: stack.currentIndex = 1
                }

                SidebarItem {
                    icon: "▤"
                    text: "Logs"
                    highlighted: stack.currentIndex === 2
                    onClicked: stack.currentIndex = 2
                }

                SidebarSectionLabel {
                    text: "MODULES"
                    visible: root.hasRoofModule
                }

                SidebarItem {
                    icon: "⌂"
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

        LogFooter {
            SplitView.preferredHeight: 140
            SplitView.minimumHeight: 60
            xmppClient: root.xmppClient
        }
    }
}
