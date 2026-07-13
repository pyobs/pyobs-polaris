import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

import "../widgets/Permissions.js" as Permissions

// Dedicated page for IAcquisition modules, ported from pyobs-gui's
// acquisitionwidget.py (AcquisitionWidget) - see TODO.md. Only reachable
// via the sidebar while at least one connected module implements
// IAcquisition (see MainWindow.qml's hasAcquisitionModule), same shape as
// AutoFocusView.qml/IAutoFocus.
//
// Layout order below (plots -> Acquire/Abort -> status -> "Result"
// GroupBox) matches acquisitionwidget.ui exactly (read directly) - the
// two-plot Row block itself is untouched by this pass (see its own
// comment on why RowLayout specifically misbehaved there; not worth
// re-litigating for a GroupBox-only pass).
//
// Unlike IAutoFocus, the result here arrives purely via state
// (AcquisitionState.result) - acquisitionwidget.py never registers a
// separate event, so this page doesn't either.
//
// Wrapped in a ScrollView (unlike RoofView.qml/AutoFocusView.qml, which
// are plain ColumnLayouts) as a safety net for shorter windows - two
// plots plus result fields/buttons per module can still exceed a modest
// window's visible height, and without this, content below the plots
// would silently clip at the window's bottom edge instead of being
// reachable by scrolling.
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
                required property var permittedMethods

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

                // Degrees -> arcsec, matching PlotItem's xScale/yScale: 3600
                // on the offset plot below - the result row shows the same
                // offset the plot does, not the raw wire value.
                function toArcsec(value) {
                    return (value === undefined || value === null) ? value : value * 3600
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

                // Plotted (and the result row below) in arcsec, not the
                // raw wire degrees - matches autoguidingwidget.py's own
                // convention (offset_lon/offset_lat * 3600) for the same
                // kind of small angular offset; degrees produced
                // impractically long decimal tick labels for values this
                // small. PlotItem.xScale/yScale: 3600 do the conversion.
                readonly property string offsetFrame: firstOffsetFrame(attemptsValue)
                readonly property string offsetXLabel: offsetFrame === "radec" ? "RA offset [arcsec]"
                    : offsetFrame === "altaz" ? "Alt offset [arcsec]" : "Offset 1 [arcsec]"
                readonly property string offsetYLabel: offsetFrame === "radec" ? "Dec offset [arcsec]"
                    : offsetFrame === "altaz" ? "Az offset [arcsec]" : "Offset 2 [arcsec]"

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

                // Side by side, via a plain Row (not RowLayout - a
                // RowLayout here reproducibly gave one child nearly all
                // the width and the other almost none, regardless of
                // child type: PlotItem directly, PlotItem wrapped in a
                // plain Item, even plain debug-colored Rectangles with no
                // PlotItem involved at all, so the cause was RowLayout's
                // own stretch distribution misbehaving in this specific
                // nested context - Repeater delegate -> ColumnLayout ->
                // StackLayout page - not anything about PlotItem itself).
                // Each PlotItem's width is computed directly from
                // root.availableWidth - root (the page's own top-level
                // ScrollView) gets its width authoritatively from
                // MainWindow.qml's StackLayout, and nothing inside this
                // file ever writes back to it, unlike
                // acquisitionDelegate.width (a Repeater delegate's own
                // width), which turned out to be ambiguous/circular when
                // referenced from its own descendants - see
                // DEVELOPMENT.md for the full debugging trail.
                Row {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    spacing: 16

                    readonly property real plotWidth: (root.availableWidth - 16 - spacing) / 2

                    PlotItem {
                        width: parent.plotWidth
                        height: 220
                        points: acquisitionDelegate.attemptsValue
                        xLabel: "Attempt"
                        yLabel: "Distance to target [arcsec]"
                        showLine: true
                        xTicksAsIntegers: true
                    }

                    PlotItem {
                        width: parent.plotWidth
                        height: 220
                        points: acquisitionDelegate.attemptsValue
                        xFieldIndex: 4
                        yFieldIndex: 5
                        xScale: 3600
                        yScale: 3600
                        xLabel: acquisitionDelegate.offsetXLabel
                        yLabel: acquisitionDelegate.offsetYLabel
                        showLine: true
                        equalAspect: true
                        originCrosshair: true
                        showStartMarker: true
                        showLatestMarker: true
                    }
                }

                RowLayout {
                    Layout.leftMargin: 8

                    Button {
                        text: "Acquire"
                        enabled: !acquisitionDelegate.running && Permissions.isPermitted(acquisitionDelegate.permittedMethods, "acquire_target")
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
                        enabled: acquisitionDelegate.running && Permissions.isPermitted(acquisitionDelegate.permittedMethods, "abort")
                        onClicked: root.xmppClient.executeMethod(acquisitionDelegate.jid, "abort", 0)
                    }
                }

                Label {
                    Layout.leftMargin: 8
                    text: acquisitionDelegate.running ? "Acquiring..." : acquisitionDelegate.hasResult ? "Acquired." : "Idle"
                    color: "grey"
                }

                GroupBox {
                    title: "Result"
                    Layout.leftMargin: 8
                    visible: acquisitionDelegate.hasResult

                    GridLayout {
                        width: parent.width
                        columns: 4
                        columnSpacing: 12
                        rowSpacing: 4

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
                            text: "(" + acquisitionDelegate.signedFixed(acquisitionDelegate.toArcsec(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "offset_lon")), 2)
                                + ", " + acquisitionDelegate.signedFixed(acquisitionDelegate.toArcsec(acquisitionDelegate.fieldOf(acquisitionDelegate.resultValue, "offset_lat")), 2)
                                + ") arcsec"
                        }
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
