import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

import "../widgets/Permissions.js" as Permissions

// Dedicated page for IAutoFocus modules, ported from pyobs-gui's
// autofocuswidget.py (AutoFocusWidget) - see TODO.md. Only reachable via
// the sidebar while at least one connected module implements IAutoFocus
// (see MainWindow.qml's hasAutoFocusModule), same shape as
// RoofView.qml/IRoof.
//
// Layout: autofocuswidget.ui itself is a vertical stack (stretch="1,0,0,0"
// - read directly), plot on top and dominant, everything else below it -
// ported as-is rather than switching to CameraView.qml's sidebar+dominant-
// content split, since that's what the source actually does. Count/Step/
// Exposure time + Run/Abort all live inside one "Auto Focus" GroupBox in
// the source (formLayout + a button row, both nested inside the same
// groupBox) - status (labelStatus) is a sibling of the GroupBox, not
// nested inside it, so it stays below/outside here too. No color
// overrides on Run/Abort in the source (unlike Camera's Expose/Abort or
// Roof's Open/Close/Stop) - left plain here to match.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    Label {
        text: "Auto Focus"
        font.bold: true
        font.pixelSize: 16
    }

    Repeater {
        model: root.xmppClient.modules

        // Same in-place-update caveat as RoofView.qml's Repeater: this
        // model is a real QAbstractListModel, so delegates are updated in
        // place rather than recreated - explicitly unsubscribe/re-fetch
        // rather than relying on bindings alone to clean up.
        delegate: ColumnLayout {
            id: autoFocusDelegate
            Layout.fillWidth: true

            required property string jid
            required property string name
            required property var statefulInterfaces
            required property var permittedMethods

            // Plain indexed loop, not Array.isArray()/.map()/.filter() -
            // matches RoofView.qml's own findInterface() exactly, a
            // pattern already confirmed live-safe on this same kind of
            // C++-crossed QVariantList-of-QVariantMap (see
            // DEVELOPMENT.md's "Roof state display bug" section for why
            // that distinction matters).
            function findInterface(interfaceName) {
                const list = statefulInterfaces || []
                for (let i = 0; i < list.length; ++i) {
                    if (list[i].name === interfaceName) {
                        return list[i]
                    }
                }
                return null
            }

            // Pulls one named field's value out of a decoded state record
            // (a StateSubscription.value-shaped QVariantList of
            // {"key":..,"value":..} entries, wire-order preserved - see
            // codec::toQVariant). Same indexed-loop safety note as
            // findInterface() above. Only ever called on an already-
            // reactive `property var` capture (autoFocusState/
            // runningState below), never directly on a subscription's
            // `.value` inside the same expression - a plain function call
            // doesn't itself establish a QML binding dependency, so the
            // reactivity has to come from reading `.value` as a real
            // property read first, same as RoofView.qml's
            // `subscription.value` passthrough.
            function fieldOf(entries, name) {
                const list = entries || []
                for (let i = 0; i < list.length; ++i) {
                    if (list[i].key === name) {
                        return list[i].value
                    }
                }
                return undefined
            }

            readonly property var autoFocusInterface: findInterface("IAutoFocus")
            readonly property var runningInterface: findInterface("IRunning")
            visible: autoFocusInterface !== null

            property var autoFocusSubscription: null
            property var runningSubscription: null

            function refreshSubscriptions() {
                if (autoFocusSubscription) {
                    autoFocusSubscription.unsubscribe()
                    autoFocusSubscription = null
                }
                if (runningSubscription) {
                    runningSubscription.unsubscribe()
                    runningSubscription = null
                }
                if (visible && autoFocusInterface) {
                    autoFocusSubscription = root.xmppClient.subscribeState(
                        jid, "IAutoFocus", autoFocusInterface.version, autoFocusDelegate)
                }
                if (visible && runningInterface) {
                    runningSubscription = root.xmppClient.subscribeState(
                        jid, "IRunning", runningInterface.version, autoFocusDelegate)
                }
            }

            onVisibleChanged: refreshSubscriptions()
            onAutoFocusInterfaceChanged: refreshSubscriptions()
            onRunningInterfaceChanged: refreshSubscriptions()

            readonly property var autoFocusState: autoFocusSubscription ? autoFocusSubscription.value : undefined
            readonly property var runningState: runningSubscription ? runningSubscription.value : undefined

            readonly property bool running: !!fieldOf(runningState, "running")
            readonly property var pointsValue: fieldOf(autoFocusState, "points")

            // FocusFoundEvent handling: xmppClient.events gives QML no
            // generic random-access iteration for free (see
            // EventLogModel::entriesOfType), so this is recomputed
            // explicitly on every rowsInserted/modelReset, same pattern
            // as LogsView.qml, then filtered to this module. Compare
            // against just the JID's user part, not the full bare JID -
            // EventManager::handlePubSubEvent sets `module` from
            // QXmppUtils::jidToUser(), e.g. "autofocus", not
            // "autofocus@localhost" (ModuleListModel's `jid` role) -
            // comparing against the bare JID directly would silently
            // never match. entriesOfType() is an invokable *return
            // value*, not a Q_PROPERTY(QVariant) read - LogsView.qml's
            // own .map()/.filter() usage on it already proves plain JS
            // array methods are fine here, unlike state values (see
            // fieldOf() above).
            property var focusFoundEvents: []
            readonly property string jidUser: jid.split("@")[0]

            function refreshFocusFoundEvents() {
                focusFoundEvents = root.xmppClient.events.entriesOfType("FocusFoundEvent")
                    .filter((e) => e.module === autoFocusDelegate.jidUser)
            }

            Connections {
                target: root.xmppClient.events
                function onRowsInserted() { autoFocusDelegate.refreshFocusFoundEvents() }
                function onModelReset() { autoFocusDelegate.refreshFocusFoundEvents() }
            }

            Component.onCompleted: {
                refreshSubscriptions()
                refreshFocusFoundEvents()
            }

            readonly property var lastResult: focusFoundEvents.length > 0
                ? focusFoundEvents[focusFoundEvents.length - 1] : null

            // A fresh run clears the stale result from the previous one -
            // same rising-edge reasoning as AutoFocusWidget's own
            // _on_running_state (a new run may have been triggered
            // elsewhere, not just from this page's own button).
            property var shownResult: null
            onRunningChanged: {
                if (running) {
                    shownResult = null
                } else if (lastResult) {
                    shownResult = lastResult
                }
            }
            onLastResultChanged: {
                if (!running) {
                    shownResult = lastResult
                }
            }

            property string lastError: ""

            RowLayout {
                Label {
                    text: autoFocusDelegate.name
                    font.bold: true
                }
                Label {
                    text: autoFocusDelegate.jid
                    color: "grey"
                }
            }

            PlotItem {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                Layout.leftMargin: 8
                points: autoFocusDelegate.pointsValue
                xLabel: "Focus [mm]"
                yLabel: "Metric"
                referenceX: autoFocusDelegate.shownResult ? autoFocusDelegate.shownResult.data.focus : NaN
                referenceLabel: "fitted focus"
            }

            GroupBox {
                title: "Auto Focus"
                Layout.leftMargin: 8
                Layout.preferredWidth: 320

                ColumnLayout {
                    width: parent.width
                    spacing: 6

                    GridLayout {
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 4
                        Layout.fillWidth: true

                        Label { text: "Count:" }
                        SpinBox {
                            id: countSpin
                            Layout.fillWidth: true
                            from: 1
                            to: 20
                            value: 5
                            editable: true
                        }
                        Label { text: "Step [mm]:" }
                        SpinBox {
                            id: stepSpin
                            Layout.fillWidth: true
                            from: 1
                            to: 1000
                            value: 20
                            editable: true
                            textFromValue: (value) => (value / 1000).toFixed(3)
                            valueFromText: (text) => Math.round(parseFloat(text) * 1000)
                        }
                        Label { text: "Exposure [s]:" }
                        SpinBox {
                            id: exposureSpin
                            Layout.fillWidth: true
                            from: 1
                            to: 60000
                            value: 1000
                            editable: true
                            textFromValue: (value) => (value / 1000).toFixed(3)
                            valueFromText: (text) => Math.round(parseFloat(text) * 1000)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            Layout.fillWidth: true
                            text: "Run Auto Focus"
                            enabled: !autoFocusDelegate.running && Permissions.isPermitted(autoFocusDelegate.permittedMethods, "auto_focus")
                            onClicked: {
                                autoFocusDelegate.lastError = ""
                                root.xmppClient.executeMethod(
                                    autoFocusDelegate.jid, "auto_focus",
                                    [countSpin.value, stepSpin.value / 1000, exposureSpin.value / 1000],
                                    function (result) {
                                        if (!result.success) {
                                            autoFocusDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                        }
                                    })
                            }
                        }
                        Button {
                            Layout.fillWidth: true
                            text: "Abort"
                            enabled: autoFocusDelegate.running && Permissions.isPermitted(autoFocusDelegate.permittedMethods, "abort")
                            onClicked: root.xmppClient.executeMethod(autoFocusDelegate.jid, "abort", 0)
                        }
                    }
                }
            }

            Label {
                Layout.leftMargin: 8
                text: {
                    if (autoFocusDelegate.running) {
                        return "Running..."
                    }
                    const result = autoFocusDelegate.shownResult
                    if (!result) {
                        return "Idle"
                    }
                    const err = result.data.error
                    return "Focus: " + result.data.focus.toFixed(3)
                        + (err !== null && err !== undefined ? " ± " + err.toFixed(3) : "") + " mm"
                }
                color: "grey"
            }

            Label {
                Layout.leftMargin: 8
                Layout.fillWidth: true
                visible: autoFocusDelegate.lastError.length > 0
                text: autoFocusDelegate.lastError
                color: "red"
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    Item { Layout.fillHeight: true }
}
