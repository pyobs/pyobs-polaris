import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-web-client's LoggingView.vue. Note this filters to
// type === "LogEvent" specifically - unlike Phase 6's original
// all-event-types debug dump, the real "Logging" page only ever shows
// LogEvent entries (level/message/etc.), with a per-module filter and an
// auto-scroll toggle.
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

    property string moduleFilter: ""

    readonly property var knownModules: {
        const s = new Set(logEvents.map((e) => e.module))
        return [...s].sort()
    }

    readonly property var filteredEvents: logEvents.filter(
        (e) => root.moduleFilter === "" || e.module === root.moduleFilter)

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

        ComboBox {
            model: [""].concat(root.knownModules)
            displayText: currentIndex === 0 ? "All modules" : currentText
            onActivated: root.moduleFilter = currentIndex === 0 ? "" : currentText
        }

        Button {
            text: "Clear"
            onClicked: root.xmppClient.events.clear()
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
