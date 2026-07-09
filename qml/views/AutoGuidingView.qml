import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Dedicated page for IAutoGuiding modules, ported from pyobs-gui's
// autoguidingwidget.py (AutoGuidingWidget) - see TODO.md. Only reachable
// via the sidebar while at least one connected module implements
// IAutoGuiding (see MainWindow.qml's hasAutoGuidingModule), same shape as
// AcquisitionView.qml/IAcquisition.
//
// Unlike IAcquisition's AcquisitionState.attempts (a server-side growing
// list), GuidingState only ever holds the *latest* correction - the
// bounded sample history autoguidingwidget.py plots is built purely
// client-side here, accumulated from each live state push into a plain
// QML-owned array (offsetHistory below). That's safe to freely
// .map()/.concat() in JS, unlike a value that crosses the C++/QML
// boundary as a Q_PROPERTY(QVariant) (see DEVELOPMENT.md's "Roof state
// display bug" section) - offsetHistory is built and owned entirely in
// QML/JS, never itself crossing that boundary.
ScrollView {
    id: root

    required property var xmppClient

    clip: true

    ColumnLayout {
        width: root.availableWidth
        spacing: 8

        Label {
            text: "Auto Guiding"
            font.bold: true
            font.pixelSize: 16
        }

        Repeater {
            model: root.xmppClient.modules

            // Same in-place-update caveat as RoofView.qml/AutoFocusView.qml/
            // AcquisitionView.qml's Repeaters: this model is a real
            // QAbstractListModel, so delegates are updated in place rather
            // than recreated.
            delegate: ColumnLayout {
                id: autoGuidingDelegate
                Layout.fillWidth: true

                required property string jid
                required property string name
                required property var statefulInterfaces

                // Plain indexed loop, not Array.isArray()/.map()/.filter() -
                // matches RoofView.qml's findInterface()/AutoFocusView.qml's
                // fieldOf(), a pattern already confirmed live-safe on this
                // kind of C++-crossed QVariantList-of-QVariantMap.
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
                // (guidingState/runningState/exposureTimeState below), never
                // directly inside the same expression as a subscription's
                // `.value` - see AutoFocusView.qml's own copy of this
                // function for why that distinction matters for QML binding
                // reactivity.
                function fieldOf(entries, name) {
                    const list = entries || []
                    for (let i = 0; i < list.length; ++i) {
                        if (list[i].key === name) {
                            return list[i].value
                        }
                    }
                    return undefined
                }

                function signedFixed(value, decimals) {
                    if (value === undefined || value === null) {
                        return ""
                    }
                    return (value >= 0 ? "+" : "") + value.toFixed(decimals)
                }

                readonly property var autoGuidingInterface: findInterface("IAutoGuiding")
                readonly property var runningInterface: findInterface("IRunning")
                readonly property var exposureTimeInterface: findInterface("IExposureTime")
                visible: autoGuidingInterface !== null

                property var autoGuidingSubscription: null
                property var runningSubscription: null
                property var exposureTimeSubscription: null

                function refreshSubscriptions() {
                    if (autoGuidingSubscription) {
                        autoGuidingSubscription.unsubscribe()
                        autoGuidingSubscription = null
                    }
                    if (runningSubscription) {
                        runningSubscription.unsubscribe()
                        runningSubscription = null
                    }
                    if (exposureTimeSubscription) {
                        exposureTimeSubscription.unsubscribe()
                        exposureTimeSubscription = null
                    }
                    if (visible && autoGuidingInterface) {
                        autoGuidingSubscription = root.xmppClient.subscribeState(
                            jid, "IAutoGuiding", autoGuidingInterface.version, autoGuidingDelegate)
                    }
                    if (visible && runningInterface) {
                        runningSubscription = root.xmppClient.subscribeState(
                            jid, "IRunning", runningInterface.version, autoGuidingDelegate)
                    }
                    if (visible && exposureTimeInterface) {
                        exposureTimeSubscription = root.xmppClient.subscribeState(
                            jid, "IExposureTime", exposureTimeInterface.version, autoGuidingDelegate)
                    }
                }

                onVisibleChanged: refreshSubscriptions()
                onAutoGuidingInterfaceChanged: refreshSubscriptions()
                onRunningInterfaceChanged: refreshSubscriptions()
                onExposureTimeInterfaceChanged: refreshSubscriptions()
                Component.onCompleted: refreshSubscriptions()

                readonly property var guidingState: autoGuidingSubscription ? autoGuidingSubscription.value : undefined
                readonly property var runningState: runningSubscription ? runningSubscription.value : undefined
                readonly property var exposureTimeState: exposureTimeSubscription ? exposureTimeSubscription.value : undefined

                readonly property bool running: !!fieldOf(runningState, "running")
                readonly property bool loopClosed: !!fieldOf(guidingState, "loop_closed")
                readonly property var offsetLon: fieldOf(guidingState, "offset_lon")
                readonly property var offsetLat: fieldOf(guidingState, "offset_lat")
                readonly property bool hasOffset: offsetLon !== undefined && offsetLon !== null
                    && offsetLat !== undefined && offsetLat !== null

                readonly property string loopStateText: running ? (loopClosed ? "Closed loop" : "Open loop") : "Stopped"

                readonly property string offsetFrame: hasOffset ? fieldOf(guidingState, "offset_frame") : null
                readonly property string offsetXLabel: offsetFrame === "radec" ? "RA offset [arcsec]"
                    : offsetFrame === "altaz" ? "Alt offset [arcsec]" : "Offset 1 [arcsec]"
                readonly property string offsetYLabel: offsetFrame === "radec" ? "Dec offset [arcsec]"
                    : offsetFrame === "altaz" ? "Az offset [arcsec]" : "Offset 2 [arcsec]"

                // Bounded client-side sample history - see the file header
                // comment on why this can't just be PlotItem.points bound
                // directly to server state, unlike AcquisitionView.qml.
                // Each entry is {lon, lat} in degrees (raw wire units, not
                // yet arcsec); magnitudeRecords/offsetRecords below derive
                // the two plots' actual PlotItem.points from this, already
                // in the {value:...}-per-field shape PlotItem's positional
                // field-index parsing expects (see PlotItem.h) - built
                // once here rather than needing any PlotItem changes.
                property var offsetHistory: []
                readonly property int maxHistoryLength: 50

                function appendOffsetSample(lon, lat) {
                    let updated = offsetHistory.concat([{ lon: lon, lat: lat }])
                    if (updated.length > maxHistoryLength) {
                        updated = updated.slice(updated.length - maxHistoryLength)
                    }
                    offsetHistory = updated
                }

                onGuidingStateChanged: {
                    if (hasOffset) {
                        appendOffsetSample(offsetLon, offsetLat)
                    }
                }

                readonly property var magnitudeRecords: offsetHistory.map((s, i) => [
                    { value: i + 1 },
                    { value: Math.sqrt(s.lon * s.lon + s.lat * s.lat) * 3600 },
                ])
                readonly property var offsetRecords: offsetHistory.map((s) => [
                    { value: s.lon },
                    { value: s.lat },
                ])

                // Live-editable exposure time: mirrors
                // autoguidingwidget.py's _on_exptime_state "was_synced"
                // check - only overwrite the spin box's current value from
                // a fresh server push if the box still shows the last
                // value *this page itself* last synced from the server, so
                // a user's in-progress edit isn't clobbered by an unrelated
                // state update. exposureSpin (declared further below) is a
                // forward id reference, resolved at binding/handler-run
                // time like any other QML id - not a declaration-order
                // issue.
                property real lastSyncedExposureTime: NaN

                onExposureTimeStateChanged: {
                    const value = fieldOf(exposureTimeState, "exposure_time")
                    if (value === undefined || value === null) {
                        return
                    }
                    const wasSynced = isNaN(lastSyncedExposureTime)
                        || Math.round(exposureSpin.value) === Math.round(lastSyncedExposureTime * 1000)
                    lastSyncedExposureTime = value
                    if (wasSynced) {
                        exposureSpin.value = Math.round(value * 1000)
                    }
                }

                property string lastError: ""

                RowLayout {
                    Label {
                        text: autoGuidingDelegate.name
                        font.bold: true
                    }
                    Label {
                        text: autoGuidingDelegate.jid
                        color: "grey"
                    }
                }

                // Side by side via a plain Row, same technique as
                // AcquisitionView.qml (see DEVELOPMENT.md for the full
                // RowLayout-bug debugging trail behind this specific
                // shape) - each PlotItem's width computed from
                // root.availableWidth (the page's own top-level
                // ScrollView), not from acquisitionDelegate/
                // autoGuidingDelegate.width (a Repeater delegate's own
                // width, which turned out to be circular when referenced
                // from its own descendants).
                Row {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    spacing: 16

                    readonly property real plotWidth: (root.availableWidth - 16 - spacing) / 2

                    PlotItem {
                        width: parent.plotWidth
                        height: 220
                        points: autoGuidingDelegate.magnitudeRecords
                        xLabel: "Sample"
                        yLabel: "Offset magnitude [arcsec]"
                        showLine: true
                        xTicksAsIntegers: true
                    }

                    // Deliberately no showLine here, unlike
                    // AcquisitionView.qml's offset-trajectory plot -
                    // autoguidingwidget.py's own ax2.plot() for this uses
                    // linestyle="" (points only): a scatter of
                    // independent correction samples isn't a path the way
                    // acquisition's converging attempts are, so connecting
                    // them with a line would be misleading, not just a
                    // style choice.
                    PlotItem {
                        width: parent.plotWidth
                        height: 220
                        points: autoGuidingDelegate.offsetRecords
                        xScale: 3600
                        yScale: 3600
                        xLabel: autoGuidingDelegate.offsetXLabel
                        yLabel: autoGuidingDelegate.offsetYLabel
                        equalAspect: true
                        originCrosshair: true
                        showLatestMarker: true
                    }
                }

                Label {
                    Layout.leftMargin: 8
                    text: autoGuidingDelegate.loopStateText
                    color: "grey"
                }

                Label {
                    Layout.leftMargin: 8
                    visible: autoGuidingDelegate.hasOffset
                    text: "(" + autoGuidingDelegate.signedFixed(autoGuidingDelegate.offsetLon * 3600, 2)
                        + ", " + autoGuidingDelegate.signedFixed(autoGuidingDelegate.offsetLat * 3600, 2) + ") arcsec"
                }

                RowLayout {
                    Layout.leftMargin: 8

                    Label { text: "Exposure time:" }
                    SpinBox {
                        id: exposureSpin
                        from: 1
                        to: 60000
                        value: 1000
                        editable: true
                        textFromValue: (value) => (value / 1000).toFixed(3)
                        valueFromText: (text) => Math.round(parseFloat(text) * 1000)
                        onValueModified: {
                            root.xmppClient.executeMethod(
                                autoGuidingDelegate.jid, "set_exposure_time", [value / 1000],
                                function (result) {
                                    if (!result.success) {
                                        autoGuidingDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                    }
                                })
                        }
                    }
                    Label { text: "s" }
                }

                RowLayout {
                    Layout.leftMargin: 8

                    Button {
                        text: "Start"
                        enabled: !autoGuidingDelegate.running
                        onClicked: {
                            autoGuidingDelegate.lastError = ""
                            root.xmppClient.executeMethod(
                                autoGuidingDelegate.jid, "start", 0,
                                function (result) {
                                    if (!result.success) {
                                        autoGuidingDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                    }
                                })
                        }
                    }
                    Button {
                        text: "Stop"
                        enabled: autoGuidingDelegate.running
                        onClicked: root.xmppClient.executeMethod(autoGuidingDelegate.jid, "stop", 0)
                    }
                }

                Label {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    visible: autoGuidingDelegate.lastError.length > 0
                    text: autoGuidingDelegate.lastError
                    color: "red"
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}
