import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris
import "../widgets/WireValueFormat.js" as WireValueFormat

// Ports pyobs-gui's StatusWidget (statuswidget.py): a flat table of every
// connected module's name, version and live presence state (ready/error/
// local), with a one-click "Clear error" for modules currently in error.
// statuswidget.py itself is a QTreeWidget with expandable per-module rows
// (interfaces/capabilities/live state) - that generic drill-down used to
// live in DashboardView.qml (deliberately removed on direct request, see
// DEVELOPMENT.md's "Dashboard removed" section) and was left as "an open
// question for whenever that capability is actually needed again". Direct
// request answered that question: reintroduced here rather than
// resurrecting Dashboard, since this page is already the natural home.
// Ports DashboardView.vue's expand/collapse behavior exactly: collapsed by
// default, expanding a row's stateful interfaces mounts subscribeState()
// calls for just that row (ref-counted the same way RoofView.qml's own
// IMotion subscription is), collapsing tears them back down - so only
// rows actually being looked at ever hold a live PubSub subscription.
//
// The expanded content's own layout is a closer, later-requested port of
// statuswidget.py's actual `_add_module_details()` shape than the first
// pass here: one plain "Interfaces: ..." line, then one line per
// interface that has capabilities ("Capabilities (X): field=value, ..."),
// then one line per stateful interface ("State (X): field=value, ..."),
// each line a single row rather than a whole nested KeyValueCard table -
// direct request, "I like the overall design ... better in pyobs-gui".
// Colors are statuswidget.py's own _DARK_DETAIL_COLORS values (this app
// has no light/dark switching anywhere, see WireValueFormat.js's own
// comment on the same simplification).
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    // Ephemeral (in-memory only, not persisted across a restart) - which
    // module JIDs are currently expanded. A plain JS object used as a Set
    // (key presence = membership), always reassigned wholesale rather than
    // mutated in place: a QML binding that reads this property only
    // re-evaluates on property *reassignment*, not on mutating an already-
    // bound object in place.
    property var expandedJids: ({})

    function isExpanded(jid) {
        return root.expandedJids.hasOwnProperty(jid)
    }

    function toggleExpanded(jid) {
        const next = Object.assign({}, root.expandedJids)
        if (next.hasOwnProperty(jid)) {
            delete next[jid]
        } else {
            next[jid] = true
        }
        root.expandedJids = next
    }

    function expandAll() {
        const next = {}
        const jids = root.xmppClient.modules.jids()
        for (let i = 0; i < jids.length; ++i) {
            next[jids[i]] = true
        }
        root.expandedJids = next
    }

    function collapseAll() {
        root.expandedJids = ({})
    }

    function stateColor(state) {
        switch (state) {
        case "ready": return "limegreen"
        case "error": return "red"
        case "local": return "orange"
        default: return "grey"
        }
    }

    // statuswidget.py's own _DARK_DETAIL_COLORS entries for these three
    // detail-row categories (not named alongside WireValueFormat.js's
    // key/value/punctuation colors above: those are wire-*value* colors,
    // these are this page's own row-category colors).
    readonly property color interfacesLineColor: "#9aa0a6"
    readonly property color capabilitiesLineColor: "#8ab4f8"
    readonly property color stateLineColor: "#81c995"

    function formatInterfacesLine(list) {
        const names = []
        for (let i = 0; i < list.length; ++i) {
            names.push(WireValueFormat.escapeHtml(list[i].name) + ":" + list[i].version)
        }
        return WireValueFormat.span(root.interfacesLineColor, "Interfaces: " + names.join(", "))
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Status"
            font.bold: true
            font.pixelSize: 16
            Layout.fillWidth: true
        }

        Button {
            text: "Expand all"
            visible: listView.count > 0
            onClicked: root.expandAll()
        }
        Button {
            text: "Collapse all"
            visible: listView.count > 0
            onClicked: root.collapseAll()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Label { text: ""; Layout.preferredWidth: 16 }
        Label { text: "Module"; font.bold: true; Layout.preferredWidth: 160 }
        Label { text: "Version"; font.bold: true; Layout.preferredWidth: 90 }
        Label { text: "Status"; font.bold: true; Layout.fillWidth: true }
    }

    ListView {
        id: listView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.xmppClient.modules

        delegate: ColumnLayout {
            id: statusDelegate
            width: ListView.view.width
            spacing: 4

            required property string jid
            required property string name
            required property string version
            required property string presenceState
            required property string presenceError
            required property var interfaces
            required property var statefulInterfaces
            required property var capabilities

            readonly property bool expanded: root.isExpanded(jid)

            Item {
                id: headerRow
                Layout.fillWidth: true
                implicitHeight: headerContent.implicitHeight

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.toggleExpanded(statusDelegate.jid)
                }

                RowLayout {
                    id: headerContent
                    anchors.left: parent.left
                    anchors.right: parent.right

                    Label {
                        Layout.preferredWidth: 16
                        text: statusDelegate.expanded ? "▾" : "▸"
                        color: "grey"
                    }

                    Label {
                        Layout.preferredWidth: 160
                        text: statusDelegate.name
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.preferredWidth: 90
                        text: statusDelegate.version
                        color: "grey"
                    }

                    Rectangle {
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        radius: 6
                        color: root.stateColor(statusDelegate.presenceState)
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WrapAnywhere
                        text: statusDelegate.presenceState.toUpperCase()
                              + (statusDelegate.presenceError ? ": " + statusDelegate.presenceError : "")
                    }

                    Button {
                        text: "Clear error"
                        visible: statusDelegate.presenceState === "error"
                        onClicked: root.xmppClient.executeMethod(statusDelegate.jid, "reset_error", 0)
                    }
                }
            }

            ColumnLayout {
                id: expandedContent
                visible: statusDelegate.expanded
                Layout.fillWidth: true
                Layout.leftMargin: 24
                spacing: 4

                Label {
                    Layout.fillWidth: true
                    text: statusDelegate.jid
                    color: "grey"
                    font.pixelSize: 11
                }

                Label {
                    Layout.fillWidth: true
                    textFormat: Text.RichText
                    wrapMode: Text.WrapAnywhere
                    text: root.formatInterfacesLine(statusDelegate.interfaces)
                }

                Repeater {
                    id: capabilitiesRepeater
                    model: statusDelegate.expanded ? statusDelegate.capabilities : []

                    delegate: Label {
                        id: capsLine

                        // Not named "interface": that's a reserved word in
                        // QML/JS (ES future-reserved), and using it as a
                        // property name fails to parse.
                        required property string ifaceName
                        required property var value

                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        wrapMode: Text.WrapAnywhere
                        text: WireValueFormat.span(root.capabilitiesLineColor, "Capabilities (" + WireValueFormat.escapeHtml(capsLine.ifaceName) + "):")
                              + " " + WireValueFormat.formatDictInline(capsLine.value)
                    }
                }

                Repeater {
                    id: stateRepeater
                    model: statusDelegate.expanded ? statusDelegate.statefulInterfaces : []

                    delegate: Label {
                        id: stateLine

                        required property string name
                        required property int version

                        property var subscription: null

                        Component.onCompleted: {
                            stateLine.subscription = root.xmppClient.subscribeState(
                                statusDelegate.jid, stateLine.name, stateLine.version, stateLine)
                        }
                        Component.onDestruction: {
                            if (stateLine.subscription) {
                                stateLine.subscription.unsubscribe()
                            }
                        }

                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        wrapMode: Text.WrapAnywhere
                        text: WireValueFormat.span(root.stateLineColor, "State (" + WireValueFormat.escapeHtml(stateLine.name) + "):") + " "
                              + (stateLine.subscription && stateLine.subscription.value !== undefined && stateLine.subscription.value !== null
                                 ? WireValueFormat.formatDictInline(stateLine.subscription.value)
                                 : WireValueFormat.span(root.interfacesLineColor, "(no value yet)"))
                    }
                }
            }
        }
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        visible: listView.count === 0
        text: "No modules online."
        color: "grey"
        font.italic: true
    }
}
