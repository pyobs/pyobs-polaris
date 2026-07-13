import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

import "../widgets/Permissions.js" as Permissions

// Dedicated page for ITelescope modules, ported from pyobs-gui's
// telescopewidget.py - MVP scope only (see TODO.md for what's
// deliberately out of scope: solar-frame pointing, MPC lookups,
// orbit-elements lookups). Sexagesimal RA/Dec input, SIMBAD name
// resolution, JPL Horizons ephemeris lookup, and the jog/compass widget
// used to be on that list too - all four shipped as direct follow-ups:
// Move's RA/Dec fields now accept "12:00:00"/"45:30:00" alongside plain
// decimal degrees via the Sexagesimal QML singleton (src/util/
// Sexagesimal.h - see that file's own comment for the parsing rule and
// why a bare number still means degrees, not hours, unlike pyobs-gui's
// own astropy-based parsing); a "Simbad" button next to a name field
// resolves any SIMBAD-known identifier ("M31", "Sirius", ...) straight
// into those same fields via comm::SimbadClient (src/comm/SimbadClient.h
// - talks SIMBAD's own TAP/ADQL service directly, no astroquery
// dependency needed); and a "JPL Horizons" button does the same for
// solar-system bodies ("Ceres", "499" for Mars, ...) via
// comm::JplHorizonsClient (src/comm/JplHorizonsClient.h - same "talk the
// HTTP API directly" reasoning, but a genuinely different kind of lookup
// than Simbad's: a computed *current* position for a moving body, not a
// fixed catalog one). ITelescope itself is a bare IMotion marker
// (confirmed against pyobs.interfaces.ITelescope source), so the base
// block below is identical to RoofView.qml's; Status/Move/Offsets stack
// under it, each gated on the module actually implementing the relevant
// capability interface (IPointingRaDec/IPointingAltAz/IOffsetsRaDec/
// IOffsetsAltAz) - see DEVELOPMENT.md for the live-verification caveat
// around IOffsetsAltAz specifically.
//
// Layout: five GroupBoxes side by side (Status/Move/Offsets/Compass/
// Filter-Focus-Temperatures), the first four ported from
// telescopewidget.ui's own QHBoxLayout structure (read directly) -
// Compass (compassmovewidget.py's N/S/E/W jog buttons) was the last of
// that original four to ship, see its own GroupBox comment below for the
// design decisions. The fifth column (Filter/Focus/Temperatures) was out
// of scope initially (this page only carried the three original
// Status/Move/Offsets columns) but shipped in a
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
// src/util/CoordinateTransform.h), fed by the connected module's own
// reported observer location (IModule capabilities' ModuleLocation,
// pyobs-core 2.0.0.dev18+ - see ModuleListModel.h's own
// ModuleLocationRole comment). pyobs-core had no wire path for this at
// all before dev18 (confirmed against source - the legacy Python GUI
// only ever had it via in-process Python object sharing, never
// serialized to XMPP), so this page originally carried its own
// client-side-only AppSettings entry instead; that's gone now that a
// real one exists - a connected ITelescope module is expected to always
// report its location, and one that doesn't is treated as an error (see
// telescopeDelegate's own hasModuleLocation comment), not silently
// worked around. Purely informational either way - never changes what
// move_radec()/move_altaz() actually send.
//
// Redesign pass (chat-driven, no ticket): the outer per-module container
// switched from RowLayout to Flow so Status/Move/Offsets/Sidebar reflow
// onto a second line on a narrower window instead of clipping (the old
// RowLayout's fixed preferred widths summed past 1000px, and the page
// only had a vertical ScrollView around it). Move's Simbad/JPL Horizons
// lookup fields are now behind a "Find by name" disclosure, collapsed by
// default, so the primary type-coordinates-and-Move flow isn't preceded
// by two full name-lookup forms every time. The standalone Compass
// GroupBox (N/S/E/W jog buttons) was folded into Offsets as a jog row
// above the RA/Dec/Alt/Az spin boxes - it operated on the exact same
// persistent offset state Offsets already displayed, so a separate panel
// next to it read as two disconnected controls for one value.
ScrollView {
    id: root

    required property var xmppClient
    required property var appSettings
    required property var simbadClient
    required property var jplHorizonsClient

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
                required property var moduleLocation
                required property var permittedMethods

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

                // Observer location - a real ITelescope module is always
                // expected to report one (IModule capabilities'
                // ModuleLocation, pyobs-core 2.0.0.dev18+, see
                // ModuleListModel.h's own ModuleLocationRole comment); a
                // connected telescope that doesn't is treated as a real
                // error condition to surface, not silently worked around
                // (direct instruction - this page used to fall back to a
                // client-side-only AppSettings entry from before dev18
                // existed, since pyobs-core had no wire path for this at
                // all; that fallback is gone now that there's a real one).
                // moduleLocation is always a QVariantMap (never null/
                // undefined - ModuleListModel returns an empty one, never
                // an absent role value), so checking for a known key's
                // presence is enough to tell "module reported one" apart
                // from "didn't".
                readonly property bool hasModuleLocation: telescopeDelegate.moduleLocation.latitude !== undefined

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

                // Compass GroupBox's own N/S/E/W handler (compassmovewidget.py's
                // __move_offset(), same fallback chain: IOffsetsRaDec directly if
                // present, else IOffsetsAltAz only when the module also reports
                // IPointingAltAz - needed to convert the compass's sky-relative
                // step into an alt/az-frame offset). compassStepSpin is a forward
                // id reference into the Compass GroupBox below, same idiom
                // raOffsetSpin/decOffsetSpin already rely on from
                // onRaDecOffsetsStateChanged above.
                // The RPC method the Compass buttons actually call - same
                // IOffsetsRaDec-first fallback chain moveCompass() itself
                // uses below, and the Compass GroupBox's own visibility
                // condition - factored out here purely so the Compass
                // buttons' enabled: binding can gate on the right method
                // name without duplicating that fallback chain a third time.
                readonly property string compassMethod: telescopeDelegate.raDecOffsetsInterface !== null
                    ? "set_offsets_radec" : "set_offsets_altaz"

                function moveCompass(direction) {
                    const stepDeg = compassStepSpin.value / 3600
                    if (telescopeDelegate.raDecOffsetsInterface !== null) {
                        let ra = telescopeDelegate.fieldOf(telescopeDelegate.raDecOffsetsState, "ra") || 0
                        let dec = telescopeDelegate.fieldOf(telescopeDelegate.raDecOffsetsState, "dec") || 0
                        if (direction === "N") dec += stepDeg
                        else if (direction === "S") dec -= stepDeg
                        else if (direction === "E") ra += stepDeg
                        else if (direction === "W") ra -= stepDeg
                        telescopeDelegate.runWithParams("set_offsets_radec", [ra, dec])
                    } else if (telescopeDelegate.altAzOffsetsInterface !== null && telescopeDelegate.altAzPointingInterface !== null) {
                        if (!telescopeDelegate.hasModuleLocation) {
                            return
                        }
                        const lat = telescopeDelegate.moduleLocation.latitude
                        const lon = telescopeDelegate.moduleLocation.longitude
                        const elev = telescopeDelegate.moduleLocation.elevation
                        const alt0 = telescopeDelegate.currentAlt
                        const az0 = telescopeDelegate.currentAz
                        if (alt0 === undefined || alt0 === null || az0 === undefined || az0 === null) {
                            return
                        }
                        const offAlt = telescopeDelegate.fieldOf(telescopeDelegate.altAzOffsetsState, "alt") || 0
                        const offAz = telescopeDelegate.fieldOf(telescopeDelegate.altAzOffsetsState, "az") || 0

                        // Re-express the current alt/az offset as an equivalent
                        // ra/dec delta at the telescope's current pointing (a
                        // two-point difference through CoordinateTransform's
                        // existing libnova-backed position transform, the same
                        // singleton the Move destination preview above already
                        // uses - not pyobs-gui's own astropy
                        // spherical_offsets_by()/spherical_offsets_to(), which
                        // isn't available here), apply the compass step in ra/dec
                        // terms, then convert the result back to an alt/az
                        // offset. Schema-verified only, like the Offsets
                        // GroupBox's own Alt/Az row above - no built-in Dummy*
                        // module implements IOffsetsAltAz to test this against
                        // live (see DEVELOPMENT.md).
                        const base = CoordinateTransform.horizontalToEquatorial(alt0, az0, lat, lon, elev)
                        const offsetPointing = CoordinateTransform.horizontalToEquatorial(alt0 + offAlt, az0 + offAz, lat, lon, elev)
                        let dRa = offsetPointing.ra - base.ra
                        let dDec = offsetPointing.dec - base.dec
                        if (direction === "N") dDec += stepDeg
                        else if (direction === "S") dDec -= stepDeg
                        else if (direction === "E") dRa += stepDeg
                        else if (direction === "W") dRa -= stepDeg
                        const target = CoordinateTransform.equatorialToHorizontal(base.ra + dRa, base.dec + dDec, lat, lon, elev)
                        telescopeDelegate.runWithParams("set_offsets_altaz", [target.alt - alt0, target.az - az0])
                    }
                }

                // Simbad name resolution (see the Move GroupBox's own
                // comment on this feature) - root.simbadClient is one
                // shared instance (like root.vfsClient in CameraView.qml),
                // so a query's own requestId (jid + a timestamp, unique
                // enough here - never more than one query in flight per
                // delegate at a time, guarded by simbadQuerying) is
                // needed to tell this delegate's own signal apart from
                // any other connected ITelescope module's simultaneous
                // query, same correlation idiom CameraView.qml's own
                // pendingRequestId already uses for vfsClient.
                property string pendingSimbadRequestId: ""
                property bool simbadQuerying: false
                property string simbadStatusText: ""
                property bool simbadStatusIsError: false

                Connections {
                    target: root.simbadClient
                    function onQueryReady(requestId, ra, dec, mainId) {
                        if (requestId !== telescopeDelegate.pendingSimbadRequestId
                                || telescopeDelegate.pendingSimbadRequestId === "") {
                            return
                        }
                        telescopeDelegate.pendingSimbadRequestId = ""
                        telescopeDelegate.simbadQuerying = false
                        telescopeDelegate.simbadStatusIsError = false
                        telescopeDelegate.simbadStatusText = "→ " + mainId + ": RA " + ra.toFixed(6)
                            + "°, Dec " + dec.toFixed(6) + "°"
                        raField.text = ra.toFixed(6)
                        decField.text = dec.toFixed(6)
                    }
                    function onQueryFailed(requestId, errorMessage) {
                        if (requestId !== telescopeDelegate.pendingSimbadRequestId
                                || telescopeDelegate.pendingSimbadRequestId === "") {
                            return
                        }
                        telescopeDelegate.pendingSimbadRequestId = ""
                        telescopeDelegate.simbadQuerying = false
                        telescopeDelegate.simbadStatusIsError = true
                        telescopeDelegate.simbadStatusText = errorMessage
                    }
                }

                // JPL Horizons name resolution - same shape as the Simbad
                // block above (own requestId/querying/status properties,
                // own Connections block against root.jplHorizonsClient),
                // kept as an entirely separate set of properties rather
                // than sharing Simbad's so a user can freely use either
                // (or both, one after the other) without them clobbering
                // each other's in-flight state.
                property string pendingJplHorizonsRequestId: ""
                property bool jplHorizonsQuerying: false
                property string jplHorizonsStatusText: ""
                property bool jplHorizonsStatusIsError: false

                Connections {
                    target: root.jplHorizonsClient
                    function onQueryReady(requestId, ra, dec, targetName) {
                        if (requestId !== telescopeDelegate.pendingJplHorizonsRequestId
                                || telescopeDelegate.pendingJplHorizonsRequestId === "") {
                            return
                        }
                        telescopeDelegate.pendingJplHorizonsRequestId = ""
                        telescopeDelegate.jplHorizonsQuerying = false
                        telescopeDelegate.jplHorizonsStatusIsError = false
                        telescopeDelegate.jplHorizonsStatusText = "→ " + targetName + ": RA " + ra.toFixed(6)
                            + "°, Dec " + dec.toFixed(6) + "°"
                        raField.text = ra.toFixed(6)
                        decField.text = dec.toFixed(6)
                    }
                    function onQueryFailed(requestId, errorMessage) {
                        if (requestId !== telescopeDelegate.pendingJplHorizonsRequestId
                                || telescopeDelegate.pendingJplHorizonsRequestId === "") {
                            return
                        }
                        telescopeDelegate.pendingJplHorizonsRequestId = ""
                        telescopeDelegate.jplHorizonsQuerying = false
                        telescopeDelegate.jplHorizonsStatusIsError = true
                        telescopeDelegate.jplHorizonsStatusText = errorMessage
                    }
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

                    // Status/Move/Offsets reflow independently inside this
                    // Flow; the sidebar below is a sibling of the Flow, not
                    // one of its wrapped children, specifically so it always
                    // keeps its own fixed size and stays pinned to the top
                    // of the row no matter how many rows the Flow wraps
                    // into (a shared Flow child would get pushed down and
                    // have its width fought over along with everything
                    // else).
                    Flow {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
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

                            // Color-coded, matching telescopewidget.py's own
                            // colorize_button() calls (green Init/yellow
                            // Park/red Stop/blue Move, all black-on-color
                            // there via Qt::GlobalColor - this project's own
                            // dark theme already established a muted-shade-
                            // plus-white-text convention instead for the same
                            // semantic colors, see CameraView.qml's green
                            // Expose/red Abort; yellow is the one exception
                            // kept black-on-color here, same as pyobs-gui,
                            // since white text on a light amber background
                            // reads poorly).
                            RowLayout {
                                Layout.fillWidth: true
                                Button {
                                    Layout.fillWidth: true
                                    text: "Init"
                                    enabled: telescopeDelegate.running === "" && Permissions.isPermitted(telescopeDelegate.permittedMethods, "init")
                                    palette.button: "#2e7d32"
                                    palette.buttonText: "white"
                                    onClicked: telescopeDelegate.run("init", 0)
                                }
                                Button {
                                    Layout.fillWidth: true
                                    text: "Park"
                                    enabled: telescopeDelegate.running === "" && Permissions.isPermitted(telescopeDelegate.permittedMethods, "park")
                                    palette.button: "#f9a825"
                                    palette.buttonText: "black"
                                    onClicked: telescopeDelegate.run("park", 0)
                                }
                                Button {
                                    Layout.fillWidth: true
                                    text: "Stop"
                                    enabled: telescopeDelegate.running === "" && Permissions.isPermitted(telescopeDelegate.permittedMethods, "stop_motion")
                                    palette.button: "#c62828"
                                    palette.buttonText: "white"
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

                            // Observer location itself is never shown here -
                            // it's read straight off the module's own
                            // reported ModuleLocation (pyobs-core
                            // 2.0.0.dev18+, see telescopeDelegate's own
                            // hasModuleLocation comment) purely as input to
                            // the destination-coordinate preview below, not
                            // something a user needs to look at or edit
                            // (direct instruction). A connected ITelescope
                            // module is always expected to report one, so a
                            // missing one is surfaced as an error rather
                            // than silently degrading - there's no
                            // client-side fallback to fall back to anymore.
                            Label {
                                Layout.fillWidth: true
                                visible: !telescopeDelegate.hasModuleLocation
                                text: "This telescope module did not report an observer location "
                                    + "(requires pyobs-core 2.0.0.dev18+ with a location configured) "
                                    + "- destination-coordinate preview unavailable."
                                color: "red"
                                wrapMode: Text.WordWrap
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

                            // Name-lookup helpers (SIMBAD + JPL Horizons),
                            // collapsed behind a disclosure by default - both
                            // fill raField/decField below but aren't needed
                            // for the common "I already have coordinates"
                            // path, so they no longer sit permanently open
                            // between the coordinate-type combo and the
                            // fields they feed.
                            ColumnLayout {
                                id: findByNameSection
                                Layout.fillWidth: true
                                visible: moveTypeCombo.currentText === "RA/Dec"
                                spacing: 4

                                property bool expanded: false

                                Button {
                                    flat: true
                                    Layout.fillWidth: true
                                    text: (findByNameSection.expanded ? "▾ " : "▸ ") + "Find by name (Simbad / JPL Horizons)"
                                    onClicked: findByNameSection.expanded = !findByNameSection.expanded
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: findByNameSection.expanded
                                    spacing: 6

                                    // SIMBAD name resolution - ports pyobs-gui's own
                                    // buttonSimbadQuery/textSimbadName (telescopewidget.py's
                                    // _query_simbad()), which fills the RA/Dec fields from
                                    // an object name via astroquery's Simbad.query_object().
                                    // This talks SIMBAD's own TAP/ADQL service directly
                                    // instead (comm::SimbadClient, src/comm/SimbadClient.h)
                                    // - no astroquery/VOTable dependency needed once a
                                    // plain CSV response is requested instead of the
                                    // service's own VOTable/XML default. Fills plain
                                    // decimal degrees (not pyobs-gui's own sexagesimal
                                    // "hmsdms" display) - simpler, and exactly as valid an
                                    // input to raField/decField below as sexagesimal
                                    // notation is, so no separate formatting code was
                                    // needed just for this.
                                    RowLayout {
                                        Layout.fillWidth: true

                                        TextField {
                                            id: simbadNameField
                                            Layout.fillWidth: true
                                            placeholderText: "Simbad object name (e.g. M31, Sirius)"
                                            enabled: !telescopeDelegate.simbadQuerying
                                        }
                                        Button {
                                            text: telescopeDelegate.simbadQuerying ? "Querying…" : "Simbad"
                                            palette.button: "#2e7d32"
                                            palette.buttonText: "white"
                                            enabled: !telescopeDelegate.simbadQuerying && simbadNameField.text.length > 0
                                            onClicked: {
                                                const requestId = telescopeDelegate.jid + "|simbad|" + Date.now()
                                                telescopeDelegate.pendingSimbadRequestId = requestId
                                                telescopeDelegate.simbadQuerying = true
                                                telescopeDelegate.simbadStatusText = ""
                                                root.simbadClient.queryByName(requestId, simbadNameField.text)
                                            }
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        visible: telescopeDelegate.simbadStatusText.length > 0
                                        text: telescopeDelegate.simbadStatusText
                                        color: telescopeDelegate.simbadStatusIsError ? "red" : "grey"
                                        wrapMode: Text.WordWrap
                                    }

                                    // JPL Horizons name resolution - ports pyobs-gui's own
                                    // buttonJplHorizonsQuery/textJplHorizonsName
                                    // (telescopewidget.py's _query_jpl_horizons()). Unlike
                                    // Simbad above (a fixed catalog position), Horizons
                                    // computes a solar-system body's actual current
                                    // position (light-time corrected, for "now") rather
                                    // than a static one - meaningfully different data, not
                                    // just a different data source, hence its own separate
                                    // field/button/status rather than merging with Simbad's.
                                    // Talks Horizons' own HTTP API directly
                                    // (comm::JplHorizonsClient, src/comm/JplHorizonsClient.h),
                                    // same "no astroquery dependency needed" reasoning as
                                    // SimbadClient.
                                    RowLayout {
                                        Layout.fillWidth: true

                                        TextField {
                                            id: jplHorizonsNameField
                                            Layout.fillWidth: true
                                            placeholderText: "JPL Horizons body name (e.g. Ceres, Mars)"
                                            enabled: !telescopeDelegate.jplHorizonsQuerying
                                        }
                                        Button {
                                            text: telescopeDelegate.jplHorizonsQuerying ? "Querying…" : "JPL Horizons"
                                            palette.button: "#2e7d32"
                                            palette.buttonText: "white"
                                            enabled: !telescopeDelegate.jplHorizonsQuerying && jplHorizonsNameField.text.length > 0
                                            onClicked: {
                                                const requestId = telescopeDelegate.jid + "|jplhorizons|" + Date.now()
                                                telescopeDelegate.pendingJplHorizonsRequestId = requestId
                                                telescopeDelegate.jplHorizonsQuerying = true
                                                telescopeDelegate.jplHorizonsStatusText = ""
                                                root.jplHorizonsClient.queryByName(requestId, jplHorizonsNameField.text)
                                            }
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        visible: telescopeDelegate.jplHorizonsStatusText.length > 0
                                        text: telescopeDelegate.jplHorizonsStatusText
                                        color: telescopeDelegate.jplHorizonsStatusIsError ? "red" : "grey"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            GridLayout {
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 4
                                Layout.fillWidth: true
                                visible: moveTypeCombo.currentText === "RA/Dec"

                                // Accepts either plain decimal degrees
                                // (unchanged from before, e.g. "180.5") or
                                // sexagesimal notation (e.g. "12:00:00" -
                                // hours for RA, "45:30:00" for Dec; colon,
                                // space, or h/m/s-letter separators all
                                // work, seconds optional) via the
                                // Sexagesimal QML singleton (src/util/
                                // Sexagesimal.h) - previously out of scope
                                // (TODO.md), a direct follow-up request.
                                // No `validator: DoubleValidator{}` (that
                                // would reject the colons/letters
                                // sexagesimal notation needs) - validity
                                // is instead computed via
                                // Sexagesimal.parseRa()/parseDec() not
                                // being NaN, checked directly wherever
                                // `acceptableInput` would have been used
                                // (the Move button's `enabled` below).
                                Label { text: "RA:" }
                                TextField {
                                    id: raField
                                    Layout.fillWidth: true
                                    placeholderText: "180.5 or 12:00:00"
                                }
                                Label { text: "Dec:" }
                                TextField {
                                    id: decField
                                    Layout.fillWidth: true
                                    placeholderText: "45.0 or 45:00:00"
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
                                visible: telescopeDelegate.hasModuleLocation
                                color: "grey"
                                wrapMode: Text.WordWrap
                                text: {
                                    // moduleLocation is a plain (required)
                                    // property, not a Q_INVOKABLE method
                                    // call - reading it here establishes a
                                    // real QML binding dependency on its own
                                    // (unlike the old AppSettings.
                                    // hasObserverLocation() this replaced,
                                    // which needed a workaround for exactly
                                    // that reason - see git history if this
                                    // comment outlives that fix).
                                    const lat = telescopeDelegate.moduleLocation.latitude
                                    const lon = telescopeDelegate.moduleLocation.longitude
                                    const elev = telescopeDelegate.moduleLocation.elevation
                                    if (moveTypeCombo.currentText === "RA/Dec") {
                                        const ra = Sexagesimal.parseRa(raField.text)
                                        const dec = Sexagesimal.parseDec(decField.text)
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
                                palette.button: "#1565c0"
                                palette.buttonText: "white"
                                enabled: telescopeDelegate.motionReady && (
                                    (moveTypeCombo.currentText === "RA/Dec"
                                        && !isNaN(Sexagesimal.parseRa(raField.text))
                                        && !isNaN(Sexagesimal.parseDec(decField.text))
                                        && Permissions.isPermitted(telescopeDelegate.permittedMethods, "move_radec"))
                                    || (moveTypeCombo.currentText === "Alt/Az"
                                        && Permissions.isPermitted(telescopeDelegate.permittedMethods, "move_altaz")))
                                onClicked: {
                                    if (moveTypeCombo.currentText === "RA/Dec") {
                                        telescopeDelegate.runWithParams(
                                            "move_radec", [Sexagesimal.parseRa(raField.text), Sexagesimal.parseDec(decField.text)])
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
                    //
                    // The jog row at the top used to be a separate Compass
                    // GroupBox (compassmovewidget.py's N/S/E/W jog buttons,
                    // nudging the same persistent offset one step at a time
                    // rather than typing an absolute value) - folded in here
                    // since it operated on the exact same offset state this
                    // box already displays, and having it as its own
                    // adjacent panel read as two disconnected controls for
                    // one value. Same fallback chain as before (IOffsetsRaDec
                    // directly if present, else IOffsetsAltAz only when the
                    // module also reports IPointingAltAz - see moveCompass()
                    // above), just relocated.
                    GroupBox {
                        title: "Offsets"
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 240
                        visible: telescopeDelegate.raDecOffsetsInterface !== null || telescopeDelegate.altAzOffsetsInterface !== null

                        ColumnLayout {
                            width: parent.width
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                visible: telescopeDelegate.raDecOffsetsInterface !== null
                                    || (telescopeDelegate.altAzOffsetsInterface !== null && telescopeDelegate.altAzPointingInterface !== null)
                                spacing: 4

                                Label { text: "Jog step [arcsec]:"; color: "grey" }
                                SpinBox {
                                    id: compassStepSpin
                                    Layout.preferredWidth: 70
                                    from: 0
                                    to: 999
                                    stepSize: 10
                                    value: 30
                                    editable: true
                                }
                                Item { Layout.fillWidth: true }
                                Button {
                                    text: "▲"
                                    Layout.preferredWidth: 32
                                    enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, telescopeDelegate.compassMethod)
                                    palette.button: "#1565c0"
                                    palette.buttonText: "white"
                                    onClicked: telescopeDelegate.moveCompass("N")
                                }
                                Button {
                                    text: "◀"
                                    Layout.preferredWidth: 32
                                    enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, telescopeDelegate.compassMethod)
                                    palette.button: "#1565c0"
                                    palette.buttonText: "white"
                                    onClicked: telescopeDelegate.moveCompass("W")
                                }
                                Button {
                                    text: "▶"
                                    Layout.preferredWidth: 32
                                    enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, telescopeDelegate.compassMethod)
                                    palette.button: "#1565c0"
                                    palette.buttonText: "white"
                                    onClicked: telescopeDelegate.moveCompass("E")
                                }
                                Button {
                                    text: "▼"
                                    Layout.preferredWidth: 32
                                    enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, telescopeDelegate.compassMethod)
                                    palette.button: "#1565c0"
                                    palette.buttonText: "white"
                                    onClicked: telescopeDelegate.moveCompass("S")
                                }
                            }

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
                                        enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, "set_offsets_radec")
                                        palette.button: "#2e7d32"
                                        palette.buttonText: "white"
                                        onClicked: telescopeDelegate.runWithParams(
                                            "set_offsets_radec", [raOffsetSpin.value / 3600, decOffsetSpin.value / 3600])
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        text: "Reset"
                                        enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, "set_offsets_radec")
                                        palette.button: "#f9a825"
                                        palette.buttonText: "black"
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
                                        enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, "set_offsets_altaz")
                                        palette.button: "#2e7d32"
                                        palette.buttonText: "white"
                                        onClicked: telescopeDelegate.runWithParams(
                                            "set_offsets_altaz", [altOffsetSpin.value / 3600, azOffsetSpin.value / 3600])
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        text: "Reset"
                                        enabled: telescopeDelegate.motionReady && Permissions.isPermitted(telescopeDelegate.permittedMethods, "set_offsets_altaz")
                                        palette.button: "#f9a825"
                                        palette.buttonText: "black"
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

                    // --- Sidebar: telescopewidget.ui's own fourth sidebar
                    // (Filter/Focus/Temperatures), out of scope until a
                    // direct follow-up (see the file header comment)
                    // shipped it, then generalized into the same fully
                    // generic SidebarPanelRegistry-driven Repeater as
                    // CameraView.qml's own third column, then factored into
                    // SidebarColumn.qml (resize handle + collapse toggle,
                    // shared width/collapsed state) once this page needed
                    // that identically too - see that file's own header
                    // comment. Kept as a sibling of the Flow above (see that
                    // Flow's own comment) rather than one of its wrapped
                    // children, so it never moves or resizes as
                    // Status/Move/Offsets reflow.
                    SidebarColumn {
                        Layout.alignment: Qt.AlignTop
                        xmppClient: root.xmppClient
                        appSettings: root.appSettings
                        jid: telescopeDelegate.jid
                        moduleName: telescopeDelegate.name
                        statefulInterfaces: telescopeDelegate.statefulInterfaces
                        availableFilters: telescopeDelegate.filters
                        permittedMethods: telescopeDelegate.permittedMethods
                    }
                }
            }
        }
    }
}
