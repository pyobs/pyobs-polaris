import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Dedicated page for ICamera modules, ported from pyobs-gui's
// camerawidget.py - MVP scope only (control, no image display; see
// TODO.md's "ICamera follow-up" for the deferred VFS/FITS/image-viewer
// half). ICamera itself is IData + IExposure (confirmed from source) -
// IExposure's state class is inherited by ICamera the same way IMotion's
// is inherited by ITelescope (TelescopeView.qml), so this subscribes to
// "IExposure" specifically (the interface that actually originates the
// state), gating visibility on "ICamera" (the specific marker), same
// split RoofView.qml/TelescopeView.qml already use. Everything below
// IExposure is capability-gated per interface, following the exact
// findInterface()/visible/refreshSubscriptions() shape every custom
// widget here already uses, just with more of them at once than any
// prior widget (up to eight simultaneous StateSubscriptions per module).
ScrollView {
    id: root

    required property var xmppClient
    required property var vfsEndpoints
    required property var vfsClient

    clip: true

    ColumnLayout {
        width: root.availableWidth
        spacing: 8

        Label {
            text: "Camera"
            font.bold: true
            font.pixelSize: 16
        }

        Repeater {
            model: root.xmppClient.modules

            // Same in-place-update caveat as every other custom widget's
            // Repeater here - this model is a real QAbstractListModel, so
            // delegates are updated in place rather than recreated.
            delegate: ColumnLayout {
                id: cameraDelegate
                Layout.fillWidth: true

                required property string jid
                required property string name
                required property var statefulInterfaces
                required property var binningOptions
                required property var windowExtent
                required property var imageFormats

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

                visible: findInterface("ICamera") !== null

                readonly property var exposureInterface: findInterface("IExposure")
                readonly property var imageTypeInterface: findInterface("IImageType")
                readonly property var exposureTimeInterface: findInterface("IExposureTime")
                readonly property var binningInterface: findInterface("IBinning")
                readonly property var windowInterface: findInterface("IWindow")
                readonly property var gainInterface: findInterface("IGain")
                readonly property var imageFormatInterface: findInterface("IImageFormat")
                readonly property var coolingInterface: findInterface("ICooling")
                readonly property bool hasAbort: findInterface("IAbortable") !== null

                property var exposureSubscription: null
                property var imageTypeSubscription: null
                property var exposureTimeSubscription: null
                property var binningSubscription: null
                property var windowSubscription: null
                property var gainSubscription: null
                property var imageFormatSubscription: null
                property var coolingSubscription: null

                function refreshSubscriptions() {
                    if (exposureSubscription) { exposureSubscription.unsubscribe(); exposureSubscription = null }
                    if (imageTypeSubscription) { imageTypeSubscription.unsubscribe(); imageTypeSubscription = null }
                    if (exposureTimeSubscription) { exposureTimeSubscription.unsubscribe(); exposureTimeSubscription = null }
                    if (binningSubscription) { binningSubscription.unsubscribe(); binningSubscription = null }
                    if (windowSubscription) { windowSubscription.unsubscribe(); windowSubscription = null }
                    if (gainSubscription) { gainSubscription.unsubscribe(); gainSubscription = null }
                    if (imageFormatSubscription) { imageFormatSubscription.unsubscribe(); imageFormatSubscription = null }
                    if (coolingSubscription) { coolingSubscription.unsubscribe(); coolingSubscription = null }

                    if (visible && exposureInterface) {
                        exposureSubscription = root.xmppClient.subscribeState(
                            jid, "IExposure", exposureInterface.version, cameraDelegate)
                    }
                    if (visible && imageTypeInterface) {
                        imageTypeSubscription = root.xmppClient.subscribeState(
                            jid, "IImageType", imageTypeInterface.version, cameraDelegate)
                    }
                    if (visible && exposureTimeInterface) {
                        exposureTimeSubscription = root.xmppClient.subscribeState(
                            jid, "IExposureTime", exposureTimeInterface.version, cameraDelegate)
                    }
                    if (visible && binningInterface) {
                        binningSubscription = root.xmppClient.subscribeState(
                            jid, "IBinning", binningInterface.version, cameraDelegate)
                    }
                    if (visible && windowInterface) {
                        windowSubscription = root.xmppClient.subscribeState(
                            jid, "IWindow", windowInterface.version, cameraDelegate)
                    }
                    if (visible && gainInterface) {
                        gainSubscription = root.xmppClient.subscribeState(
                            jid, "IGain", gainInterface.version, cameraDelegate)
                    }
                    if (visible && imageFormatInterface) {
                        imageFormatSubscription = root.xmppClient.subscribeState(
                            jid, "IImageFormat", imageFormatInterface.version, cameraDelegate)
                    }
                    if (visible && coolingInterface) {
                        coolingSubscription = root.xmppClient.subscribeState(
                            jid, "ICooling", coolingInterface.version, cameraDelegate)
                    }
                }

                onVisibleChanged: refreshSubscriptions()
                onExposureInterfaceChanged: refreshSubscriptions()
                onImageTypeInterfaceChanged: refreshSubscriptions()
                onExposureTimeInterfaceChanged: refreshSubscriptions()
                onBinningInterfaceChanged: refreshSubscriptions()
                onWindowInterfaceChanged: refreshSubscriptions()
                onGainInterfaceChanged: refreshSubscriptions()
                onImageFormatInterfaceChanged: refreshSubscriptions()
                onCoolingInterfaceChanged: refreshSubscriptions()
                Component.onCompleted: {
                    refreshSubscriptions()
                    checkForNewImage()
                }

                readonly property var exposureState: exposureSubscription ? exposureSubscription.value : undefined
                readonly property var imageTypeState: imageTypeSubscription ? imageTypeSubscription.value : undefined
                readonly property var exposureTimeState: exposureTimeSubscription ? exposureTimeSubscription.value : undefined
                readonly property var binningState: binningSubscription ? binningSubscription.value : undefined
                readonly property var windowState: windowSubscription ? windowSubscription.value : undefined
                readonly property var gainState: gainSubscription ? gainSubscription.value : undefined
                readonly property var imageFormatState: imageFormatSubscription ? imageFormatSubscription.value : undefined
                readonly property var coolingState: coolingSubscription ? coolingSubscription.value : undefined

                readonly property string exposureStatus: fieldOf(exposureState, "status") || ""
                readonly property real exposureProgress: fieldOf(exposureState, "progress") || 0
                readonly property var exposureTimeLeft: fieldOf(exposureState, "exposure_time_left")

                readonly property string currentImageType: fieldOf(imageTypeState, "image_type") || ""
                readonly property int currentBinX: fieldOf(binningState, "x") || 1
                readonly property int currentBinY: fieldOf(binningState, "y") || 1

                property int remainingExposures: 0
                property bool broadcastEnabled: true
                property string lastError: ""

                function grabOne() {
                    root.xmppClient.executeMethod(jid, "grab_data", [cameraDelegate.broadcastEnabled], function (result) {
                        if (!result.success) {
                            cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                            cameraDelegate.remainingExposures = 0
                            return
                        }
                        cameraDelegate.remainingExposures = Math.max(0, cameraDelegate.remainingExposures - 1)
                        if (cameraDelegate.remainingExposures > 0) {
                            cameraDelegate.grabOne()
                        }
                    })
                }

                // --- Image display: grab_data() -> NewImageEvent -> VFS
                // fetch -> FITS decode, the flow TODO.md's "ICamera
                // follow-up" split into three separately-shipped pieces
                // (config::VfsEndpointsModel/comm::VfsClient, then
                // fits::FitsImage/fits::FitsImageItem) - this is what
                // finally wires them together. NewImageEvent delivery
                // itself needs no new C++: EventManager already
                // subscribes to every event a module's disco#info
                // advertises (Phase 6), so this only needs to notice a
                // new one arriving for *this* jid and drive the fetch.
                property string lastImageFilename: ""
                // "", "loading", or "error" - drives the status Label
                // below; "" with fitsImageItem.hasImage true means the
                // currently-shown image is up to date.
                property string imageStatus: ""
                property string imageError: ""
                // Correlates an in-flight VfsClient fetch (and, before
                // that, an in-flight VfsEndpointsModel password load)
                // back to this delegate specifically - both are global
                // per-instance signals, not scoped to one Repeater
                // delegate, since multiple cameras can be fetching
                // concurrently (possibly even from the same VFS
                // endpoint, sharing its password-load request).
                property string pendingRequestId: ""
                property string pendingEndpointId: ""
                property string pendingUrl: ""
                property string pendingUsername: ""

                function checkForNewImage() {
                    // EventLogModel's `module` is the *local part only* of
                    // the sender's JID (EventManager.cpp uses
                    // QXmppUtils::jidToUser()) - jid here is the full bare
                    // JID (e.g. "camera@localhost", see ModuleInfo.h's own
                    // comment), so comparing them directly never matches.
                    // Caught live: NewImageEvent showed up correctly on
                    // the Events page but never triggered a fetch here.
                    const localJid = jid.split("@")[0]
                    const events = root.xmppClient.events.entriesOfType("NewImageEvent")
                    for (let i = events.length - 1; i >= 0; --i) {
                        if (events[i].module !== localJid) {
                            continue
                        }
                        const filename = events[i].data ? events[i].data.filename : undefined
                        if (filename && filename !== cameraDelegate.lastImageFilename) {
                            cameraDelegate.lastImageFilename = filename
                            cameraDelegate.fetchImage(filename)
                        }
                        return
                    }
                }

                function fetchImage(filename) {
                    const resolved = root.vfsEndpoints.resolveVfsPath(filename)
                    if (resolved.url === undefined) {
                        cameraDelegate.imageStatus = "error"
                        cameraDelegate.imageError = "No VFS endpoint configured for \"" + filename
                            + "\" - add one on the Settings page."
                        return
                    }

                    cameraDelegate.imageStatus = "loading"
                    cameraDelegate.imageError = ""
                    cameraDelegate.pendingRequestId = jid + "|" + filename
                    cameraDelegate.pendingUrl = resolved.url
                    cameraDelegate.pendingUsername = resolved.username

                    if (resolved.hasStoredPassword) {
                        cameraDelegate.pendingEndpointId = resolved.endpointId
                        root.vfsEndpoints.loadPassword(resolved.endpointId)
                    } else {
                        root.vfsClient.fetchFile(cameraDelegate.pendingRequestId, resolved.url, resolved.username, "")
                    }
                }

                Connections {
                    target: root.xmppClient.events
                    function onRowsInserted() { cameraDelegate.checkForNewImage() }
                }

                Connections {
                    target: root.vfsEndpoints
                    function onPasswordReady(id, password) {
                        if (id !== cameraDelegate.pendingEndpointId || cameraDelegate.pendingEndpointId === "") {
                            return
                        }
                        cameraDelegate.pendingEndpointId = ""
                        root.vfsClient.fetchFile(
                            cameraDelegate.pendingRequestId, cameraDelegate.pendingUrl,
                            cameraDelegate.pendingUsername, password)
                    }
                    function onPasswordLoadFailed(id) {
                        if (id !== cameraDelegate.pendingEndpointId || cameraDelegate.pendingEndpointId === "") {
                            return
                        }
                        cameraDelegate.pendingEndpointId = ""
                        cameraDelegate.imageStatus = "error"
                        cameraDelegate.imageError = "Could not load the stored password for this VFS endpoint."
                    }
                }

                Connections {
                    target: root.vfsClient
                    function onFileReady(requestId, data) {
                        if (requestId !== cameraDelegate.pendingRequestId) {
                            return
                        }
                        if (fitsImageItem.loadFitsBytes(data)) {
                            cameraDelegate.imageStatus = ""
                            cameraDelegate.imageError = ""
                        } else {
                            cameraDelegate.imageStatus = "error"
                            cameraDelegate.imageError = fitsImageItem.lastError
                        }
                    }
                    function onFileFailed(requestId, errorMessage) {
                        if (requestId !== cameraDelegate.pendingRequestId) {
                            return
                        }
                        cameraDelegate.imageStatus = "error"
                        cameraDelegate.imageError = errorMessage
                    }
                }

                // "was synced" idioms for every capability-gated control
                // below. Each must live here on cameraDelegate - the object
                // that actually owns exposureTimeState/windowState/
                // gainState/currentImageType - since an onXChanged handler
                // only binds to a property on its own object, not one
                // belonging to an ancestor/descendant (same lesson as
                // TelescopeView.qml's Offsets section). imageTypeCombo/
                // exposureTimeSpin/leftSpin.../gainSpin/offsetSpin are
                // forward id references into this same delegate's object
                // tree, resolved once the state actually changes (well
                // after Component.onCompleted).
                property string lastSyncedImageType: ""

                onCurrentImageTypeChanged: {
                    if (currentImageType === "") {
                        return
                    }
                    const wasSynced = lastSyncedImageType === "" || imageTypeCombo.currentValue === lastSyncedImageType
                    lastSyncedImageType = currentImageType
                    if (wasSynced) {
                        const idx = imageTypeCombo.indexOfValue(currentImageType)
                        if (idx >= 0) {
                            imageTypeCombo.currentIndex = idx
                        }
                    }
                }

                property real lastSyncedExposureTime: NaN

                onExposureTimeStateChanged: {
                    const value = fieldOf(exposureTimeState, "exposure_time")
                    if (value === undefined || value === null) {
                        return
                    }
                    const wasSynced = isNaN(lastSyncedExposureTime)
                        || Math.round(exposureTimeSpin.value) === Math.round(lastSyncedExposureTime * 1000)
                    lastSyncedExposureTime = value
                    if (wasSynced) {
                        exposureTimeSpin.value = Math.round(value * 1000)
                    }
                }

                property int lastSyncedLeft: -1
                property int lastSyncedTop: -1
                property int lastSyncedWidth: -1
                property int lastSyncedHeight: -1

                onWindowStateChanged: {
                    const left = fieldOf(windowState, "x")
                    const top = fieldOf(windowState, "y")
                    const width = fieldOf(windowState, "width")
                    const height = fieldOf(windowState, "height")
                    if (left === undefined || left === null) {
                        return
                    }
                    const leftSynced = lastSyncedLeft < 0 || leftSpin.value === lastSyncedLeft
                    const topSynced = lastSyncedTop < 0 || topSpin.value === lastSyncedTop
                    const widthSynced = lastSyncedWidth < 0 || widthSpin.value === lastSyncedWidth
                    const heightSynced = lastSyncedHeight < 0 || heightSpin.value === lastSyncedHeight
                    lastSyncedLeft = left
                    lastSyncedTop = top
                    lastSyncedWidth = width
                    lastSyncedHeight = height
                    if (leftSynced) leftSpin.value = left
                    if (topSynced) topSpin.value = top
                    if (widthSynced) widthSpin.value = width
                    if (heightSynced) heightSpin.value = height
                }

                property real lastSyncedGain: NaN
                property real lastSyncedOffset: NaN

                onGainStateChanged: {
                    const gain = fieldOf(gainState, "gain")
                    const offset = fieldOf(gainState, "offset")
                    if (gain === undefined || gain === null || offset === undefined || offset === null) {
                        return
                    }
                    const gainSynced = isNaN(lastSyncedGain) || Math.round(gainSpin.value) === Math.round(lastSyncedGain * 100)
                    const offsetSynced = isNaN(lastSyncedOffset) || Math.round(offsetSpin.value) === Math.round(lastSyncedOffset * 100)
                    lastSyncedGain = gain
                    lastSyncedOffset = offset
                    if (gainSynced) gainSpin.value = Math.round(gain * 100)
                    if (offsetSynced) offsetSpin.value = Math.round(offset * 100)
                }

                RowLayout {
                    Label {
                        text: cameraDelegate.name
                        font.bold: true
                    }
                    Label {
                        text: cameraDelegate.jid
                        color: "grey"
                    }
                }

                KeyValueCard {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    value: cameraDelegate.exposureState
                }

                ColumnLayout {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: cameraDelegate.exposureProgress
                        }
                        Label {
                            text: cameraDelegate.exposureStatus
                                + (cameraDelegate.exposureTimeLeft !== undefined && cameraDelegate.exposureTimeLeft !== null
                                   ? " (" + cameraDelegate.exposureTimeLeft.toFixed(1) + "s left)" : "")
                        }
                    }

                    RowLayout {
                        Label { text: "Count:" }
                        SpinBox {
                            id: countSpin
                            from: 1
                            to: 999
                            value: 1
                            editable: true
                        }
                        Button {
                            text: "Expose"
                            enabled: cameraDelegate.remainingExposures === 0
                            onClicked: {
                                cameraDelegate.lastError = ""
                                cameraDelegate.remainingExposures = countSpin.value
                                cameraDelegate.grabOne()
                            }
                        }
                        Button {
                            text: cameraDelegate.remainingExposures > 1 ? "Abort Sequence" : "Abort Exposure"
                            visible: cameraDelegate.hasAbort
                            enabled: cameraDelegate.remainingExposures > 0
                            onClicked: {
                                if (cameraDelegate.remainingExposures > 1) {
                                    // Mid-sequence: just stop the client-side
                                    // loop, don't interrupt the exposure
                                    // that's already in flight.
                                    cameraDelegate.remainingExposures = 0
                                } else {
                                    cameraDelegate.remainingExposures = 0
                                    root.xmppClient.executeMethod(jid, "abort", 0, function (result) {
                                        if (!result.success) {
                                            cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                        }
                                    })
                                }
                            }
                        }
                    }

                    RowLayout {
                        CheckBox {
                            id: broadcastCheck
                            text: "Broadcast"
                            checked: cameraDelegate.broadcastEnabled
                            onToggled: {
                                if (checked) {
                                    cameraDelegate.broadcastEnabled = true
                                } else {
                                    broadcastConfirmDialog.open()
                                }
                            }
                        }
                        Dialog {
                            id: broadcastConfirmDialog
                            title: "Disable broadcast?"
                            modal: true
                            standardButtons: Dialog.Yes | Dialog.No
                            anchors.centerIn: Overlay.overlay
                            Label {
                                text: "New images will not be processed or saved. Are you sure?"
                                wrapMode: Text.WordWrap
                            }
                            onAccepted: cameraDelegate.broadcastEnabled = false
                            onRejected: broadcastCheck.checked = true
                        }
                    }
                }

                // --- IImageType: static ImageType enum, not a capability -
                // BIAS disables/zeroes the exposure-time control below
                // (camerawidget.py's own image_type_changed nicety).
                RowLayout {
                    Layout.leftMargin: 8
                    visible: cameraDelegate.imageTypeInterface !== null

                    Label { text: "Image type:" }
                    ComboBox {
                        id: imageTypeCombo
                        textRole: "label"
                        valueRole: "value"
                        model: [
                            { label: "Bias", value: "bias" },
                            { label: "Dark", value: "dark" },
                            { label: "Object", value: "object" },
                            { label: "Sky Flat", value: "skyflat" },
                            { label: "Focus", value: "focus" },
                            { label: "Acquisition", value: "acquisition" },
                            { label: "Guiding", value: "guiding" },
                        ]
                        onActivated: {
                            cameraDelegate.lastError = ""
                            root.xmppClient.executeMethod(jid, "set_image_type", [currentValue], function (result) {
                                if (!result.success) {
                                    cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                }
                            })
                        }
                    }
                }

                // --- IExposureTime: AutoGuidingView.qml's exposure-time
                // SpinBox idiom, verbatim (integer milliseconds, was-synced
                // guard) - disabled while BIAS is selected.
                RowLayout {
                    Layout.leftMargin: 8
                    visible: cameraDelegate.exposureTimeInterface !== null

                    Label { text: "Exposure time:" }
                    SpinBox {
                        id: exposureTimeSpin
                        from: 0
                        to: 3600000
                        value: 1000
                        editable: true
                        enabled: cameraDelegate.currentImageType !== "bias"
                        textFromValue: (value) => (value / 1000).toFixed(3)
                        valueFromText: (text) => Math.round(parseFloat(text) * 1000)
                        onValueModified: {
                            root.xmppClient.executeMethod(jid, "set_exposure_time", [value / 1000], function (result) {
                                if (!result.success) {
                                    cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                }
                            })
                        }
                    }
                    Label { text: "s" }
                }

                // --- IBinning: ComboBox over the binningOptions role
                // ("{x}x{y}" strings), same live-sync/onActivated shape as
                // ModeView.qml's mode ComboBox.
                RowLayout {
                    Layout.leftMargin: 8
                    visible: cameraDelegate.binningInterface !== null

                    readonly property string currentBinning: cameraDelegate.binningState !== undefined
                        ? cameraDelegate.currentBinX + "x" + cameraDelegate.currentBinY : ""
                    property string lastSyncedBinning: ""

                    onCurrentBinningChanged: {
                        if (currentBinning === "") {
                            return
                        }
                        const wasSynced = lastSyncedBinning === "" || binningCombo.currentText === lastSyncedBinning
                        lastSyncedBinning = currentBinning
                        if (wasSynced) {
                            const idx = binningCombo.find(currentBinning)
                            if (idx >= 0) {
                                binningCombo.currentIndex = idx
                            }
                        }
                    }

                    Label { text: "Binning:" }
                    ComboBox {
                        id: binningCombo
                        model: cameraDelegate.binningOptions || []
                        onActivated: {
                            const parts = currentText.split("x")
                            if (parts.length !== 2) {
                                return
                            }
                            cameraDelegate.lastError = ""
                            root.xmppClient.executeMethod(
                                jid, "set_binning", [parseInt(parts[0], 10), parseInt(parts[1], 10)],
                                function (result) {
                                    if (!result.success) {
                                        cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                    }
                                })
                        }
                    }
                }

                // --- IWindow: four live-sync SpinBoxes bounded by
                // windowExtent adjusted for the current binning factor -
                // set_window()'s own param names are left/top/width/height,
                // even though WindowState's fields are named x/y (a real
                // wire naming mismatch, not a typo - see DEVELOPMENT.md).
                ColumnLayout {
                    id: windowSection
                    Layout.leftMargin: 8
                    visible: cameraDelegate.windowInterface !== null
                    spacing: 4

                    readonly property int maxWidth: Math.max(1, Math.floor((cameraDelegate.windowExtent.fullFrameWidth || 0) / cameraDelegate.currentBinX))
                    readonly property int maxHeight: Math.max(1, Math.floor((cameraDelegate.windowExtent.fullFrameHeight || 0) / cameraDelegate.currentBinY))

                    Label { text: "Window" }

                    RowLayout {
                        Label { text: "Left:" }
                        SpinBox { id: leftSpin; from: 0; to: windowSection.maxWidth; editable: true }
                        Label { text: "Top:" }
                        SpinBox { id: topSpin; from: 0; to: windowSection.maxHeight; editable: true }
                        Label { text: "Width:" }
                        SpinBox { id: widthSpin; from: 1; to: windowSection.maxWidth; editable: true }
                        Label { text: "Height:" }
                        SpinBox { id: heightSpin; from: 1; to: windowSection.maxHeight; editable: true }
                    }

                    RowLayout {
                        Button {
                            text: "Set Window"
                            onClicked: {
                                cameraDelegate.lastError = ""
                                root.xmppClient.executeMethod(
                                    jid, "set_window", [leftSpin.value, topSpin.value, widthSpin.value, heightSpin.value],
                                    function (result) {
                                        if (!result.success) {
                                            cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                        }
                                    })
                            }
                        }
                        Button {
                            text: "Full Frame"
                            onClicked: {
                                leftSpin.value = 0
                                topSpin.value = 0
                                widthSpin.value = windowSection.maxWidth
                                heightSpin.value = windowSection.maxHeight
                                cameraDelegate.lastError = ""
                                root.xmppClient.executeMethod(
                                    jid, "set_window", [0, 0, widthSpin.value, heightSpin.value],
                                    function (result) {
                                        if (!result.success) {
                                            cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                        }
                                    })
                            }
                        }
                    }
                }

                // --- IGain: two live-sync SpinBoxes (no declared range -
                // generous fixed bounds), one "Set" button firing both
                // set_gain/set_offset (two separate RPCs, no combined
                // command exists). Real fix vs. camerawidget.py, not a
                // faithful port - see DEVELOPMENT.md.
                RowLayout {
                    Layout.leftMargin: 8
                    visible: cameraDelegate.gainInterface !== null

                    Label { text: "Gain:" }
                    SpinBox {
                        id: gainSpin
                        from: -1000000
                        to: 1000000
                        editable: true
                        textFromValue: (value) => (value / 100).toFixed(2)
                        valueFromText: (text) => Math.round(parseFloat(text) * 100)
                    }
                    Label { text: "Offset:" }
                    SpinBox {
                        id: offsetSpin
                        from: -1000000
                        to: 1000000
                        editable: true
                        textFromValue: (value) => (value / 100).toFixed(2)
                        valueFromText: (text) => Math.round(parseFloat(text) * 100)
                    }
                    Button {
                        text: "Set"
                        onClicked: {
                            cameraDelegate.lastError = ""
                            root.xmppClient.executeMethod(jid, "set_gain", [gainSpin.value / 100], function (result) {
                                if (!result.success) {
                                    cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                }
                            })
                            root.xmppClient.executeMethod(jid, "set_offset", [offsetSpin.value / 100], function (result) {
                                if (!result.success) {
                                    cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                }
                            })
                        }
                    }
                }

                // --- IImageFormat: ComboBox over the imageFormats role.
                RowLayout {
                    Layout.leftMargin: 8
                    visible: cameraDelegate.imageFormatInterface !== null

                    readonly property string currentImageFormat: cameraDelegate.fieldOf(cameraDelegate.imageFormatState, "image_format") || ""
                    property string lastSyncedImageFormat: ""

                    onCurrentImageFormatChanged: {
                        if (currentImageFormat === "") {
                            return
                        }
                        const wasSynced = lastSyncedImageFormat === "" || imageFormatCombo.currentText === lastSyncedImageFormat
                        lastSyncedImageFormat = currentImageFormat
                        if (wasSynced) {
                            const idx = imageFormatCombo.find(currentImageFormat)
                            if (idx >= 0) {
                                imageFormatCombo.currentIndex = idx
                            }
                        }
                    }

                    Label { text: "Image format:" }
                    ComboBox {
                        id: imageFormatCombo
                        model: cameraDelegate.imageFormats || []
                        onActivated: {
                            cameraDelegate.lastError = ""
                            root.xmppClient.executeMethod(jid, "set_image_format", [currentText], function (result) {
                                if (!result.success) {
                                    cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                }
                            })
                        }
                    }
                }

                // --- ICooling: CoolingState alone (setpoint/power/enabled)
                // - current measured temperature lives on the separately-
                // inherited ITemperatures state, out of scope here (see
                // TODO.md's ITelescope-MVP deferral of IFilters/
                // ITemperatures, unchanged for this pass).
                ColumnLayout {
                    Layout.leftMargin: 8
                    visible: cameraDelegate.coolingInterface !== null
                    spacing: 4

                    readonly property bool currentEnabled: !!cameraDelegate.fieldOf(cameraDelegate.coolingState, "enabled")
                    readonly property var currentSetpoint: cameraDelegate.fieldOf(cameraDelegate.coolingState, "setpoint")
                    readonly property var currentPower: cameraDelegate.fieldOf(cameraDelegate.coolingState, "power")

                    property bool lastSyncedEnabled: false
                    property real lastSyncedSetpoint: NaN

                    onCurrentEnabledChanged: {
                        const wasSynced = coolingCheck.checked === lastSyncedEnabled
                        lastSyncedEnabled = currentEnabled
                        if (wasSynced) {
                            coolingCheck.checked = currentEnabled
                        }
                    }

                    onCurrentSetpointChanged: {
                        if (currentSetpoint === undefined || currentSetpoint === null) {
                            return
                        }
                        const wasSynced = isNaN(lastSyncedSetpoint) || Math.round(setpointSpin.value) === Math.round(lastSyncedSetpoint * 10)
                        lastSyncedSetpoint = currentSetpoint
                        if (wasSynced) {
                            setpointSpin.value = Math.round(currentSetpoint * 10)
                        }
                    }

                    Label { text: "Cooling"; font.bold: true }

                    RowLayout {
                        CheckBox {
                            id: coolingCheck
                            text: "Enabled"
                        }
                        Label { text: "Setpoint:" }
                        SpinBox {
                            id: setpointSpin
                            from: -1000
                            to: 500
                            editable: true
                            textFromValue: (value) => (value / 10).toFixed(1)
                            valueFromText: (text) => Math.round(parseFloat(text) * 10)
                        }
                        Label { text: "°C" }
                        Button {
                            text: "Apply"
                            onClicked: {
                                cameraDelegate.lastError = ""
                                root.xmppClient.executeMethod(
                                    jid, "set_cooling", [coolingCheck.checked, setpointSpin.value / 10],
                                    function (result) {
                                        if (!result.success) {
                                            cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                                        }
                                    })
                            }
                        }
                    }

                    Label {
                        text: parent.currentEnabled
                            ? "Setpoint: " + (parent.currentSetpoint !== undefined && parent.currentSetpoint !== null ? parent.currentSetpoint.toFixed(1) : "?") + "°C, Power: "
                                + (parent.currentPower !== undefined && parent.currentPower !== null ? parent.currentPower : "?") + "%"
                            : "OFF"
                        color: "grey"
                    }
                }

                // --- Image display: fits::FitsImageItem paints the last
                // fetched/decoded frame (see checkForNewImage()/
                // fetchImage() above for how it gets there). Zoom/pan
                // are QML-side, not implemented in the item itself (see
                // FitsImageItem.h's own comment) - Flickable gives pan
                // for free, imageZoomSpin drives the item's own
                // width/height, which FitsImageItem smoothly rescales
                // its cached render into on every paint.
                ColumnLayout {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Label { text: "Image"; font.bold: true }
                        Item { Layout.fillWidth: true }
                        Label { text: "Stretch:" }
                        ComboBox {
                            id: stretchCombo
                            textRole: "label"
                            valueRole: "value"
                            model: [
                                { label: "Percentile", value: "percentile" },
                                { label: "Min/Max", value: "minmax" },
                            ]
                            onActivated: fitsImageItem.stretchMode = currentValue
                        }
                        Label { text: "Zoom:" }
                        SpinBox {
                            id: imageZoomSpin
                            from: 10
                            to: 400
                            value: 100
                            stepSize: 10
                            editable: true
                            textFromValue: (value) => value + "%"
                            valueFromText: (text) => parseInt(text, 10)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: cameraDelegate.imageStatus === "loading"
                        text: "Loading image..."
                        color: "grey"
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: cameraDelegate.imageStatus === "error"
                        text: cameraDelegate.imageError
                        color: "red"
                        wrapMode: Text.WrapAnywhere
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: fitsImageItem.hasImage
                        text: fitsImageItem.imageWidth + "x" + fitsImageItem.imageHeight
                            + "  levels: " + fitsImageItem.blackLevel.toFixed(1) + " - " + fitsImageItem.whiteLevel.toFixed(1)
                        color: "grey"
                    }

                    Flickable {
                        Layout.preferredWidth: 480
                        Layout.preferredHeight: 360
                        visible: fitsImageItem.hasImage
                        clip: true
                        contentWidth: fitsImageItem.width
                        contentHeight: fitsImageItem.height
                        boundsBehavior: Flickable.StopAtBounds

                        FitsImageItem {
                            id: fitsImageItem
                            width: hasImage ? imageWidth * (imageZoomSpin.value / 100) : 0
                            height: hasImage ? imageHeight * (imageZoomSpin.value / 100) : 0
                        }
                    }
                }

                Label {
                    Layout.leftMargin: 8
                    Layout.fillWidth: true
                    visible: cameraDelegate.lastError.length > 0
                    text: cameraDelegate.lastError
                    color: "red"
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}
