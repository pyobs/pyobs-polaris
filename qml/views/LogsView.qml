import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

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

        delegate: RowLayout {
            width: ListView.view.width

            required property var modelData

            Label {
                text: root.formatTime(modelData.timestamp)
                color: "grey"
                Layout.preferredWidth: 90
            }
            Label {
                text: (modelData.data.level ?? "").toUpperCase()
                color: root.levelColor(modelData.data.level)
                Layout.preferredWidth: 70
            }
            Label {
                text: modelData.module
                color: "grey"
                Layout.preferredWidth: 90
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: modelData.data.message ?? ""
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
