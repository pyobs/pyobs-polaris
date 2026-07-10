import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.gui

// Dedicated page for ITelescope modules, ported from pyobs-gui's
// telescopewidget.py - MVP scope only (see TODO.md for what's
// deliberately out of scope: sexagesimal RA/Dec parsing, destination-
// coordinate preview, solar-frame pointing, SIMBAD/Horizons/MPC lookups,
// jog control, Filter/Focus/Temperatures). ITelescope itself is a bare
// IMotion marker (confirmed against pyobs.interfaces.ITelescope source),
// so the base block below is identical to RoofView.qml's; Move and
// Offsets stack under it, each gated on the module actually implementing
// the relevant capability interface (IPointingRaDec/IPointingAltAz/
// IOffsetsRaDec/IOffsetsAltAz) - see DEVELOPMENT.md for the live-
// verification caveat around IOffsetsAltAz specifically.
ScrollView {
    id: root

    required property var xmppClient

    clip: true

    ColumnLayout {
        width: root.availableWidth
        spacing: 8

        Label {
            text: "Telescope"
            font.bold: true
            font.pixelSize: 16
        }

        Repeater {
            model: root.xmppClient.modules

            // Same in-place-update caveat as every other custom widget's
            // Repeater here (RoofView.qml/AutoGuidingView.qml/etc.) - this
            // model is a real QAbstractListModel, so delegates are
            // updated in place rather than recreated.
            delegate: ColumnLayout {
                id: telescopeDelegate
                Layout.fillWidth: true

                required property string jid
                required property string name
                required property var statefulInterfaces

                function findInterface(interfaceName) {
                    const list = statefulInterfaces || []
                    for (let i = 0; i < list.length; ++i) {
                        if (list[i].name === interfaceName) {
                            return list[i]
                        }
                    }
                    return null
                }

                function fieldOf(entries, key) {
                    const list = entries || []
                    for (let i = 0; i < list.length; ++i) {
                        if (list[i].key === key) {
                            return list[i].value
                        }
                    }
                    return undefined
                }

                readonly property var motionInterface: findInterface("IMotion")
                readonly property var raDecOffsetsInterface: findInterface("IOffsetsRaDec")
                readonly property var altAzOffsetsInterface: findInterface("IOffsetsAltAz")
                readonly property bool hasRaDecPointing: findInterface("IPointingRaDec") !== null
                readonly property bool hasAltAzPointing: findInterface("IPointingAltAz") !== null

                visible: findInterface("ITelescope") !== null

                property var motionSubscription: null
                property var raDecOffsetsSubscription: null
                property var altAzOffsetsSubscription: null

                function refreshSubscriptions() {
                    if (motionSubscription) {
                        motionSubscription.unsubscribe()
                        motionSubscription = null
                    }
                    if (raDecOffsetsSubscription) {
                        raDecOffsetsSubscription.unsubscribe()
                        raDecOffsetsSubscription = null
                    }
                    if (altAzOffsetsSubscription) {
                        altAzOffsetsSubscription.unsubscribe()
                        altAzOffsetsSubscription = null
                    }
                    if (visible && motionInterface) {
                        motionSubscription = root.xmppClient.subscribeState(
                            jid, "IMotion", motionInterface.version, telescopeDelegate)
                    }
                    if (visible && raDecOffsetsInterface) {
                        raDecOffsetsSubscription = root.xmppClient.subscribeState(
                            jid, "IOffsetsRaDec", raDecOffsetsInterface.version, telescopeDelegate)
                    }
                    if (visible && altAzOffsetsInterface) {
                        altAzOffsetsSubscription = root.xmppClient.subscribeState(
                            jid, "IOffsetsAltAz", altAzOffsetsInterface.version, telescopeDelegate)
                    }
                }

                onVisibleChanged: refreshSubscriptions()
                onMotionInterfaceChanged: refreshSubscriptions()
                onRaDecOffsetsInterfaceChanged: refreshSubscriptions()
                onAltAzOffsetsInterfaceChanged: refreshSubscriptions()
                Component.onCompleted: refreshSubscriptions()

                readonly property var motionState: motionSubscription ? motionSubscription.value : undefined
                readonly property var raDecOffsetsState: raDecOffsetsSubscription ? raDecOffsetsSubscription.value : undefined
                readonly property var altAzOffsetsState: altAzOffsetsSubscription ? altAzOffsetsSubscription.value : undefined

                readonly property string motionStatus: fieldOf(motionState, "status") || ""
                // Wire value is the lowercase enum member (confirmed live -
                // "idle", not "IDLE" - same convention ModeView.qml's own
                // motionStatus/initialized pair already uses). Same
                // "initialized" set telescopewidget.py:287-300's update_gui
                // gates Move/Offsets controls on - still a valid subset of
                // the real (larger) MotionStatus enum, which also has
                // aborting/error/initializing/parking/parked/calibrating/
                // unknown members that stay disabled.
                readonly property bool motionReady: motionStatus === "slewing" || motionStatus === "tracking"
                    || motionStatus === "idle" || motionStatus === "positioned"

                property string running: "" // action currently in flight, "" if none
                property string lastError: ""

                function run(action, paramCount) {
                    telescopeDelegate.running = action
                    telescopeDelegate.lastError = ""
                    root.xmppClient.executeMethod(jid, action, paramCount, function (result) {
                        if (!result.success) {
                            telescopeDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                        }
                        telescopeDelegate.running = ""
                    })
                }

                function runWithParams(action, params) {
                    telescopeDelegate.lastError = ""
                    root.xmppClient.executeMethod(jid, action, params, function (result) {
                        if (!result.success) {
                            telescopeDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                        }
                    })
                }

                // "was synced" idiom, same as AutoGuidingView.qml's
                // exposure-time SpinBox: only overwritten by a fresh
                // server push if it still shows the last value *this
                // page* last synced from the server, so an in-progress
                // edit isn't clobbered by an unrelated state update. Must
                // live here (on telescopeDelegate, the object that
                // actually owns raDecOffsetsState/altAzOffsetsState) -
                // an onXChanged handler only binds to a property on its
                // own object, not one belonging to an ancestor/descendant.
                // raOffsetSpin/decOffsetSpin/altOffsetSpin/azOffsetSpin
                // are forward id references into this same delegate's
                // object tree, resolved once the state actually changes
                // (well after Component.onCompleted), same trick
                // AutoGuidingView.qml's exposureSpin reference relies on.
                property real lastSyncedRaOffset: NaN
                property real lastSyncedDecOffset: NaN

                onRaDecOffsetsStateChanged: {
                    const raValue = fieldOf(raDecOffsetsState, "ra")
                    const decValue = fieldOf(raDecOffsetsState, "dec")
                    if (raValue === undefined || raValue === null || decValue === undefined || decValue === null) {
                        return
                    }
                    const raArcsec = raValue * 3600
                    const decArcsec = decValue * 3600
                    const raWasSynced = isNaN(lastSyncedRaOffset) || Math.round(raOffsetSpin.value) === Math.round(lastSyncedRaOffset)
                    const decWasSynced = isNaN(lastSyncedDecOffset) || Math.round(decOffsetSpin.value) === Math.round(lastSyncedDecOffset)
                    lastSyncedRaOffset = raArcsec
                    lastSyncedDecOffset = decArcsec
                    if (raWasSynced) {
                        raOffsetSpin.value = Math.round(raArcsec)
                    }
                    if (decWasSynced) {
                        decOffsetSpin.value = Math.round(decArcsec)
                    }
                }

                property real lastSyncedAltOffset: NaN
                property real lastSyncedAzOffset: NaN

                onAltAzOffsetsStateChanged: {
                    const altValue = fieldOf(altAzOffsetsState, "alt")
                    const azValue = fieldOf(altAzOffsetsState, "az")
                    if (altValue === undefined || altValue === null || azValue === undefined || azValue === null) {
                        return
                    }
                    const altArcsec = altValue * 3600
                    const azArcsec = azValue * 3600
                    const altWasSynced = isNaN(lastSyncedAltOffset) || Math.round(altOffsetSpin.value) === Math.round(lastSyncedAltOffset)
                    const azWasSynced = isNaN(lastSyncedAzOffset) || Math.round(azOffsetSpin.value) === Math.round(lastSyncedAzOffset)
                    lastSyncedAltOffset = altArcsec
                    lastSyncedAzOffset = azArcsec
                    if (altWasSynced) {
                        altOffsetSpin.value = Math.round(altArcsec)
                    }
                    if (azWasSynced) {
                        azOffsetSpin.value = Math.round(azArcsec)
                    }
                }

                RowLayout {
                    Label {
                        text: telescopeDelegate.name
                        font.bold: true
                    }
                    Label {
                        text: telescopeDelegate.jid
                        color: "grey"
                    }
                }

                KeyValueCard {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    value: telescopeDelegate.motionState
                }

                RowLayout {
                    Button {
                        text: "Init"
                        enabled: telescopeDelegate.running === ""
                        onClicked: telescopeDelegate.run("init", 0)
                    }
                    Button {
                        text: "Park"
                        enabled: telescopeDelegate.running === ""
                        onClicked: telescopeDelegate.run("park", 0)
                    }
                    Button {
                        text: "Stop"
                        enabled: telescopeDelegate.running === ""
                        onClicked: telescopeDelegate.run("stop_motion", 1)
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: telescopeDelegate.lastError.length > 0
                    text: telescopeDelegate.lastError
                    color: "red"
                    wrapMode: Text.WrapAnywhere
                }

                // --- Move: visible if the module can point at RA/Dec
                // and/or Alt/Az. Fire-and-forget command fields, not
                // persistent state - no "was synced" idiom needed here
                // (unlike Offsets below), since there's no server-pushed
                // value these fields ever need to reflect.
                ColumnLayout {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    visible: telescopeDelegate.hasRaDecPointing || telescopeDelegate.hasAltAzPointing
                    spacing: 4

                    Label {
                        text: "Move"
                        font.bold: true
                    }

                    RowLayout {
                        Label { text: "Coordinates:" }
                        ComboBox {
                            id: moveTypeCombo
                            model: {
                                const types = []
                                if (telescopeDelegate.hasRaDecPointing) types.push("RA/Dec")
                                if (telescopeDelegate.hasAltAzPointing) types.push("Alt/Az")
                                return types
                            }
                        }
                    }

                    RowLayout {
                        visible: moveTypeCombo.currentText === "RA/Dec"

                        Label { text: "RA [deg]:" }
                        TextField {
                            id: raField
                            implicitWidth: 90
                            placeholderText: "0.0"
                            validator: DoubleValidator {}
                        }
                        Label { text: "Dec [deg]:" }
                        TextField {
                            id: decField
                            implicitWidth: 90
                            placeholderText: "0.0"
                            validator: DoubleValidator {}
                        }
                        Button {
                            text: "Move"
                            enabled: telescopeDelegate.motionReady && raField.acceptableInput && decField.acceptableInput
                            onClicked: telescopeDelegate.runWithParams(
                                "move_radec", [parseFloat(raField.text), parseFloat(decField.text)])
                        }
                    }

                    RowLayout {
                        visible: moveTypeCombo.currentText === "Alt/Az"

                        Label { text: "Alt [deg]:" }
                        SpinBox {
                            id: altSpin
                            from: -90
                            to: 90
                            value: 0
                            editable: true
                        }
                        Label { text: "Az [deg]:" }
                        SpinBox {
                            id: azSpin
                            from: 0
                            to: 360
                            value: 0
                            editable: true
                        }
                        Button {
                            text: "Move"
                            enabled: telescopeDelegate.motionReady
                            onClicked: telescopeDelegate.runWithParams(
                                "move_altaz", [altSpin.value, azSpin.value])
                        }
                    }
                }

                // --- Offsets: visible if the module reports IOffsetsRaDec
                // and/or IOffsetsAltAz, one sub-row per interface present.
                // Each SpinBox mirrors AutoGuidingView.qml's exposure-time
                // "was synced" idiom: only overwritten by a fresh server
                // push if it still shows the last value *this page* last
                // synced from the server, so an in-progress edit isn't
                // clobbered by an unrelated state update. That doubles as
                // the "shows the current offset" display TODO.md asks
                // for - no separate read-only label needed.
                ColumnLayout {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    visible: telescopeDelegate.raDecOffsetsInterface !== null || telescopeDelegate.altAzOffsetsInterface !== null
                    spacing: 4

                    Label {
                        text: "Offsets"
                        font.bold: true
                    }

                    RowLayout {
                        visible: telescopeDelegate.raDecOffsetsInterface !== null

                        Label { text: "RA/Dec [arcsec]:" }
                        SpinBox {
                            id: raOffsetSpin
                            from: -3600
                            to: 3600
                            value: 0
                            editable: true
                        }
                        SpinBox {
                            id: decOffsetSpin
                            from: -3600
                            to: 3600
                            value: 0
                            editable: true
                        }
                        Button {
                            text: "Set"
                            enabled: telescopeDelegate.motionReady
                            onClicked: telescopeDelegate.runWithParams(
                                "set_offsets_radec", [raOffsetSpin.value / 3600, decOffsetSpin.value / 3600])
                        }
                        Button {
                            text: "Reset to 0"
                            enabled: telescopeDelegate.motionReady
                            onClicked: {
                                raOffsetSpin.value = 0
                                decOffsetSpin.value = 0
                                telescopeDelegate.runWithParams("set_offsets_radec", [0, 0])
                            }
                        }
                    }

                    // Schema-verified only, not live-pixel-verified - no
                    // built-in Dummy* module implements IOffsetsAltAz (see
                    // DEVELOPMENT.md).
                    RowLayout {
                        visible: telescopeDelegate.altAzOffsetsInterface !== null

                        Label { text: "Alt/Az [arcsec]:" }
                        SpinBox {
                            id: altOffsetSpin
                            from: -3600
                            to: 3600
                            value: 0
                            editable: true
                        }
                        SpinBox {
                            id: azOffsetSpin
                            from: -3600
                            to: 3600
                            value: 0
                            editable: true
                        }
                        Button {
                            text: "Set"
                            enabled: telescopeDelegate.motionReady
                            onClicked: telescopeDelegate.runWithParams(
                                "set_offsets_altaz", [altOffsetSpin.value / 3600, azOffsetSpin.value / 3600])
                        }
                        Button {
                            text: "Reset to 0"
                            enabled: telescopeDelegate.motionReady
                            onClicked: {
                                altOffsetSpin.value = 0
                                azOffsetSpin.value = 0
                                telescopeDelegate.runWithParams("set_offsets_altaz", [0, 0])
                            }
                        }
                    }
                }
            }
        }
    }
}
