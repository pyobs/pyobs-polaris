import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Dedicated page for ITelescope modules, ported from pyobs-gui's
// telescopewidget.py - MVP scope only (see TODO.md for what's
// deliberately out of scope: sexagesimal RA/Dec parsing, solar-frame
// pointing, SIMBAD/Horizons/MPC/orbit-elements lookups, the jog/compass
// widget). ITelescope itself is a bare IMotion marker (confirmed against
// pyobs.interfaces.ITelescope source), so the base block below is
// identical to RoofView.qml's; Status/Move/Offsets stack under it, each
// gated on the module actually implementing the relevant capability
// interface (IPointingRaDec/IPointingAltAz/IOffsetsRaDec/IOffsetsAltAz) -
// see DEVELOPMENT.md for the live-verification caveat around
// IOffsetsAltAz specifically.
//
// Layout: four GroupBoxes side by side (Status/Move/Offsets/Filter-Focus-
// Temperatures), the first three ported from telescopewidget.ui's own
// QHBoxLayout structure (read directly) - that file has a fifth column
// (CompassMoveWidget, the jog control) still out of scope here. The
// fourth column (Filter/Focus/Temperatures) was out of scope initially
// (this page only carried the three original columns) but shipped in a
// direct follow-up ("finish the camera page with filter/focus. both can
// also show up for the telescope. the telescope page also misses the
// temperatures in the right sidebar.") - `DummyTelescope` implements all
// three of IFilters/IFocuser/ITemperatures (confirmed from pyobs-core
// source, unlike any Dummy* camera module), making this page - not
// CameraView.qml - where those three widgets actually got live-verified.
// All three are qml/widgets/*Panel.qml components shared verbatim with
// CameraView.qml, not hand-wired here - both pages' fourth/third columns
// are now a single generic SidebarPanelRegistry-driven Repeater (direct
// follow-up: "would it make sense to make this a general thing and
// widgets can decide whether they need a sidebar... go full registry") -
// see SidebarPanelRegistry.qml and CameraView.qml's own matching comment.
//
// Status now also shows the live current-pointing readout
// (RA/Dec and/or Alt/Az, decimal degrees) via labelCurRA/Dec/Alt/Az's
// own IPointingRaDec/IPointingAltAz state subscriptions - a real gap
// this pass filled in, not just a visual port; Polaris previously only
// checked those interfaces' *presence* for gating Move, never actually
// displayed where the telescope currently points. Move consolidates
// telescopewidget.ui's own single shared "Move" button below the
// coordinate-type pages, rather than one Move button duplicated per
// page.
//
// Move also includes a destination-coordinate preview (typed RA/Dec <->
// Alt/Az, computed via the CoordinateTransform QML singleton - see
// src/util/CoordinateTransform.h) and an inline Observer Location editor.
// pyobs-core has no wire path for observer location at all (confirmed
// against source - the legacy Python GUI only had it via in-process
// Python object sharing, never serialized to XMPP), so this is a
// client-side-only AppSettings value the user enters once, not fetched
// from any module. Purely informational either way - never changes what
// move_radec()/move_altaz() actually send.
ScrollView {
    id: root

    required property var xmppClient
    required property var appSettings

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
                spacing: 4

                required property string jid
                required property string name
                required property var statefulInterfaces
                required property var filters

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
                readonly property var raDecPointingInterface: findInterface("IPointingRaDec")
                readonly property var altAzPointingInterface: findInterface("IPointingAltAz")
                readonly property bool hasRaDecPointing: raDecPointingInterface !== null
                readonly property bool hasAltAzPointing: altAzPointingInterface !== null

                visible: findInterface("ITelescope") !== null

                property var motionSubscription: null
                property var raDecOffsetsSubscription: null
                property var altAzOffsetsSubscription: null
                property var raDecPointingSubscription: null
                property var altAzPointingSubscription: null

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
                    if (raDecPointingSubscription) {
                        raDecPointingSubscription.unsubscribe()
                        raDecPointingSubscription = null
                    }
                    if (altAzPointingSubscription) {
                        altAzPointingSubscription.unsubscribe()
                        altAzPointingSubscription = null
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
                    if (visible && raDecPointingInterface) {
                        raDecPointingSubscription = root.xmppClient.subscribeState(
                            jid, "IPointingRaDec", raDecPointingInterface.version, telescopeDelegate)
                    }
                    if (visible && altAzPointingInterface) {
                        altAzPointingSubscription = root.xmppClient.subscribeState(
                            jid, "IPointingAltAz", altAzPointingInterface.version, telescopeDelegate)
                    }
                }

                onVisibleChanged: refreshSubscriptions()
                onMotionInterfaceChanged: refreshSubscriptions()
                onRaDecOffsetsInterfaceChanged: refreshSubscriptions()
                onAltAzOffsetsInterfaceChanged: refreshSubscriptions()
                onRaDecPointingInterfaceChanged: refreshSubscriptions()
                onAltAzPointingInterfaceChanged: refreshSubscriptions()
                Component.onCompleted: refreshSubscriptions()

                readonly property var motionState: motionSubscription ? motionSubscription.value : undefined
                readonly property var raDecOffsetsState: raDecOffsetsSubscription ? raDecOffsetsSubscription.value : undefined
                readonly property var altAzOffsetsState: altAzOffsetsSubscription ? altAzOffsetsSubscription.value : undefined
                readonly property var raDecPointingState: raDecPointingSubscription ? raDecPointingSubscription.value : undefined
                readonly property var altAzPointingState: altAzPointingSubscription ? altAzPointingSubscription.value : undefined

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

                // Current-pointing readout (telescopewidget.ui's own
                // labelCurRA/Dec/Alt/Az) - decimal degrees, not the
                // legacy's sexagesimal formatting (TODO.md's own scope
                // cut for this project, unchanged here).
                readonly property var currentRa: fieldOf(raDecPointingState, "ra")
                readonly property var currentDec: fieldOf(raDecPointingState, "dec")
                readonly property var currentAlt: fieldOf(altAzPointingState, "alt")
                readonly property var currentAz: fieldOf(altAzPointingState, "az")

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

                Label {
                    Layout.fillWidth: true
                    visible: telescopeDelegate.lastError.length > 0
                    text: telescopeDelegate.lastError
                    color: "red"
                    wrapMode: Text.WrapAnywhere
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // --- Status: motion state, Init/Park/Stop, and the
                    // live current-pointing readout - telescopewidget.ui's
                    // own groupStatus (labelStatus, buttonInit/Park/Stop,
                    // labelCurRA/Dec/Alt/Az).
                    GroupBox {
                        title: "Status"
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 220

                        ColumnLayout {
                            width: parent.width
                            spacing: 6

                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: telescopeDelegate.motionStatus.toUpperCase()
                                font.bold: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Button {
                                    Layout.fillWidth: true
                                    text: "Init"
                                    enabled: telescopeDelegate.running === ""
                                    onClicked: telescopeDelegate.run("init", 0)
                                }
                                Button {
                                    Layout.fillWidth: true
                                    text: "Park"
                                    enabled: telescopeDelegate.running === ""
                                    onClicked: telescopeDelegate.run("park", 0)
                                }
                                Button {
                                    Layout.fillWidth: true
                                    text: "Stop"
                                    enabled: telescopeDelegate.running === ""
                                    onClicked: telescopeDelegate.run("stop_motion", 1)
                                }
                            }

                            GridLayout {
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4
                                Layout.fillWidth: true
                                visible: telescopeDelegate.hasRaDecPointing || telescopeDelegate.hasAltAzPointing

                                Label { visible: telescopeDelegate.hasRaDecPointing; text: "RA:" }
                                Label {
                                    visible: telescopeDelegate.hasRaDecPointing
                                    Layout.fillWidth: true
                                    text: telescopeDelegate.currentRa !== undefined && telescopeDelegate.currentRa !== null
                                        ? telescopeDelegate.currentRa.toFixed(3) + "°" : "-"
                                    color: "grey"
                                }
                                Label { visible: telescopeDelegate.hasRaDecPointing; text: "Dec:" }
                                Label {
                                    visible: telescopeDelegate.hasRaDecPointing
                                    Layout.fillWidth: true
                                    text: telescopeDelegate.currentDec !== undefined && telescopeDelegate.currentDec !== null
                                        ? telescopeDelegate.currentDec.toFixed(3) + "°" : "-"
                                    color: "grey"
                                }
                                Label { visible: telescopeDelegate.hasAltAzPointing; text: "Alt:" }
                                Label {
                                    visible: telescopeDelegate.hasAltAzPointing
                                    Layout.fillWidth: true
                                    text: telescopeDelegate.currentAlt !== undefined && telescopeDelegate.currentAlt !== null
                                        ? telescopeDelegate.currentAlt.toFixed(3) + "°" : "-"
                                    color: "grey"
                                }
                                Label { visible: telescopeDelegate.hasAltAzPointing; text: "Az:" }
                                Label {
                                    visible: telescopeDelegate.hasAltAzPointing
                                    Layout.fillWidth: true
                                    text: telescopeDelegate.currentAz !== undefined && telescopeDelegate.currentAz !== null
                                        ? telescopeDelegate.currentAz.toFixed(3) + "°" : "-"
                                    color: "grey"
                                }
                            }
                        }
                    }

                    // --- Move: visible if the module can point at RA/Dec
                    // and/or Alt/Az. Fire-and-forget command fields, not
                    // persistent state - no "was synced" idiom needed here
                    // (unlike Offsets below), since there's no server-pushed
                    // value these fields ever need to reflect. One shared
                    // Move button below the active page, matching
                    // telescopewidget.ui's own buttonMove (not one button
                    // duplicated per coordinate-type page).
                    GroupBox {
                        title: "Move"
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 320
                        visible: telescopeDelegate.hasRaDecPointing || telescopeDelegate.hasAltAzPointing

                        ColumnLayout {
                            width: parent.width
                            spacing: 6

                            // Client-side only - see the file header comment
                            // for why this can't be fetched from the
                            // module. Plain "controlled component"
                            // TextFields (same idiom as CameraView.qml's
                            // broadcastCheck): text is set once from the
                            // persisted AppSettings value, then the user
                            // freely edits it, writing back on
                            // editingFinished.
                            Label { text: "Observer location"; color: "grey" }
                            GridLayout {
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4
                                Layout.fillWidth: true

                                Label { text: "Lat [deg]:" }
                                TextField {
                                    id: obsLatField
                                    Layout.fillWidth: true
                                    text: root.appSettings.observerLatitude.toFixed(4)
                                    validator: DoubleValidator { bottom: -90; top: 90 }
                                    onEditingFinished: {
                                        const value = parseFloat(text)
                                        if (!isNaN(value)) {
                                            root.appSettings.observerLatitude = value
                                        }
                                    }
                                }
                                Label { text: "Lon [deg]:" }
                                TextField {
                                    id: obsLonField
                                    Layout.fillWidth: true
                                    text: root.appSettings.observerLongitude.toFixed(4)
                                    validator: DoubleValidator { bottom: -180; top: 180 }
                                    onEditingFinished: {
                                        const value = parseFloat(text)
                                        if (!isNaN(value)) {
                                            root.appSettings.observerLongitude = value
                                        }
                                    }
                                }
                                Label { text: "Elev [m]:" }
                                TextField {
                                    id: obsElevField
                                    Layout.fillWidth: true
                                    text: root.appSettings.observerElevation.toFixed(1)
                                    validator: DoubleValidator {}
                                    onEditingFinished: {
                                        const value = parseFloat(text)
                                        if (!isNaN(value)) {
                                            root.appSettings.observerElevation = value
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Coordinates:" }
                                ComboBox {
                                    id: moveTypeCombo
                                    Layout.fillWidth: true
                                    model: {
                                        const types = []
                                        if (telescopeDelegate.hasRaDecPointing) types.push("RA/Dec")
                                        if (telescopeDelegate.hasAltAzPointing) types.push("Alt/Az")
                                        return types
                                    }
                                }
                            }

                            GridLayout {
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4
                                Layout.fillWidth: true
                                visible: moveTypeCombo.currentText === "RA/Dec"

                                Label { text: "RA [deg]:" }
                                TextField {
                                    id: raField
                                    Layout.fillWidth: true
                                    placeholderText: "0.0"
                                    validator: DoubleValidator {}
                                }
                                Label { text: "Dec [deg]:" }
                                TextField {
                                    id: decField
                                    Layout.fillWidth: true
                                    placeholderText: "0.0"
                                    validator: DoubleValidator {}
                                }
                            }

                            GridLayout {
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4
                                Layout.fillWidth: true
                                visible: moveTypeCombo.currentText === "Alt/Az"

                                Label { text: "Alt [deg]:" }
                                SpinBox {
                                    id: altSpin
                                    Layout.fillWidth: true
                                    from: -90
                                    to: 90
                                    value: 0
                                    editable: true
                                }
                                Label { text: "Az [deg]:" }
                                SpinBox {
                                    id: azSpin
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 360
                                    value: 0
                                    editable: true
                                }
                            }

                            // Destination-coordinate preview: shows what the
                            // *other* coordinate system's values would be for
                            // whichever page is currently active, computed via
                            // the CoordinateTransform QML singleton (libnova-
                            // backed, see src/util/CoordinateTransform.h).
                            // Read-only, informational only - the Move button
                            // below always sends exactly the user's typed/
                            // spun values, unchanged.
                            Label {
                                Layout.fillWidth: true
                                color: "grey"
                                wrapMode: Text.WordWrap
                                text: {
                                    // Read these unconditionally, before any
                                    // early return - real bug caught live: a
                                    // Q_INVOKABLE call like hasObserverLocation()
                                    // below creates no QML binding dependency by
                                    // itself. The first evaluation of this binding
                                    // happens while location is still unset, so it
                                    // used to return before ever reading
                                    // observerLatitude/observerLongitude as
                                    // properties - meaning this binding never
                                    // re-evaluated once the user actually set a
                                    // location, since no dependency on those
                                    // properties had ever been established.
                                    // Reading them here every time, regardless of
                                    // branch, fixes that.
                                    const lat = root.appSettings.observerLatitude
                                    const lon = root.appSettings.observerLongitude
                                    const elev = root.appSettings.observerElevation
                                    if (!root.appSettings.hasObserverLocation()) {
                                        return "Set observer location above to preview"
                                    }
                                    if (moveTypeCombo.currentText === "RA/Dec") {
                                        const ra = parseFloat(raField.text)
                                        const dec = parseFloat(decField.text)
                                        if (isNaN(ra) || isNaN(dec)) {
                                            return ""
                                        }
                                        const result = CoordinateTransform.equatorialToHorizontal(ra, dec, lat, lon, elev)
                                        return "→ Alt: " + result.alt.toFixed(2) + "°, Az: " + result.az.toFixed(2) + "°"
                                    }
                                    if (moveTypeCombo.currentText === "Alt/Az") {
                                        const result = CoordinateTransform.horizontalToEquatorial(
                                            altSpin.value, azSpin.value, lat, lon, elev)
                                        return "→ RA: " + result.ra.toFixed(2) + "°, Dec: " + result.dec.toFixed(2) + "°"
                                    }
                                    return ""
                                }
                            }

                            Button {
                                Layout.fillWidth: true
                                text: "Move"
                                enabled: telescopeDelegate.motionReady && (
                                    (moveTypeCombo.currentText === "RA/Dec" && raField.acceptableInput && decField.acceptableInput)
                                    || moveTypeCombo.currentText === "Alt/Az")
                                onClicked: {
                                    if (moveTypeCombo.currentText === "RA/Dec") {
                                        telescopeDelegate.runWithParams(
                                            "move_radec", [parseFloat(raField.text), parseFloat(decField.text)])
                                    } else if (moveTypeCombo.currentText === "Alt/Az") {
                                        telescopeDelegate.runWithParams(
                                            "move_altaz", [altSpin.value, azSpin.value])
                                    }
                                }
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
                    // for - no separate read-only label needed. Unlike
                    // CameraView.qml's Window/Gain (fetch-once, apply-on-
                    // Expose), offsets keep their own immediate Set/Reset
                    // buttons - there's no equivalent "shutter action" here
                    // to batch onto, matching telescopewidget.ui's own
                    // per-row set/reset buttons.
                    GroupBox {
                        title: "Offsets"
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 220
                        visible: telescopeDelegate.raDecOffsetsInterface !== null || telescopeDelegate.altAzOffsetsInterface !== null

                        ColumnLayout {
                            width: parent.width
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: telescopeDelegate.raDecOffsetsInterface !== null
                                spacing: 4

                                Label { text: "RA/Dec [arcsec]"; color: "grey" }
                                RowLayout {
                                    Layout.fillWidth: true
                                    SpinBox {
                                        id: raOffsetSpin
                                        Layout.fillWidth: true
                                        from: -3600
                                        to: 3600
                                        value: 0
                                        editable: true
                                    }
                                    SpinBox {
                                        id: decOffsetSpin
                                        Layout.fillWidth: true
                                        from: -3600
                                        to: 3600
                                        value: 0
                                        editable: true
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Button {
                                        Layout.fillWidth: true
                                        text: "Set"
                                        enabled: telescopeDelegate.motionReady
                                        onClicked: telescopeDelegate.runWithParams(
                                            "set_offsets_radec", [raOffsetSpin.value / 3600, decOffsetSpin.value / 3600])
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        text: "Reset"
                                        enabled: telescopeDelegate.motionReady
                                        onClicked: {
                                            raOffsetSpin.value = 0
                                            decOffsetSpin.value = 0
                                            telescopeDelegate.runWithParams("set_offsets_radec", [0, 0])
                                        }
                                    }
                                }
                            }

                            // Schema-verified only, not live-pixel-verified - no
                            // built-in Dummy* module implements IOffsetsAltAz (see
                            // DEVELOPMENT.md).
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: telescopeDelegate.altAzOffsetsInterface !== null
                                spacing: 4

                                Label { text: "Alt/Az [arcsec]"; color: "grey" }
                                RowLayout {
                                    Layout.fillWidth: true
                                    SpinBox {
                                        id: altOffsetSpin
                                        Layout.fillWidth: true
                                        from: -3600
                                        to: 3600
                                        value: 0
                                        editable: true
                                    }
                                    SpinBox {
                                        id: azOffsetSpin
                                        Layout.fillWidth: true
                                        from: -3600
                                        to: 3600
                                        value: 0
                                        editable: true
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Button {
                                        Layout.fillWidth: true
                                        text: "Set"
                                        enabled: telescopeDelegate.motionReady
                                        onClicked: telescopeDelegate.runWithParams(
                                            "set_offsets_altaz", [altOffsetSpin.value / 3600, azOffsetSpin.value / 3600])
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        text: "Reset"
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

                    // --- Fourth column: telescopewidget.ui's own fourth
                    // sidebar (Filter/Focus/Temperatures), out of scope
                    // until a direct follow-up (see the file header
                    // comment) shipped it, then generalized into the same
                    // fully generic SidebarPanelRegistry-driven Repeater
                    // as CameraView.qml's own third column, then factored
                    // into SidebarColumn.qml (resize handle + collapse
                    // toggle, shared width/collapsed state) once this page
                    // needed that identically too - see that file's own
                    // header comment.
                    SidebarColumn {
                        Layout.alignment: Qt.AlignTop
                        xmppClient: root.xmppClient
                        appSettings: root.appSettings
                        jid: telescopeDelegate.jid
                        moduleName: telescopeDelegate.name
                        statefulInterfaces: telescopeDelegate.statefulInterfaces
                        availableFilters: telescopeDelegate.filters
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
