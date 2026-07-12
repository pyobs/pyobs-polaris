import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Ports pyobs-web-client's LoggingView.vue. Note this filters to
// type === "LogEvent" specifically - unlike Phase 6's original
// all-event-types debug dump, the real "Logging" page only ever shows
// LogEvent entries (level/message/etc.), with a per-module filter and an
// auto-scroll toggle.
//
// Per-module filtering ports pyobs-gui's actual mainwindow.py/logmodel.py
// shape: a checkbox per known client (listClients, a QListWidget) feeding
// a QSortFilterProxyModel (LogModelProxy.filter_source) - multi-select
// show/hide, not the single-select "All modules"/one-module ComboBox this
// page had before. Deliberate divergence: listClients is populated from
// self.comm.clients (every currently-connected client) and is fully
// cleared/rebuilt on every client-list change, which resets any
// previously-unchecked filter back to checked - this page instead derives
// its module list from logEvents (same knownModules idiom already used
// here) and only ever appends newly-seen names, so a filter choice
// survives new modules connecting/disconnecting rather than silently
// resetting. Trade-off: a module only gets a checkbox once it has logged
// at least one entry this session, not the moment it connects.
//
// Minimum-level filtering has no equivalent in the Python reference at
// all (confirmed by reading mainwindow.py/logmodel.py - LogModelProxy
// only ever filters by sender) - added here anyway since this page
// already computes a level for coloring (levelColor()), so a threshold
// filter is nearly free and a common log-viewer expectation.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    // QAbstractListModel doesn't give QML/JS generic random-access
    // iteration for free (only Repeater/ListView-style delegate binding
    // does) - EventLogModel::entriesOfType() is the plain-JS-array escape
    // hatch for that, recomputed explicitly whenever the model changes
    // (rowsInserted on append, modelReset on clear) rather than via an
    // auto-tracked property binding.
    property var logEvents: []

    function refresh() {
        logEvents = root.xmppClient.events.entriesOfType("LogEvent")
    }

    Connections {
        target: root.xmppClient.events
        function onRowsInserted() { root.refresh() }
        function onModelReset() { root.refresh() }
    }

    Component.onCompleted: refresh()

    // Names unchecked in the module-filter Flow below - absence means
    // shown, matching listClients' "all checked by default" starting
    // state. A plain array, not a Set, since QML property bindings only
    // notify on reassignment either way - reassigned wholesale (concat/
    // filter) on every toggle rather than mutated in place.
    property var hiddenModules: []

    readonly property var knownModules: {
        const s = new Set(logEvents.map((e) => e.module))
        return [...s].sort()
    }

    readonly property var levels: ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
    property int minLevelIndex: 0 // index into levels; 0 = show everything

    readonly property var filteredEvents: logEvents.filter((e) => {
        if (root.hiddenModules.includes(e.module)) {
            return false
        }
        const idx = root.levels.indexOf((e.data.level ?? "").toUpperCase())
        return idx === -1 || idx >= root.minLevelIndex
    })

    function toggleModule(name, show) {
        if (show) {
            root.hiddenModules = root.hiddenModules.filter((m) => m !== name)
        } else if (!root.hiddenModules.includes(name)) {
            root.hiddenModules = root.hiddenModules.concat([name])
        }
    }

    function levelColor(level) {
        switch ((level ?? "").toUpperCase()) {
        case "DEBUG": return "grey"
        case "WARNING": return "orange"
        case "ERROR":
        case "CRITICAL": return "red"
        default: return "white"
        }
    }

    function formatTime(timestamp) {
        const d = new Date(timestamp * 1000)
        function pad(n) { return String(n).padStart(2, "0") }
        return pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds())
    }

    // Plain-text reproduction of one row, for the per-entry "Copy" button
    // below - same field order/formatting the row itself already
    // displays, just space-joined instead of column-aligned.
    function entryAsText(entry) {
        return root.formatTime(entry.timestamp) + " " + (entry.data.level ?? "").toUpperCase()
            + " " + entry.module + ": " + (entry.data.message ?? "")
    }

    // Hidden TextEdit is the standard QtQuick idiom for writing to the
    // system clipboard without pulling in Qt.labs.platform's Clipboard
    // singleton (a separate QML module this project doesn't otherwise
    // depend on, and isn't in CLAUDE.md's documented system-Qt6-package
    // prerequisites) - TextEdit.copy() already wraps QGuiApplication's
    // own clipboard, no extra import needed. invisible children are
    // already excluded from Layout arrangement (same behavior this
    // project's own SidebarColumn.qml collapse toggle already relies on),
    // so this doesn't need explicit zero-size Layout properties.
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function copyEntryToClipboard(entry) {
        clipboardHelper.text = root.entryAsText(entry)
        clipboardHelper.selectAll()
        clipboardHelper.copy()
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Logs"
            font.bold: true
            font.pixelSize: 16
        }

        Item { Layout.fillWidth: true }

        Label { text: "Min. level:" }

        ComboBox {
            model: ["ALL"].concat(root.levels)
            currentIndex: 0
            onActivated: root.minLevelIndex = currentIndex === 0 ? 0 : currentIndex - 1
        }

        Button {
            text: "Clear"
            onClicked: root.xmppClient.events.clear()
        }
    }

    Flow {
        Layout.fillWidth: true
        visible: root.knownModules.length > 0
        spacing: 12

        Repeater {
            model: root.knownModules

            delegate: CheckBox {
                required property string modelData

                text: modelData
                checked: !root.hiddenModules.includes(modelData)
                onToggled: root.toggleModule(modelData, checked)
            }
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.filteredEvents
        onCountChanged: positionViewAtEnd()

        // Item, not a bare RowLayout, as the delegate root - a right-click
        // "Copy" context menu needs a MouseArea sibling of the RowLayout
        // (not squeezed inside it as a layout cell, which would distort
        // the row), and MouseArea/Menu both need a plain Item to anchor
        // against. acceptedButtons: Qt.RightButton only, so this never
        // intercepts anything else the row itself might want (nothing
        // does today, but this doesn't foreclose it later).
        delegate: Item {
            id: logRow
            required property var modelData
            width: ListView.view.width
            height: rowLayout.implicitHeight

            RowLayout {
                id: rowLayout
                anchors.left: parent.left
                anchors.right: parent.right

                Label {
                    text: root.formatTime(logRow.modelData.timestamp)
                    color: "grey"
                    Layout.preferredWidth: 90
                }
                Label {
                    text: (logRow.modelData.data.level ?? "").toUpperCase()
                    color: root.levelColor(logRow.modelData.data.level)
                    Layout.preferredWidth: 70
                }
                Label {
                    text: logRow.modelData.module
                    color: "grey"
                    Layout.preferredWidth: 90
                }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: logRow.modelData.data.message ?? ""
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: contextMenu.popup()
            }

            Menu {
                id: contextMenu
                MenuItem {
                    text: "Copy"
                    onTriggered: root.copyEntryToClipboard(logRow.modelData)
                }
            }
        }
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        visible: root.filteredEvents.length === 0
        text: "No log events yet."
        color: "grey"
        font.italic: true
    }
}
