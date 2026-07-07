import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Persistent log tail docked below the main content on every page,
// ported from pyobs-gui's MainWindow (mainwindow.py's always-visible
// tableLog, below splitterNav in its own splitterLog pane). For now
// this is a deliberate duplicate of LogsView.qml's rendering (no
// per-module filter, no Clear button) - once LogsView.qml grows real
// filtering, this footer and that page are expected to diverge rather
// than share one component.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 4

    Rectangle { Layout.fillWidth: true; height: 1; color: "#2d3035" }

    // See LogsView.qml's identical comment: QAbstractListModel gives QML
    // no generic random-access iteration for free, so
    // EventLogModel::entriesOfType() is the escape hatch, recomputed
    // explicitly whenever the model changes rather than via an
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

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 4
        clip: true
        model: root.logEvents
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
        visible: root.logEvents.length === 0
        text: "No log events yet."
        color: "grey"
        font.italic: true
    }
}
