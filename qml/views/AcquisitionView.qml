import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Dedicated page for IAcquisition modules, ported from pyobs-gui's
// acquisitionwidget.py (AcquisitionWidget) - see TODO.md. Only reachable
// via the sidebar while at least one connected module implements
// IAcquisition (see MainWindow.qml's hasAcquisitionModule), same shape as
// AutoFocusView.qml/IAutoFocus.
//
// Unlike IAutoFocus, the result here arrives purely via state
// (AcquisitionState.result) - acquisitionwidget.py never registers a
// separate event, so this page doesn't either.
//
// Wrapped in a ScrollView (unlike RoofView.qml/AutoFocusView.qml, which
// are plain ColumnLayouts) since this page's two stacked plots per module
// (see the "Stacked vertically" comment below) need more vertical room
// than a typical window height comfortably offers - without this, the
// result fields/buttons below the plots silently clip at the window's
// bottom edge instead of being reachable by scrolling.
ScrollView {
    id: root

    required property var xmppClient

    clip: true

    ColumnLayout {
        width: root.availableWidth
        spacing: 8

        Label {
            text: "Acquisition"
            font.bold: true
            font.pixelSize: 16
        }

        Repeater {
            model: root.xmppClient.modules

            // Same in-place-update caveat as RoofView.qml/AutoFocusView.qml's
            // Repeaters: this model is a real QAbstractListModel, so
            // delegates are updated in place rather than recreated.
            delegate: ColumnLayout {
                id: acquisitionDelegate
                Layout.fillWidth: true

                required property string jid
                required property string name
                required property var statefulInterfaces

                // Plain indexed loop, not Array.isArray()/.map()/.filter() -
                // matches RoofView.qml's findInterface()/AutoFocusView.qml's
                // fieldOf(), a pattern already confirmed live-safe on this
                // kind of C++-crossed QVariantList-of-QVariantMap (see
                // DEVELOPMENT.md's "Roof state display bug" section).
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
                // {"key":..,"value":..} entries, wire-order preserved). Only
                // ever called on an already-reactive `property var` capture
                // (acquisitionState/runningState below), never directly
                // inside the same expression as a subscription's `.value` -
                // see AutoFocusView.qml's own copy of this function for why
                // that distinction matters for QML binding reactivity.
                function fieldOf(entries, name) {
                    const list = entries || []
                    for (let i = 0; i < list.length; ++i) {
                        if (list[i].key === name) {
                            return list[i].value
                        }
                    }
                    return undefined
                }

                // First non-null offset_frame across a decoded attempts list -
                // matches acquisitionwidget.py's own `offset_attempts[0]`
                // lookup for picking the offset plot's axis labels.
                function firstOffsetFrame(attempts) {
                    const list = attempts || []
                    for (let i = 0; i < list.length; ++i) {
                        const frame = fieldOf(list[i], "offset_frame")
                        if (frame !== undefined && frame !== null) {
                            return frame
                        }
                    }
                    return null
                }

                function formatFixed(value, decimals) {
                    return (value === undefined || value === null) ? "" : value.toFixed(decimals)
                }

                function signedFixed(value, decimals) {
                    if (value === undefined || value === null) {
                        return ""
                    }
                    return (value >= 0 ? "+" : "") + value.toFixed(decimals)
                }

                readonly property var acquisitionInterface: findInterface("IAcquisition")
                readonly property var runningInterface: findInterface("IRunning")
                visible: acquisitionInterface !== null

                property var acquisitionSubscription: null
                property var runningSubscription: null

                function refreshSubscriptions() {
                    if (acquisitionSubscription) {
                        acquisitionSubscription.unsubscribe()
                        acquisitionSubscription = null
                    }
                    if (runningSubscription) {
                        runningSubscription.unsubscribe()
                        runningSubscription = null
                    }
                    if (visible && acquisitionInterface) {
                        acquisitionSubscription = root.xmppClient.subscribeState(
                            jid, "IAcquisition", acquisitionInterface.version, acquisitionDelegate)
                    }
                    if (visible && runningInterface) {
                        runningSubscription = root.xmppClient.subscribeState(
                            jid, "IRunning", runningInterface.version, acquisitionDelegate)
                    }
                }

                onVisibleChanged: refreshSubscriptions()
                onAcquisitionInterfaceChanged: refreshSubscriptions()
                onRunningInterfaceChanged: refreshSubscriptions()
                Component.onCompleted: refreshSubscriptions()

                readonly property var acquisitionState: acquisitionSubscription ? acquisitionSubscription.value : undefined
                readonly property var runningState: runningSubscription ? runningSubscription.value : undefined

                readonly property bool running: !!fieldOf(runningState, "running")
                readonly property var attemptsValue: fieldOf(acquisitionState, "attempts")
                readonly property var resultValue: fieldOf(acquisitionState, "result")
                readonly property bool hasResult: resultValue !== undefined && resultValue !== null

                readonly property string offsetFrame: firstOffsetFrame(attemptsValue)
                readonly property string offsetXLabel: offsetFrame === "radec" ? "RA offset [deg]"
                    : offsetFrame === "altaz" ? "Alt offset [deg]" : "Offset 1 [deg]"
                readonly property string offsetYLabel: offsetFrame === "radec" ? "Dec offset [deg]"
                    : offsetFrame === "altaz" ? "Az offset [deg]" : "Offset 2 [deg]"

                readonly property string resultOffsetFrame: hasResult ? fieldOf(resultValue, "offset_frame") : null
                readonly property string offsetLabelText: resultOffsetFrame === "radec" ? "RA/Dec offset:"
                    : resultOffsetFrame === "altaz" ? "Alt/Az offset:" : "Offset:"

                property string lastError: ""

                RowLayout {
                    Label {
                        text: acquisitionDelegate.name
                        font.bold: true
                    }
                    Label {
                        text: acquisitionDelegate.jid
                        color: "grey"
                    }
                }

                // Stacked vertically, not side by side: a RowLayout here
                // reproducibly gave one child nearly all the width and the
                // other almost none, regardless of which child type was
                // tried (PlotItem directly, PlotItem wrapped in a plain Item,
                // even plain debug-colored Rectangles with no PlotItem
                // involved at all) - so the cause is RowLayout's own stretch
                // distribution misbehaving in this specific nested context
                // (Repeater delegate -> ColumnLayout -> StackLayout page),
                // not anything about PlotItem itself. ColumnLayout's
                // Layout.fillWidth-per-item behavior is what every other page
                // in this app (including AutoFocusView.qml's own single
                // PlotItem) already relies on successfully, so stacking
                // trades the Python widget's side-by-side subplot layout for
                // a reliably-working one rather than chasing this further.
                PlotItem {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    Layout.leftMargin: 8
                    points: acquisitionDelegate.attemptsValue
                    xLabel: "Attempt"
                    yLabel: "Distance to target [arcsec]"
                    showLine: true
                    xTicksAsIntegers: true
                }

                PlotItem {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    Layout.leftMargin: 8
                    points: acquisitionDelegate.attemptsValue
                    xFieldIndex: 4
                    yFieldIndex: 5
                    xLabel: acquisitionDelegate.offsetXLabel
                    yLabel: acquisitionDelegate.offsetYLabel
                    showLine: true
                    equalAspect: true
                    originCrosshair: true
                    showStartMarker: true
                    showLatestMarker: true
                }

                Label {
                    Layout.leftMargin: 8
                    text: acquisitionDelegate.running ? "Acquiring..." : acquisitionDelegate.hasResult ? "Acquired." : "Idle"
                    color: "grey"
                }

                GridLayout {
                    Layout.leftMargin: 8
                    columns: 4
                    visible: acquisitionDelegate.hasResult

                    Label { text: "RA:"; color: "grey" }
                    Label { text: acquisitionDelegate.formatFixed(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "ra"), 5) }
                    Label { text: "Dec:"; color: "grey" }
                    Label { text: acquisitionDelegate.formatFixed(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "dec"), 5) }
                    Label { text: "Alt:"; color: "grey" }
                    Label { text: acquisitionDelegate.formatFixed(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "alt"), 3) }
                    Label { text: "Az:"; color: "grey" }
                    Label { text: acquisitionDelegate.formatFixed(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "az"), 3) }
                    Label { text: acquisitionDelegate.offsetLabelText; color: "grey" }
                    Label {
                        Layout.columnSpan: 3
                        text: "(" + acquisitionDelegate.signedFixed(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "offset_lon"), 5)
                            + ", " + acquisitionDelegate.signedFixed(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "offset_lat"), 5) + ")"
                    }
                }

                RowLayout {
                    Layout.leftMargin: 8

                    Button {
                        text: "Acquire"
                        enabled: !acquisitionDelegate.running
                        onClicked: {
                            acquisitionDelegate.lastError = ""
                            root.xmppClient.executeMethod(
                                acquisitionDelegate.jid, "acquire_target", 0,
                                function (result) {
                                    if (!result.success) {
                                        acquisitionDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                    }
                                })
                        }
                    }
                    Button {
                        text: "Abort"
                        enabled: acquisitionDelegate.running
                        onClicked: root.xmppClient.executeMethod(acquisitionDelegate.jid, "abort", 0)
                    }
                }

                Label {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    visible: acquisitionDelegate.lastError.length > 0
                    text: acquisitionDelegate.lastError
                    color: "red"
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}
