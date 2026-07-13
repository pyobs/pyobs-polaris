import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Resizable, collapsible right-hand sidebar column - factors out what
// used to be near-identical, independently-duplicated code in
// CameraView.qml's third column and TelescopeView.qml's fourth column
// (the SidebarPanelRegistry-driven Repeater-of-Loader itself, unchanged
// here), now also carrying a drag handle + collapse toggle. Direct
// instructions: "add a splitter to adjust the right sidebar width",
// "maybe make it even fully collapsible", "the sidebar should have the
// same size over several widgets" - the last of these is why width/
// collapsed state live in AppSettings (persisted, one shared instance
// per CLAUDE.md's Main.qml) rather than as a local property here: every
// page using this component reads/writes the exact same
// appSettings.sidebarWidth/sidebarCollapsed, so resizing on the Camera
// page is immediately reflected on the Telescope page too, and survives
// a restart.
RowLayout {
    id: root
    spacing: 0

    required property var xmppClient
    required property var appSettings
    required property string jid
    required property string moduleName
    required property var statefulInterfaces
    required property var availableFilters
    required property var permittedMethods

    // Narrower than SidebarPanelRegistry's usual per-panel findInterface()
    // helpers (those live on each panel/delegate already) - this one only
    // needs to answer "is there anything to show at all", to gate this
    // whole column's (and its handle's) own visibility, mirroring the
    // hasAnySidebarPanel() check this replaces in CameraView.qml/
    // TelescopeView.qml.
    function hasAnyPanel() {
        const list = root.statefulInterfaces || []
        const entries = SidebarPanelRegistry.entries
        for (let i = 0; i < entries.length; ++i) {
            for (let j = 0; j < list.length; ++j) {
                if (list[j].name === entries[i].interface) {
                    return true
                }
            }
        }
        return false
    }

    function findInterface(name) {
        const list = root.statefulInterfaces || []
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name === name) {
                return list[i]
            }
        }
        return null
    }

    visible: root.hasAnyPanel()

    // Handle bar: always present whenever this column has anything to
    // show, even while collapsed, so there's always a way back in. The
    // top is the collapse/expand toggle - a real ToolButton (not a bare
    // Label+MouseArea) so it gets normal hover/press feedback and a real
    // accessible "push button" role/click action for free, consistent
    // with every other clickable control in this codebase (and with how
    // this project's own AT-SPI-driven live-verification scripts, e.g.
    // scripts/screenshot_page.py, discover and press buttons - a bare
    // Label+MouseArea exposes no AT-SPI action interface at all). The
    // rest of the bar below it is the drag-to-resize strip.
    ColumnLayout {
        Layout.fillHeight: true
        Layout.alignment: Qt.AlignTop
        spacing: 0

        ToolButton {
            Layout.alignment: Qt.AlignHCenter
            flat: true
            text: root.appSettings.sidebarCollapsed ? "‹" : "›"
            onClicked: root.appSettings.sidebarCollapsed = !root.appSettings.sidebarCollapsed
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.appSettings.sidebarCollapsed
            color: (dragArea.containsMouse || dragArea.pressed) ? palette.mid : "transparent"

            // Resizes appSettings.sidebarWidth by tracking the mouse in a
            // coordinate frame that doesn't move during the drag
            // (mapToItem(null, ...), i.e. the top-level Window) rather
            // than this MouseArea's own local `mouse.x` - this handle's
            // own on-screen position shifts as a direct side effect of
            // the resize itself (it sits right after the dominant,
            // Layout.fillWidth image/content column, which shrinks to
            // make room), so naive local-coordinate deltas would drift
            // and compound every frame instead of tracking the actual
            // mouse movement.
            MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor

                property real pressGlobalX: 0
                property real pressStartWidth: 0

                onPressed: (mouse) => {
                    pressGlobalX = dragArea.mapToItem(null, mouse.x, mouse.y).x
                    pressStartWidth = root.appSettings.sidebarWidth
                }
                onPositionChanged: (mouse) => {
                    if (!pressed) {
                        return
                    }
                    const globalX = dragArea.mapToItem(null, mouse.x, mouse.y).x
                    // The sidebar is the rightmost column - dragging the
                    // handle left (toward the content it's freeing up
                    // space from) grows the sidebar, dragging right
                    // shrinks it.
                    const delta = pressGlobalX - globalX
                    root.appSettings.sidebarWidth = Math.max(160, Math.min(480, pressStartWidth + delta))
                }
            }
        }
    }

    ColumnLayout {
        Layout.alignment: Qt.AlignTop
        Layout.preferredWidth: root.appSettings.sidebarWidth
        spacing: 8
        visible: !root.appSettings.sidebarCollapsed

        Repeater {
            model: SidebarPanelRegistry.entries

            // Same Loader-width/visible shape CameraView.qml's own third
            // column originally had inline - see DEVELOPMENT.md's
            // "SidebarPanelRegistry.qml follow-up" section for why both
            // of these bindings are needed rather than relying on
            // Loader's defaults.
            delegate: Loader {
                id: panelLoader
                Layout.fillWidth: true
                visible: root.findInterface(modelData.interface) !== null

                sourceComponent: modelData.component

                onLoaded: {
                    item.xmppClient = root.xmppClient
                    item.jid = root.jid
                    item.moduleName = root.moduleName
                    item.statefulInterfaces = Qt.binding(() => root.statefulInterfaces)
                    item.availableFilters = Qt.binding(() => root.availableFilters)
                    item.permittedMethods = Qt.binding(() => root.permittedMethods)
                    item.width = Qt.binding(() => panelLoader.width)
                }
            }
        }
    }
}
