import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Ports pyobs-gui's ShellWidget/CommandInputWidget/pyobs.utils.shellcommand.
// ShellCommand: a single-line command prompt (`module.command(arg1, arg2,
// ...)` syntax, typed and executed like a shell) with Up/Down command
// history - not pyobs-web-client's ShellView.vue module-picker-then-method-
// picker-then-click UI the previous version of this file ported (see
// TODO.md's Shell item: the plan changed on direct instruction, replacing
// that UI wholesale rather than extending it).
//
// Parsing/dispatch is entirely XmppClient::executeShellCommand()
// (shell::ShellCommandParser + ModuleListModel::jidForModuleName() + the
// existing real-param executeMethod() overload) - this page is just the
// prompt, history, and result log around it, no parsing/matching logic
// here.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    property var log: [] // {timestamp, commandText, success, text}
    property var history: [] // typed command strings, oldest first, this session only
    property int historyIndex: -1 // -1 means "not currently browsing history"
    property bool running: false

    // Autocomplete popup (TODO.md's Shell item, step 4) - allCommands is a
    // flat {module, name, params} list across every connected module
    // (ModuleListModel::allCommands(), refreshed the same "call it again on
    // every rowsInserted/rowsRemoved/modelReset/dataChanged" way
    // AutoFocusView.qml's own refreshFocusFoundEvents() refreshes its own
    // Q_INVOKABLE-sourced array), filtered locally as the user types - same
    // "plain array + filter()" idiom LogsView.qml/EventsView.qml already
    // use, not a new pattern.
    property var allCommands: []

    function refreshAllCommands() {
        root.allCommands = root.xmppClient.modules.allCommands()
    }

    function formatParam(param) {
        return param.name + ": " + param.type + (param.optional ? "?" : "")
            + (param.unit.length > 0 ? " [" + param.unit + "]" : "")
    }

    // "module.command(param: type, ...)" - no doc/description column: this
    // project's CommandSchema has no equivalent field to pyobs-gui's own
    // popup's docstring column (see TODO.md's Shell item, step 4 - confirmed
    // gap, not fixable from the wire alone).
    function formatSignature(entry) {
        return entry.module + "." + entry.name + "(" + entry.params.map(root.formatParam).join(", ") + ")"
    }

    // True once the user has typed "(" - meaning they've committed to a
    // specific command and moved on to entering its params, so there's
    // nothing left to suggest. Checked explicitly, not inferred from
    // filteredCommands being empty: the just-completed command's own
    // "module.command" text still matches itself via startsWith below, so
    // without this check the popup would never close after a selection (or
    // after manually typing a full command) - Enter would then keep
    // re-completing the same suggestion instead of ever executing it.
    readonly property bool hasOpenParen: commandField.text.indexOf("(") !== -1

    readonly property var filteredCommands: {
        if (root.hasOpenParen || commandField.text.length === 0) {
            return []
        }
        return root.allCommands.filter((c) => (c.module + "." + c.name).startsWith(commandField.text))
    }

    // Which popup row Up/Down has currently highlighted, -1 meaning none.
    // Reset to the top match whenever the candidate list itself changes
    // (new keystroke), not left dangling on an index that may no longer
    // exist or no longer make sense for the new filter text.
    property int highlightedIndex: -1
    onFilteredCommandsChanged: root.highlightedIndex = root.filteredCommands.length > 0 ? 0 : -1

    // Fills in "module.command(" (or the fully-closed "module.command()"
    // when it takes no args) and hands focus back to the field -
    // filteredCommands then recomputes to [] on its own (the text now
    // contains "("), which is what actually hides the popup. Shared by the
    // popup's own mouse click and Enter-while-a-suggestion-is-highlighted.
    function selectSuggestion(entry) {
        const prefix = entry.module + "." + entry.name + "("
        commandField.text = entry.params.length === 0 ? prefix + ")" : prefix
        commandField.cursorPosition = commandField.text.length
        commandField.forceActiveFocus()
    }

    Connections {
        target: root.xmppClient.modules
        function onRowsInserted() { root.refreshAllCommands() }
        function onRowsRemoved() { root.refreshAllCommands() }
        function onModelReset() { root.refreshAllCommands() }
        function onDataChanged() { root.refreshAllCommands() }
    }

    Component.onCompleted: root.refreshAllCommands()

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

    function execute(commandText) {
        root.running = true
        root.xmppClient.executeShellCommand(commandText, function (result) {
            root.log = root.log.concat([{
                timestamp: root.formatTime(new Date()),
                commandText: commandText,
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

    // Command / reply log - same scrolling, success-green/error-red
    // rendering the module-picker version of this page already had
    // (ShellCommandResponse.color: lime/red), just keyed off the typed
    // command line instead of a picked interface/method pair.
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
                    text: "$ " + modelData.commandText
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

    // Command prompt - module.command(arg1, arg2, ...). Enter parses and
    // executes it, then clears the field; Up/Down cycle this session's
    // command history (a plain in-memory array, not persisted across
    // restarts - matches pyobs-gui's own CommandInputWidget).
    TextField {
        id: commandField
        Layout.fillWidth: true
        focus: true
        enabled: !root.running
        selectByMouse: true
        placeholderText: "module.command(arg1, arg2, ...)"
        font.family: "monospace"

        Keys.onReturnPressed: {
            // A highlighted popup suggestion takes Enter first - completes
            // it into the field rather than executing the (as-yet
            // incomplete) typed text, same as any other autocomplete
            // widget. A second Enter, once the popup has closed itself
            // (filteredCommands empties once "(" is in the text), runs it.
            if (commandPopup.visible && root.highlightedIndex >= 0) {
                root.selectSuggestion(root.filteredCommands[root.highlightedIndex])
                return
            }
            const text = commandField.text.trim()
            if (text.length === 0) {
                return
            }
            root.history = root.history.concat([text])
            root.historyIndex = -1
            root.execute(text)
            commandField.text = ""
        }

        // While the popup is showing suggestions, Up/Down move the
        // highlighted row instead of cycling command history - history
        // browsing resumes once there are no suggestions to navigate.
        Keys.onUpPressed: {
            if (commandPopup.visible) {
                root.highlightedIndex = Math.max(0, root.highlightedIndex - 1)
                return
            }
            if (root.history.length === 0) {
                return
            }
            const next = root.historyIndex === -1
                ? root.history.length - 1
                : Math.max(0, root.historyIndex - 1)
            root.historyIndex = next
            commandField.text = root.history[next]
        }

        Keys.onDownPressed: {
            if (commandPopup.visible) {
                root.highlightedIndex = Math.min(root.filteredCommands.length - 1, root.highlightedIndex + 1)
                return
            }
            if (root.historyIndex === -1) {
                return
            }
            const next = root.historyIndex + 1
            if (next >= root.history.length) {
                root.historyIndex = -1
                commandField.text = ""
            } else {
                root.historyIndex = next
                commandField.text = root.history[next]
            }
        }

        // Plain QML-native popup, not QCompleter - checked, and it doesn't
        // fit this project (QCompleter lives in QtWidgets, which this
        // project links nowhere at all - see TODO.md's Shell item, step 4).
        // Opens upward since commandField sits at the bottom of the page.
        // visible is a pure binding off filteredCommands (which itself
        // depends only on commandField.text), never set imperatively from
        // anywhere - closePolicy: NoAutoClose keeps Popup's own click-
        // outside/Escape handling from fighting that binding by setting
        // visible itself.
        Popup {
            id: commandPopup
            parent: commandField
            x: 0
            y: -height
            width: commandField.width
            padding: 0
            visible: root.filteredCommands.length > 0
            closePolicy: Popup.NoAutoClose

            contentItem: ListView {
                implicitHeight: Math.min(contentHeight, 200)
                clip: true
                model: root.filteredCommands
                // Keeps the Up/Down-highlighted row scrolled into view -
                // ListView does this automatically whenever currentIndex
                // changes, regardless of what changed it.
                currentIndex: root.highlightedIndex

                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    highlighted: index === root.highlightedIndex
                    text: root.formatSignature(modelData)
                    font.family: "monospace"
                    onClicked: root.selectSuggestion(modelData)
                }
            }
        }
    }
}
