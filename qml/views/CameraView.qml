import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import pyobs.polaris

import "../widgets/Permissions.js" as Permissions

// Dedicated page for ICamera modules, ported from pyobs-gui's
// camerawidget.py. ICamera itself is IData + IExposure (confirmed from
// source) - IExposure's state class is inherited by ICamera the same way
// IMotion's is inherited by ITelescope (TelescopeView.qml), so this
// subscribes to "IExposure" specifically (the interface that actually
// originates the state), gating visibility on "ICamera" (the specific
// marker), same split RoofView.qml/TelescopeView.qml already use.
// Everything below IExposure is capability-gated per interface,
// following the exact findInterface()/visible/refreshSubscriptions()
// shape every custom widget here already uses, just with more of them at
// once than any prior widget (up to eight simultaneous StateSubscriptions
// per module).
//
// Layout: sidebar-of-GroupBoxes + dominant image area, matching
// pyobs-gui's own camerawidget.ui (QHBoxLayout stretch="0,1,0": a narrow
// scrollable control sidebar, a dominant DataDisplayWidget, and a third
// filter/temperature sidebar this project doesn't have - see TODO.md's
// deliberate scope cut). GroupBox titles ("Exposure"/"Window"/"Gain"/...)
// replace the legacy's title-less bordered boxes (which relied on
// position/context alone) - a real, justified improvement over a 1:1
// port, not a generic default. Settable Window/Gain/ExpTime fields show
// a small grey "current value" label next to their SpinBox, mirroring
// camerawidget.ui's WatchedLabel pattern - the live-sync-into-spinbox
// idiom below already tracks the current value into the SpinBox itself
// when not being edited, but showing both side by side removes any
// ambiguity while a user is mid-edit, exactly the problem WatchedLabel
// solves in the original.
//
// Image controls, ported from datadisplaywidget.py/.ui and
// qfitswidget's fitswidget.ui (the third-party widget
// DataDisplayWidget embeds for the actual image pane): "Cuts:" combo
// (100.0/99.9/99.0/95.0%/Custom, matching qfitswidget's own comboCuts
// presets exactly - fits::FitsImageItem::setPercentilePreset()/
// enterCustomMode()) plus manual Lo/Hi level spin boxes when "Custom"
// is selected (fits::FitsImageItem::setManualLimits()), "Stretch:"
// tone curve + "Colormap:" + reversed + trimsec (all four backed by
// fits::FitsStretch's ToneCurve/Colormap/applyTrimSec - see that
// header's own comments, including why the colormap set is a small
// curated one rather than matplotlib's full library), and the bottom
// Auto-update/Auto-save/Save-to row (fits::FitsFileWriter does the
// actual disk I/O, QtQuick.Dialogs' FileDialog/FolderDialog pick the
// destination).
ScrollView {
    id: root

    required property var xmppClient
    required property var vfsEndpoints
    required property var vfsClient
    required property var appSettings

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
                spacing: 4

                required property string jid
                required property string name
                required property var statefulInterfaces
                required property var binningOptions
                required property var windowExtent
                required property var imageFormats
                required property var filters
                required property var permittedMethods

                // Whether every RPC applyPendingSettingsThenExpose() is
                // about to fire (conditionally: set_window/set_gain+
                // set_offset/set_exposure_time, always: grab_data) is
                // actually permitted - gates the Expose button as one unit
                // rather than letting it fire a partial batch that's bound
                // to fail partway through on a forbidden call.
                readonly property bool exposeIsPermitted:
                    Permissions.isPermitted(cameraDelegate.permittedMethods, "grab_data")
                    && (!cameraDelegate.windowInterface || Permissions.isPermitted(cameraDelegate.permittedMethods, "set_window"))
                    && (!cameraDelegate.gainInterface || (Permissions.isPermitted(cameraDelegate.permittedMethods, "set_gain")
                        && Permissions.isPermitted(cameraDelegate.permittedMethods, "set_offset")))
                    && (!cameraDelegate.exposureTimeInterface || cameraDelegate.currentImageType === "bias"
                        || Permissions.isPermitted(cameraDelegate.permittedMethods, "set_exposure_time"))

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
                readonly property bool hasAbort: findInterface("IAbortable") !== null

                property var exposureSubscription: null
                property var imageTypeSubscription: null
                property var exposureTimeSubscription: null
                property var binningSubscription: null
                property var windowSubscription: null
                property var gainSubscription: null
                property var imageFormatSubscription: null

                function refreshSubscriptions() {
                    if (exposureSubscription) { exposureSubscription.unsubscribe(); exposureSubscription = null }
                    if (imageTypeSubscription) { imageTypeSubscription.unsubscribe(); imageTypeSubscription = null }
                    if (exposureTimeSubscription) { exposureTimeSubscription.unsubscribe(); exposureTimeSubscription = null }
                    if (binningSubscription) { binningSubscription.unsubscribe(); binningSubscription = null }
                    if (windowSubscription) { windowSubscription.unsubscribe(); windowSubscription = null }
                    if (gainSubscription) { gainSubscription.unsubscribe(); gainSubscription = null }
                    if (imageFormatSubscription) { imageFormatSubscription.unsubscribe(); imageFormatSubscription = null }

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
                }

                onVisibleChanged: refreshSubscriptions()
                onExposureInterfaceChanged: refreshSubscriptions()
                onImageTypeInterfaceChanged: refreshSubscriptions()
                onExposureTimeInterfaceChanged: refreshSubscriptions()
                onBinningInterfaceChanged: refreshSubscriptions()
                onWindowInterfaceChanged: refreshSubscriptions()
                onGainInterfaceChanged: refreshSubscriptions()
                onImageFormatInterfaceChanged: refreshSubscriptions()
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

                // Sends whatever Window/Gain/ExposureTime values are
                // currently sitting in the SpinBoxes (populated once on
                // start, freely edited since - see exposureTimeInitialized/
                // windowInitialized/gainInitialized above) as a single
                // batch, then starts the exposure sequence once every "set"
                // RPC has come back - direct instruction: no per-field Set
                // button/confirmation, just apply everything together right
                // before Expose. Only ever called once per Expose click
                // (not once per exposure in a Count > 1 sequence) - the
                // settings apply for the whole sequence, matching what a
                // user clicking Expose once would expect.
                function applyPendingSettingsThenExpose() {
                    const pending = []
                    if (cameraDelegate.windowInterface) {
                        pending.push((cb) => root.xmppClient.executeMethod(
                            jid, "set_window", [leftSpin.value, topSpin.value, widthSpin.value, heightSpin.value], cb))
                    }
                    if (cameraDelegate.gainInterface) {
                        pending.push((cb) => root.xmppClient.executeMethod(jid, "set_gain", [gainSpin.value / 100], cb))
                        pending.push((cb) => root.xmppClient.executeMethod(jid, "set_offset", [offsetSpin.value / 100], cb))
                    }
                    if (cameraDelegate.exposureTimeInterface && cameraDelegate.currentImageType !== "bias") {
                        pending.push((cb) => root.xmppClient.executeMethod(
                            jid, "set_exposure_time", [exposureTimeSpin.value / 1000], cb))
                    }

                    if (pending.length === 0) {
                        cameraDelegate.remainingExposures = countSpin.value
                        cameraDelegate.grabOne()
                        return
                    }

                    let remaining = pending.length
                    function onOneDone(result) {
                        if (!result.success) {
                            cameraDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                        }
                        remaining -= 1
                        if (remaining === 0) {
                            cameraDelegate.remainingExposures = countSpin.value
                            cameraDelegate.grabOne()
                        }
                    }
                    for (const fn of pending) {
                        fn(onOneDone)
                    }
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

                // Auto-update/auto-save, ported from datadisplaywidget.py's
                // own checkAutoUpdate/checkAutoSave/textAutoSavePath -
                // auto-update gates the *entire* fetch, not just the
                // display (confirmed from source: _on_new_data() returns
                // early before even downloading if unchecked, so a
                // disabled auto-update also disables auto-save for that
                // image, matching here). autoSaveDirectory is a url (not a
                // free-text path) - only ever set via the FolderDialog
                // below, unlike the legacy's directly-editable QLineEdit;
                // simpler, and the legacy's own text field was only ever
                // populated by its own browse dialog in practice anyway.
                property bool autoUpdate: true
                property bool autoSaveEnabled: false
                property url autoSaveDirectory: ""
                // Raw bytes of the last successfully fetched image, kept
                // around purely for "Save to..." (see saveImageDialog
                // below) - VfsClient's fileReady(requestId, data) already
                // hands this to us for the auto-save/decode path, no
                // extra fetch needed to save what's already on screen.
                property var lastImageBytes: null

                // Basename with ".fits.gz" collapsed to ".fits", matching
                // datadisplaywidget.py's save_data()/_on_new_data() own
                // `os.path.basename(...).replace(".fits.gz", ".fits")`.
                function suggestedSaveFileName() {
                    const base = cameraDelegate.lastImageFilename.split("/").pop()
                    return base.replace(".fits.gz", ".fits")
                }

                // Cuts presets match qfitswidget's own comboCuts exactly
                // (100.0/99.9/99.0/95.0%, then Custom) - no separate
                // "Min/Max" entry, since 100.0% cuts already means the
                // literal min/max (see FitsStretch.h's own comment on
                // why that's not its own mode here).
                function cutsComboIndexFor(mode, percentile) {
                    if (mode === "custom") {
                        return 4
                    }
                    const presets = [100.0, 99.9, 99.0, 95.0]
                    for (let i = 0; i < presets.length; ++i) {
                        if (presets[i] === percentile) {
                            return i
                        }
                    }
                    return 1 // 99.9%, matching FitsImageItem's own default
                }

                // ComboBox.indexOfValue() turned out unreliable for these
                // object-array models (`textRole`/`valueRole`, current
                // value read from a forward-referenced fitsImageItem
                // property) - it silently left currentIndex at -1 (blank
                // combo text, no QML warning) for toneCurve/colormap,
                // even though the exact same model shape works fine for
                // cutsComboIndexFor's own hand-written lookup above.
                // Caught live from a screenshot showing empty Stretch/
                // Colormap combos, not obvious from reading the QML -
                // same class of bug as the CameraView.qml layout pass's
                // own RowLayout-overflow gotcha (see DEVELOPMENT.md).
                function indexOfStringValue(values, value) {
                    const idx = values.indexOf(value)
                    return idx >= 0 ? idx : 0
                }

                // For the collapsed Stretch/Colormap summary label below -
                // every value in both combos' models is just its label
                // lowercased ("Linear" -> "linear", "Gray" -> "gray", ...),
                // so this is enough without a second value->label lookup
                // table duplicating the combo models.
                function capitalize(value) {
                    return value.length > 0 ? value.charAt(0).toUpperCase() + value.slice(1) : value
                }

                function checkForNewImage() {
                    if (!cameraDelegate.autoUpdate) {
                        return
                    }
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
                        cameraDelegate.lastImageBytes = data

                        if (cameraDelegate.autoSaveEnabled) {
                            const ok = fitsFileWriter.writeBytesToDirectory(
                                cameraDelegate.autoSaveDirectory, cameraDelegate.suggestedSaveFileName(), data)
                            if (!ok) {
                                cameraDelegate.imageStatus = "error"
                                cameraDelegate.imageError = "Auto-save failed: " + fitsFileWriter.lastError
                                return
                            }
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

                FitsFileWriter {
                    id: fitsFileWriter
                }

                FolderDialog {
                    id: autoSaveFolderDialog
                    onAccepted: cameraDelegate.autoSaveDirectory = selectedFolder
                }

                FileDialog {
                    id: saveImageDialog
                    fileMode: FileDialog.SaveFile
                    nameFilters: ["FITS files (*.fits *.fits.gz)", "All files (*)"]
                    onAccepted: {
                        if (cameraDelegate.lastImageBytes !== null
                                && !fitsFileWriter.writeBytes(selectedFile, cameraDelegate.lastImageBytes)) {
                            cameraDelegate.imageStatus = "error"
                            cameraDelegate.imageError = "Save failed: " + fitsFileWriter.lastError
                        }
                    }
                }

                // "was synced" idiom for IImageType alone now - Window/
                // Gain/ExposureTime used to do this same continuous
                // live-resync dance (plus a grey "current value" label
                // next to each field), mirroring camerawidget.py's
                // WatchedLabel. Direct user instruction: that pattern
                // "doesn't really work" in practice - removed in favor of
                // fetch-once-on-start (below) + apply-on-Expose
                // (applyPendingSettingsThenExpose()). Type has no
                // separate "current value" display and no batch-apply
                // either (it's a single ComboBox, not a numeric field to
                // stage edits on) - it stays live-synced and
                // immediate-on-select, unchanged. Must live here on
                // cameraDelegate - the object that actually owns
                // exposureTimeState/windowState/gainState/
                // currentImageType - since an onXChanged handler only
                // binds to a property on its own object, not one
                // belonging to an ancestor/descendant (same lesson as
                // TelescopeView.qml's Offsets section). imageTypeCombo/
                // exposureTimeSpin/leftSpin.../gainSpin/offsetSpin are
                // forward id references into this same delegate's object
                // tree, resolved once the state actually changes (well
                // after Component.onCompleted) - nesting them inside
                // GroupBoxes/GridLayouts below doesn't change that, ids
                // are scoped to the whole Component regardless of depth.
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

                // Fetch-once-on-start: the first state push populates the
                // SpinBox, then this flag blocks any further server-driven
                // updates - the user edits freely afterward with no
                // ongoing resync fighting them, and the edited value is
                // only ever sent to the server in a batch right before
                // grab_data() (applyPendingSettingsThenExpose() below).
                property bool exposureTimeInitialized: false

                onExposureTimeStateChanged: {
                    if (exposureTimeInitialized) {
                        return
                    }
                    const value = fieldOf(exposureTimeState, "exposure_time")
                    if (value === undefined || value === null) {
                        return
                    }
                    exposureTimeSpin.value = Math.round(value * 1000)
                    exposureTimeInitialized = true
                }

                property bool windowInitialized: false

                onWindowStateChanged: {
                    if (windowInitialized) {
                        return
                    }
                    const left = fieldOf(windowState, "x")
                    const top = fieldOf(windowState, "y")
                    const width = fieldOf(windowState, "width")
                    const height = fieldOf(windowState, "height")
                    if (left === undefined || left === null) {
                        return
                    }
                    leftSpin.value = left
                    topSpin.value = top
                    widthSpin.value = width
                    heightSpin.value = height
                    windowInitialized = true
                }

                property bool gainInitialized: false

                onGainStateChanged: {
                    if (gainInitialized) {
                        return
                    }
                    const gain = fieldOf(gainState, "gain")
                    const offset = fieldOf(gainState, "offset")
                    if (gain === undefined || gain === null || offset === undefined || offset === null) {
                        return
                    }
                    gainSpin.value = Math.round(gain * 100)
                    offsetSpin.value = Math.round(offset * 100)
                    gainInitialized = true
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

                // --- Body: narrow control sidebar + dominant image area,
                // matching camerawidget.ui's own QHBoxLayout stretch
                // ratio (0 for the sidebar, 1 for the image) - see this
                // file's own header comment.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.preferredWidth: 220
                        Layout.maximumWidth: 220
                        Layout.alignment: Qt.AlignTop
                        spacing: 8

                        // --- IWindow: four live-sync SpinBoxes bounded by
                        // windowExtent adjusted for the current binning
                        // factor - set_window()'s own param names are
                        // left/top/width/height, even though WindowState's
                        // fields are named x/y (a real wire naming
                        // mismatch, not a typo - see DEVELOPMENT.md).
                        GroupBox {
                            title: "Window"
                            Layout.fillWidth: true
                            visible: cameraDelegate.windowInterface !== null

                            ColumnLayout {
                                id: windowSection
                                width: parent.width
                                spacing: 6

                                readonly property int maxWidth: Math.max(1, Math.floor((cameraDelegate.windowExtent.fullFrameWidth || 0) / cameraDelegate.currentBinX))
                                readonly property int maxHeight: Math.max(1, Math.floor((cameraDelegate.windowExtent.fullFrameHeight || 0) / cameraDelegate.currentBinY))

                                GridLayout {
                                    columns: 2
                                    columnSpacing: 8
                                    rowSpacing: 4
                                    Layout.fillWidth: true

                                    Label { text: "Left:" }
                                    SpinBox { id: leftSpin; Layout.fillWidth: true; from: 0; to: windowSection.maxWidth; editable: true }

                                    Label { text: "Top:" }
                                    SpinBox { id: topSpin; Layout.fillWidth: true; from: 0; to: windowSection.maxHeight; editable: true }

                                    Label { text: "Width:" }
                                    SpinBox { id: widthSpin; Layout.fillWidth: true; from: 1; to: windowSection.maxWidth; editable: true }

                                    Label { text: "Height:" }
                                    SpinBox { id: heightSpin; Layout.fillWidth: true; from: 1; to: windowSection.maxHeight; editable: true }
                                }

                                // Local-only - no RPC. Just stages the
                                // full-frame values into the SpinBoxes;
                                // like every other edit here, they're only
                                // ever sent to the server as part of
                                // applyPendingSettingsThenExpose() on the
                                // next Expose click.
                                Button {
                                    Layout.fillWidth: true
                                    text: "Full Frame"
                                    onClicked: {
                                        leftSpin.value = 0
                                        topSpin.value = 0
                                        widthSpin.value = windowSection.maxWidth
                                        heightSpin.value = windowSection.maxHeight
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "Binning & Format"
                            Layout.fillWidth: true
                            visible: cameraDelegate.binningInterface !== null || cameraDelegate.imageFormatInterface !== null

                            ColumnLayout {
                                width: parent.width
                                spacing: 6

                                // --- IBinning: ComboBox over the
                                // binningOptions role ("{x}x{y}" strings),
                                // same live-sync/onActivated shape as
                                // ModeView.qml's mode ComboBox.
                                RowLayout {
                                    Layout.fillWidth: true
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
                                        Layout.fillWidth: true
                                        enabled: Permissions.isPermitted(cameraDelegate.permittedMethods, "set_binning")
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

                                // --- IImageFormat: ComboBox over the
                                // imageFormats role.
                                RowLayout {
                                    Layout.fillWidth: true
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

                                    Label { text: "Format:" }
                                    ComboBox {
                                        id: imageFormatCombo
                                        Layout.fillWidth: true
                                        enabled: Permissions.isPermitted(cameraDelegate.permittedMethods, "set_image_format")
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
                            }
                        }

                        // --- IGain: two live-sync SpinBoxes (no declared
                        // range - generous fixed bounds), one "Set" button
                        // firing both set_gain/set_offset (two separate
                        // RPCs, no combined command exists). Real fix vs.
                        // camerawidget.py, not a faithful port - see
                        // DEVELOPMENT.md.
                        GroupBox {
                            title: "Gain"
                            Layout.fillWidth: true
                            visible: cameraDelegate.gainInterface !== null

                            ColumnLayout {
                                width: parent.width
                                spacing: 6

                                GridLayout {
                                    columns: 2
                                    columnSpacing: 8
                                    rowSpacing: 4
                                    Layout.fillWidth: true

                                    Label { text: "Gain:" }
                                    SpinBox {
                                        id: gainSpin
                                        Layout.fillWidth: true
                                        from: -1000000
                                        to: 1000000
                                        editable: true
                                        textFromValue: (value) => (value / 100).toFixed(2)
                                        valueFromText: (text) => Math.round(parseFloat(text) * 100)
                                    }

                                    Label { text: "Offset:" }
                                    SpinBox {
                                        id: offsetSpin
                                        Layout.fillWidth: true
                                        from: -1000000
                                        to: 1000000
                                        editable: true
                                        textFromValue: (value) => (value / 100).toFixed(2)
                                        valueFromText: (text) => Math.round(parseFloat(text) * 100)
                                    }
                                }
                            }
                        }

                        GroupBox {
                            title: "Exposure"
                            Layout.fillWidth: true

                            ColumnLayout {
                                width: parent.width
                                spacing: 6

                                // --- IImageType: static ImageType enum,
                                // not a capability - BIAS disables/zeroes
                                // the exposure-time control below
                                // (camerawidget.py's own
                                // image_type_changed nicety).
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: cameraDelegate.imageTypeInterface !== null

                                    Label { text: "Type:" }
                                    ComboBox {
                                        id: imageTypeCombo
                                        Layout.fillWidth: true
                                        enabled: Permissions.isPermitted(cameraDelegate.permittedMethods, "set_image_type")
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

                                // --- IExposureTime: fetched once on start
                                // (exposureTimeInitialized above), edited
                                // freely, applied as part of the batch in
                                // applyPendingSettingsThenExpose() - no
                                // immediate per-edit RPC, no separate
                                // current-value label (direct instruction,
                                // see that function's own comment).
                                // Disabled while BIAS is selected, same as
                                // before.
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: cameraDelegate.exposureTimeInterface !== null

                                    Label { text: "Exp. time:" }
                                    SpinBox {
                                        id: exposureTimeSpin
                                        Layout.fillWidth: true
                                        from: 0
                                        to: 3600000
                                        value: 1000
                                        editable: true
                                        enabled: cameraDelegate.currentImageType !== "bias"
                                        textFromValue: (value) => (value / 1000).toFixed(3)
                                        valueFromText: (text) => Math.round(parseFloat(text) * 1000)
                                    }
                                    Label { text: "s" }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Count:" }
                                    SpinBox {
                                        id: countSpin
                                        from: 1
                                        to: 999
                                        value: 1
                                        editable: true
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
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

                                // Color-coded Expose/Abort, matching
                                // camerawidget.ui's own green/red buttons.
                                RowLayout {
                                    Layout.fillWidth: true
                                    Button {
                                        Layout.fillWidth: true
                                        text: "Expose"
                                        palette.button: "#2e7d32"
                                        palette.buttonText: "white"
                                        enabled: cameraDelegate.remainingExposures === 0 && cameraDelegate.exposeIsPermitted
                                        onClicked: {
                                            cameraDelegate.lastError = ""
                                            cameraDelegate.applyPendingSettingsThenExpose()
                                        }
                                    }
                                    Button {
                                        Layout.fillWidth: true
                                        text: cameraDelegate.remainingExposures > 1 ? "Abort Seq." : "Abort"
                                        visible: cameraDelegate.hasAbort
                                        palette.button: "#c62828"
                                        palette.buttonText: "white"
                                        enabled: cameraDelegate.remainingExposures > 0
                                            && (cameraDelegate.remainingExposures > 1 || Permissions.isPermitted(cameraDelegate.permittedMethods, "abort"))
                                        onClicked: {
                                            if (cameraDelegate.remainingExposures > 1) {
                                                // Mid-sequence: just stop the
                                                // client-side loop, don't
                                                // interrupt the exposure
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
                            }
                        }

                        // --- Status/progress, at the very bottom of the
                        // sidebar below every control group - matches
                        // camerawidget.ui's own layout exactly (labelStatus/
                        // progressExposure are the last items in its
                        // sidebar's QVBoxLayout, after a vertical spacer),
                        // not mixed in with the Type/Count/Expose controls.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: cameraDelegate.exposureStatus.toUpperCase()
                                    + (cameraDelegate.exposureTimeLeft !== undefined && cameraDelegate.exposureTimeLeft !== null
                                       ? " (" + cameraDelegate.exposureTimeLeft.toFixed(1) + "s left)" : "")
                            }
                            ProgressBar {
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                value: cameraDelegate.exposureProgress
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: cameraDelegate.lastError.length > 0
                            text: cameraDelegate.lastError
                            color: "red"
                            wrapMode: Text.WrapAnywhere
                        }
                    }

                    // --- Image display: fits::FitsImageItem paints the
                    // last fetched/decoded frame (see checkForNewImage()/
                    // fetchImage() above for how it gets there). Zoom/pan
                    // are QML-side, not implemented in the item itself
                    // (see FitsImageItem.h's own comment) - Flickable
                    // gives pan for free, imageZoomSpin drives the item's
                    // own width/height, which FitsImageItem smoothly
                    // rescales its cached render into on every paint.
                    // Dominant, fills the remaining width - matches
                    // camerawidget.ui's own stretch="0,1,0" ratio (this
                    // project has no third filter/temperature sidebar,
                    // see TODO.md).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 4

                        // Flow, not RowLayout - when the image column gets
                        // squeezed narrow (fixed-width control sidebar +
                        // SidebarColumn leaving little room left), these
                        // controls need to wrap onto another line instead
                        // of clipping (the exact RowLayout-overflow gotcha
                        // this file's own header comment already
                        // references). No fillWidth spacer to push Cuts/
                        // Zoom to the right anymore - Flow doesn't support
                        // one, so "Image" just flows left of them with
                        // normal spacing instead of being pinned apart.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: "Image"; font.bold: true }
                            Label { text: "Cuts:" }
                            ComboBox {
                                id: cutsCombo
                                textRole: "label"
                                valueRole: "value"
                                model: [
                                    { label: "100.0%", value: 100.0 },
                                    { label: "99.9%", value: 99.9 },
                                    { label: "99.0%", value: 99.0 },
                                    { label: "95.0%", value: 95.0 },
                                    { label: "Custom", value: -1 },
                                ]
                                // Reflects fitsImageItem's own state rather
                                // than only ever being set by this combo -
                                // typing in loCutSpin/hiCutSpin below also
                                // switches the item into "custom" mode (see
                                // FitsImageItem::setManualLimits()), which
                                // should move this combo's selection to
                                // match, not just the spin boxes' enabled
                                // state.
                                currentIndex: cameraDelegate.cutsComboIndexFor(
                                    fitsImageItem.stretchMode, fitsImageItem.percentile)
                                onActivated: {
                                    if (currentValue === -1) {
                                        fitsImageItem.enterCustomMode()
                                    } else {
                                        fitsImageItem.setPercentilePreset(currentValue)
                                    }
                                }
                            }
                            // Manual black/white level override -
                            // qfitswidget's spinLoCut/spinHiCut equivalent.
                            // Seeded from the item's own computed levels the
                            // moment "Custom" becomes active (see the
                            // Connections block below), then left entirely
                            // to the user - same fetch-once-then-explicit-
                            // apply idiom as Window/Gain/ExposureTime above,
                            // just applied on every edit rather than behind
                            // a separate "apply" action, since there's no
                            // batching concern here (each edit is already
                            // its own independent RPC-free local repaint).
                            SpinBox {
                                id: loCutSpin
                                visible: fitsImageItem.stretchMode === "custom"
                                from: -1000000
                                to: 1000000
                                editable: true
                                onValueModified: fitsImageItem.setManualLimits(loCutSpin.value, hiCutSpin.value)
                            }
                            SpinBox {
                                id: hiCutSpin
                                visible: fitsImageItem.stretchMode === "custom"
                                from: -1000000
                                to: 1000000
                                editable: true
                                onValueModified: fitsImageItem.setManualLimits(loCutSpin.value, hiCutSpin.value)
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

                        Connections {
                            target: fitsImageItem
                            function onStretchModeChanged() {
                                if (fitsImageItem.stretchMode === "custom") {
                                    loCutSpin.value = Math.round(fitsImageItem.blackLevel)
                                    hiCutSpin.value = Math.round(fitsImageItem.whiteLevel)
                                }
                            }
                        }

                        // Tone curve / colormap / trimsec - the rest of
                        // qfitswidget's own toolbar (fitswidget.ui's
                        // comboStretch/comboColormap/checkColormapReverse/
                        // checkTrimSec). Unlike Cuts/Zoom above (adjusted
                        // constantly while actually looking at an image),
                        // these are "set once and forget" - collapsed into
                        // a readonly summary label plus a button that opens
                        // the real controls in a Popup, instead of a whole
                        // extra always-visible toolbar row (direct
                        // instruction - a previous pass already had to
                        // split this onto its own row to avoid a
                        // RowLayout-overflow clip, see DEVELOPMENT.md's
                        // CameraView.qml layout-pass write-up; this goes
                        // further and removes the row entirely).
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: "grey"
                                text: cameraDelegate.capitalize(fitsImageItem.toneCurve) + " · "
                                    + cameraDelegate.capitalize(fitsImageItem.colormap)
                                    + (fitsImageItem.reversedColormap ? " (reversed)" : "")
                                    + (fitsImageItem.trimSecEnabled ? " · trimsec" : "")
                            }
                            Button {
                                id: displaySettingsButton
                                text: "Display settings…"
                                onClicked: displaySettingsPopup.open()
                            }
                        }

                        Popup {
                            id: displaySettingsPopup
                            parent: displaySettingsButton
                            x: parent.width - width
                            y: parent.height + 4
                            focus: true

                            ColumnLayout {
                                spacing: 8

                                RowLayout {
                                    Label { text: "Stretch:" }
                                    ComboBox {
                                        id: toneCurveCombo
                                        Layout.fillWidth: true
                                        textRole: "label"
                                        valueRole: "value"
                                        model: [
                                            { label: "Linear", value: "linear" },
                                            { label: "Log", value: "log" },
                                            { label: "Sqrt", value: "sqrt" },
                                            { label: "Squared", value: "squared" },
                                            { label: "Asinh", value: "asinh" },
                                        ]
                                        currentIndex: cameraDelegate.indexOfStringValue(
                                            ["linear", "log", "sqrt", "squared", "asinh"], fitsImageItem.toneCurve)
                                        onActivated: fitsImageItem.toneCurve = currentValue
                                    }
                                }
                                RowLayout {
                                    Label { text: "Colormap:" }
                                    ComboBox {
                                        id: colormapCombo
                                        Layout.fillWidth: true
                                        textRole: "label"
                                        valueRole: "value"
                                        model: [
                                            { label: "Gray", value: "gray" },
                                            { label: "Viridis", value: "viridis" },
                                            { label: "Hot", value: "hot" },
                                            { label: "Cool", value: "cool" },
                                            { label: "Jet", value: "jet" },
                                        ]
                                        currentIndex: cameraDelegate.indexOfStringValue(
                                            ["gray", "viridis", "hot", "cool", "jet"], fitsImageItem.colormap)
                                        onActivated: fitsImageItem.colormap = currentValue
                                    }
                                }
                                CheckBox {
                                    text: "reversed"
                                    checked: fitsImageItem.reversedColormap
                                    onToggled: fitsImageItem.reversedColormap = checked
                                }
                                CheckBox {
                                    text: "trimsec"
                                    checked: fitsImageItem.trimSecEnabled
                                    onToggled: fitsImageItem.trimSecEnabled = checked
                                }
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

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 560
                            color: "#101214"
                            border.color: "#2d3035"
                            border.width: 1

                            Label {
                                anchors.centerIn: parent
                                visible: !fitsImageItem.hasImage && cameraDelegate.imageStatus === ""
                                text: "No image yet - click Expose to capture one."
                                color: "grey"
                            }

                            Flickable {
                                anchors.fill: parent
                                anchors.margins: 1
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

                        // Auto-update/auto-save/save-to, ported from
                        // datadisplaywidget.ui's own bottom row
                        // (checkAutoUpdate, checkAutoSave + textAutoSavePath
                        // + butAutoSave, butSaveTo) - see checkForNewImage()/
                        // onFileReady() above for the actual behavior; this
                        // is just the controls for it.
                        // Flow, same reasoning as the Cuts/Zoom and Stretch/
                        // Colormap rows above - no fillWidth spacers to
                        // separate the Auto-update/Auto-save/Save-to groups
                        // anymore, they just flow adjacent with normal
                        // spacing. The path label's width is now a plain
                        // property instead of Layout.maximumWidth (Flow
                        // doesn't process Layout attached properties on its
                        // children, unlike RowLayout) - still needed so
                        // elide actually has a bound to truncate against.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8

                            CheckBox {
                                text: "Auto-update"
                                checked: cameraDelegate.autoUpdate
                                onToggled: cameraDelegate.autoUpdate = checked
                            }
                            CheckBox {
                                text: "Auto-save:"
                                checked: cameraDelegate.autoSaveEnabled
                                onToggled: cameraDelegate.autoSaveEnabled = checked
                            }
                            Label {
                                width: 220
                                elide: Text.ElideMiddle
                                enabled: cameraDelegate.autoSaveEnabled
                                text: cameraDelegate.autoSaveDirectory.toString().length > 0
                                    ? cameraDelegate.autoSaveDirectory.toString().replace("file://", "")
                                    : "(no folder selected)"
                                color: "grey"
                            }
                            ToolButton {
                                text: "..."
                                enabled: cameraDelegate.autoSaveEnabled
                                onClicked: autoSaveFolderDialog.open()
                            }
                            Button {
                                text: "Save to..."
                                enabled: cameraDelegate.lastImageBytes !== null
                                onClicked: {
                                    saveImageDialog.currentFile = cameraDelegate.suggestedSaveFileName()
                                    saveImageDialog.open()
                                }
                            }
                        }
                    }

                    // --- Third column: mirrors camerawidget.ui's own
                    // right-hand sidebar position for Cooling/
                    // Temperatures/FITS headers. Originally a hand-wired
                    // Cooling GroupBox plus, once shipped as direct
                    // follow-up requests, ITemperatures/IFilters/IFocuser
                    // panels (see DEVELOPMENT.md for the ports/live-
                    // verification notes on each) - generalized into a
                    // fully generic SidebarPanelRegistry-driven Repeater
                    // once TelescopeView.qml needed the exact same sidebar
                    // shape too ("would it make sense to make this a
                    // general thing and widgets can decide whether they
                    // need a sidebar... go full registry"), then factored
                    // out into SidebarColumn.qml once it also grew a
                    // resize handle and collapse toggle that
                    // TelescopeView.qml's own fourth column needed
                    // identically ("the sidebar should have the same size
                    // over several widgets") - see that file's own header
                    // comment for the shape/rationale. Adding a new
                    // sidebar panel anywhere in this project still only
                    // means registering it in MainWindow.qml, never
                    // touching this file, TelescopeView.qml, or
                    // SidebarColumn.qml again.
                    SidebarColumn {
                        Layout.alignment: Qt.AlignTop
                        xmppClient: root.xmppClient
                        appSettings: root.appSettings
                        jid: cameraDelegate.jid
                        moduleName: cameraDelegate.name
                        statefulInterfaces: cameraDelegate.statefulInterfaces
                        availableFilters: cameraDelegate.filters
                        permittedMethods: cameraDelegate.permittedMethods
                    }
                }
            }
        }
    }
}
