import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-web-client's ShellView.vue: pick a module, pick one of its
// commands, run it, see the result in a scrolling log - matching the
// reference's module -> method -> execute flow.
//
// Simplification, not yet ported: ShellView.vue also builds type-aware
// parameter widgets (bool/enum/number/string, reading each param's real
// WireType from CommandSchema) before executing. ModuleListModel's
// `commands` role only exposes {interface, name, paramCount} (see Phase
// 5) - not full per-param type/unit/enum schemas - so this port executes
// every command exactly like Phase 5/7's existing entry points already
// do: every param passed as null. Real parameter entry is a reasonable
// follow-up phase, not implemented here.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    property string selectedJid: ""
    property string selectedModuleName: ""

    property var log: [] // {timestamp, moduleName, iface, method, success, text}
    property bool running: false

    function selectModule(jid, name) {
        selectedJid = jid
        selectedModuleName = name
    }

    function pad(n) { return String(n).padStart(2, "0") }

    function formatTime(date) {
        return pad(date.getHours()) + ":" + pad(date.getMinutes()) + ":" + pad(date.getSeconds())
    }

    function formatResult(result) {
        if (result.success) {
            return result.errorMessage.length === 0 && result.errorClass.length === 0
                ? "success"
                : result.errorMessage
        }
        return (result.errorClass.length > 0 ? result.errorClass + ": " : "") + result.errorMessage
    }

    function execute(iface, name, paramCount) {
        root.running = true
        root.xmppClient.executeMethod(root.selectedJid, name, paramCount, function (result) {
            root.log = root.log.concat([{
                timestamp: root.formatTime(new Date()),
                moduleName: root.selectedModuleName,
                iface: iface,
                method: name,
                success: result.success,
                text: root.formatResult(result),
            }])
            root.running = false
        })
    }

    Label {
        text: "Shell"
        font.bold: true
        font.pixelSize: 16
    }

    // Command / reply log
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.log
        onCountChanged: positionViewAtEnd()

        delegate: ColumnLayout {
            width: ListView.view.width
            spacing: 0

            required property var modelData

            RowLayout {
                Label {
                    text: modelData.timestamp
                    color: "grey"
                }
                Label {
                    text: modelData.moduleName + ": " + modelData.iface + "." + modelData.method + "()"
                }
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                wrapMode: Text.Wrap
                color: modelData.success ? "lightgreen" : "red"
                text: modelData.text
            }
        }
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        visible: root.log.length === 0
        text: "No commands executed yet."
        color: "grey"
        font.italic: true
    }

    // Module picker
    Label {
        text: "Module"
        color: "grey"
        font.pixelSize: 11
    }

    Flow {
        Layout.fillWidth: true

        Repeater {
            model: root.xmppClient.modules

            delegate: Button {
                required property string jid
                required property string name

                text: name
                highlighted: root.selectedJid === jid
                onClicked: root.selectModule(jid, name)
            }
        }
    }

    // Method picker - one delegate per module row, self-filtered to the
    // selected one (same pattern RoofWidget.qml uses for its own
    // Repeater-over-real-model filtering).
    Label {
        text: "Method"
        color: "grey"
        font.pixelSize: 11
        visible: root.selectedJid.length > 0
    }

    Repeater {
        model: root.xmppClient.modules

        delegate: Flow {
            id: methodDelegate
            Layout.fillWidth: true
            visible: jid === root.selectedJid

            required property string jid
            required property var commands

            Repeater {
                model: methodDelegate.commands

                delegate: Button {
                    required property var modelData
                    enabled: !root.running
                    text: modelData.interface + "." + modelData.name
                    onClicked: root.execute(modelData.interface, modelData.name, modelData.paramCount)
                }
            }
        }
    }
}
