import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

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
// Module/type filtering both use the same multi-select checkbox Flow
// idiom LogsView.qml settled on (not the single-select ComboBox
// originally sketched in TODO.md before that page's own filtering
// shipped) - consistent UI across both pages beats matching a stale plan.
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

    // Same "absence means shown, only ever append newly-seen names"
    // idiom as LogsView.qml's hiddenModules - see that file's own
    // comment for why (a filter choice should survive new modules/types
    // appearing, not silently reset).
    property var hiddenModules: []
    property var hiddenTypes: []

    readonly property var knownModules: {
        const s = new Set(allEvents.map((e) => e.module))
        return [...s].sort()
    }

    readonly property var knownTypes: {
        const s = new Set(allEvents.map((e) => e.type))
        return [...s].sort()
    }

    readonly property var filteredEvents: allEvents.filter(
        (e) => !root.hiddenModules.includes(e.module) && !root.hiddenTypes.includes(e.type))

    function toggle(list, name, show) {
        if (show) {
            return list.filter((m) => m !== name)
        } else if (!list.includes(name)) {
            return list.concat([name])
        }
        return list
    }

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

    Flow {
        Layout.fillWidth: true
        visible: root.knownTypes.length > 0
        spacing: 12

        Label { text: "Type:" }

        Repeater {
            model: root.knownTypes

            delegate: CheckBox {
                required property string modelData

                text: modelData
                checked: !root.hiddenTypes.includes(modelData)
                onToggled: root.hiddenTypes = root.toggle(root.hiddenTypes, modelData, checked)
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        visible: root.knownModules.length > 0
        spacing: 12

        Label { text: "Module:" }

        Repeater {
            model: root.knownModules

            delegate: CheckBox {
                required property string modelData

                text: modelData
                checked: !root.hiddenModules.includes(modelData)
                onToggled: root.hiddenModules = root.toggle(root.hiddenModules, modelData, checked)
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
                text: modelData.module
                color: "grey"
                Layout.preferredWidth: 90
            }
            Label {
                text: modelData.type
                Layout.preferredWidth: 140
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
        visible: root.filteredEvents.length === 0
        text: "No events yet."
        color: "grey"
        font.italic: true
    }
}
