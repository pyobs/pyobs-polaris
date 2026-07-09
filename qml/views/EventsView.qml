import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Ports pyobs-gui's eventswidget.py: a generic dump of every incoming
// event across all connected modules, not just LogEvent (LogsView.qml/
// LogFooter.qml already cover that one type on their own pages). Always
// visible in the sidebar's TOOLS group, not interface-gated - events
// aren't module-type-specific the way Roof/Auto Focus/etc. are.
//
// EventLogModel (Phase 6) already logs every event centrally -
// entries() (added alongside this page) is the unfiltered counterpart to
// entriesOfType("LogEvent"), which LogsView.qml/LogFooter.qml already
// use. LogEvent itself is excluded client-side, same as
// eventswidget.py::_handle_event's own explicit skip - it fires often
// enough to drown out everything else in a generic view.
//
// No module/type filtering here (on direct instruction) - unlike
// LogsView.qml, this page is meant as a flat, unfiltered dump of
// everything.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    property var allEvents: []

    function refresh() {
        allEvents = root.xmppClient.events.entries().filter((e) => e.type !== "LogEvent")
    }

    Connections {
        target: root.xmppClient.events
        function onRowsInserted() { root.refresh() }
        function onModelReset() { root.refresh() }
    }

    Component.onCompleted: refresh()

    function formatTime(timestamp) {
        const d = new Date(timestamp * 1000)
        function pad(n) { return String(n).padStart(2, "0") }
        return pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds())
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Events"
            font.bold: true
            font.pixelSize: 16
        }

        Item { Layout.fillWidth: true }

        Button {
            text: "Clear"
            onClicked: root.xmppClient.events.clear()
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.allEvents
        onCountChanged: positionViewAtEnd()

        delegate: RowLayout {
            width: ListView.view.width
            spacing: 8

            required property var modelData

            Label {
                text: root.formatTime(modelData.timestamp)
                color: "grey"
                Layout.preferredWidth: 90
            }
            Label {
                text: modelData.module
                color: "grey"
                Layout.preferredWidth: 90
                elide: Text.ElideRight
            }
            Label {
                text: modelData.type
                font.bold: true
                Layout.preferredWidth: 180
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WrapAnywhere
                text: JSON.stringify(modelData.data)
                color: "grey"
            }
        }
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        visible: root.allEvents.length === 0
        text: "No events yet."
        color: "grey"
        font.italic: true
    }
}
