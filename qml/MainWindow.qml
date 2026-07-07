import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-web-client's AppLayout.vue: a left sidebar nav (Status,
// then a "Tools" group - Shell/Logs - then a conditionally-visible
// "Modules" group for device-specific pages like Roof/Auto Focus) plus a
// main content area showing whichever page is selected - RouterView's
// equivalent here is a plain StackLayout, since this project has no
// separate routing concept. Icon glyphs are plain Unicode characters
// (no bundled icon font/theme here, unlike the web client's Bootstrap
// Icons), chosen to read the same at a glance: a status dot, a
// terminal prompt, a lined page, a house, a focus-ring target.
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
        property string iconGlyph: ""

        Layout.fillWidth: true

        contentItem: RowLayout {
            spacing: 8

            Label {
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
                text: sidebarItem.iconGlyph
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

    // Gates the "Roof"/"Auto Focus"/"Acquisition" sidebar entries - only
    // relevant while a connected module actually implements the
    // interface. ModuleListModel::hasInterface() is a plain query, not a
    // live binding, so it's explicitly recomputed on every model change
    // rather than evaluated once.
    property bool hasRoofModule: xmppClient.modules.hasInterface("IRoof")
    property bool hasAutoFocusModule: xmppClient.modules.hasInterface("IAutoFocus")
    property bool hasAcquisitionModule: xmppClient.modules.hasInterface("IAcquisition")

    function refreshModuleGating() {
        root.hasRoofModule = root.xmppClient.modules.hasInterface("IRoof")
        root.hasAutoFocusModule = root.xmppClient.modules.hasInterface("IAutoFocus")
        root.hasAcquisitionModule = root.xmppClient.modules.hasInterface("IAcquisition")
    }

    Connections {
        target: xmppClient.modules
        function onRowsInserted() { root.refreshModuleGating() }
        function onRowsRemoved() { root.refreshModuleGating() }
        function onModelReset() { root.refreshModuleGating() }
        function onDataChanged() { root.refreshModuleGating() }
    }

    // The last IRoof/IAutoFocus/IAcquisition module can disconnect while
    // its page is open - jump back to Status rather than leaving the
    // sidebar highlighting a now-hidden entry.
    onHasRoofModuleChanged: {
        if (!hasRoofModule && stack.currentIndex === 3) {
            stack.currentIndex = 0
        }
    }
    onHasAutoFocusModuleChanged: {
        if (!hasAutoFocusModule && stack.currentIndex === 4) {
            stack.currentIndex = 0
        }
    }
    onHasAcquisitionModuleChanged: {
        if (!hasAcquisitionModule && stack.currentIndex === 5) {
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
                    iconGlyph: "●"
                    text: "Status"
                    highlighted: stack.currentIndex === 0
                    onClicked: stack.currentIndex = 0
                }

                SidebarSectionLabel { text: "TOOLS" }

                SidebarItem {
                    iconGlyph: "❯"
                    text: "Shell"
                    highlighted: stack.currentIndex === 1
                    onClicked: stack.currentIndex = 1
                }

                SidebarItem {
                    iconGlyph: "▤"
                    text: "Logs"
                    highlighted: stack.currentIndex === 2
                    onClicked: stack.currentIndex = 2
                }

                SidebarSectionLabel {
                    text: "MODULES"
                    visible: root.hasRoofModule || root.hasAutoFocusModule || root.hasAcquisitionModule
                }

                SidebarItem {
                    iconGlyph: "⌂"
                    text: "Roof"
                    visible: root.hasRoofModule
                    highlighted: stack.currentIndex === 3
                    onClicked: stack.currentIndex = 3
                }

                SidebarItem {
                    iconGlyph: "◎"
                    text: "Auto Focus"
                    visible: root.hasAutoFocusModule
                    highlighted: stack.currentIndex === 4
                    onClicked: stack.currentIndex = 4
                }

                SidebarItem {
                    iconGlyph: "⊕"
                    text: "Acquisition"
                    visible: root.hasAcquisitionModule
                    highlighted: stack.currentIndex === 5
                    onClicked: stack.currentIndex = 5
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

                AutoFocusView {
                    Layout.margins: 16
                    xmppClient: root.xmppClient
                }

                AcquisitionView {
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
