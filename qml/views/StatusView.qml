import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Ports pyobs-gui's StatusWidget (statuswidget.py): a flat table of every
// connected module's name, version and live presence state (ready/error/
// local), with a one-click "Clear error" for modules currently in error.
// statuswidget.py itself is a QTreeWidget with expandable per-module rows
// (interfaces/capabilities/live state) - that generic drill-down doesn't
// exist on this page. It used to live in DashboardView.qml, deliberately
// removed on direct request (see the "remove Dashboard" commit) as
// unwanted scope, not an oversight - nothing has picked it back up since.
// This page is intentionally just the "is everything OK" overview.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    function stateColor(state) {
        switch (state) {
        case "ready": return "limegreen"
        case "error": return "red"
        case "local": return "orange"
        default: return "grey"
        }
    }

    Label {
        text: "Status"
        font.bold: true
        font.pixelSize: 16
    }

    RowLayout {
        Layout.fillWidth: true
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

        delegate: RowLayout {
            id: statusDelegate
            width: ListView.view.width

            required property string jid
            required property string name
            required property string version
            required property string presenceState
            required property string presenceError

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

    Label {
        Layout.alignment: Qt.AlignHCenter
        visible: listView.count === 0
        text: "No modules online."
        color: "grey"
        font.italic: true
    }
}
