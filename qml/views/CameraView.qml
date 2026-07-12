import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import pyobs.polaris

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
                readonly property var temperaturesInterface: findInterface("ITemperatures")
                readonly property bool hasAbort: findInterface("IAbortable") !== null

                property var exposureSubscription: null
                property var imageTypeSubscription: null
                property var exposureTimeSubscription: null
                property var binningSubscription: null
                property var windowSubscription: null
                property var gainSubscription: null
                property var imageFormatSubscription: null
                property var coolingSubscription: null
                property var temperaturesSubscription: null

                function refreshSubscriptions() {
                    if (exposureSubscription) { exposureSubscription.unsubscribe(); exposureSubscription = null }
                    if (imageTypeSubscription) { imageTypeSubscription.unsubscribe(); imageTypeSubscription = null }
                    if (exposureTimeSubscription) { exposureTimeSubscription.unsubscribe(); exposureTimeSubscription = null }
                    if (binningSubscription) { binningSubscription.unsubscribe(); binningSubscription = null }
                    if (windowSubscription) { windowSubscription.unsubscribe(); windowSubscription = null }
                    if (gainSubscription) { gainSubscription.unsubscribe(); gainSubscription = null }
                    if (imageFormatSubscription) { imageFormatSubscription.unsubscribe(); imageFormatSubscription = null }
                    if (coolingSubscription) { coolingSubscription.unsubscribe(); coolingSubscription = null }
                    if (temperaturesSubscription) { temperaturesSubscription.unsubscribe(); temperaturesSubscription = null }

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
                    if (visible && temperaturesInterface) {
                        temperaturesSubscription = root.xmppClient.subscribeState(
                            jid, "ITemperatures", temperaturesInterface.version, cameraDelegate)
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
                onTemperaturesInterfaceChanged: refreshSubscriptions()
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
                readonly property var temperaturesState: temperaturesSubscription ? temperaturesSubscription.value : undefined
                readonly property var temperatureReadings: fieldOf(temperaturesState, "readings") || []

                // ITemperatures' own wire state is only ever the latest
                // snapshot (see pyobs.interfaces.ITemperatures) - there's no
                // history on the wire, so the "Plot temps" window's history
                // is accumulated client-side here, mirroring pyobs-gui's
                // TemperaturesWidget._on_temperatures_state()/
                // TemperaturesPlotWidget.add_data(): every new snapshot
                // appends one point per sensor name. A plain JS object used
                // as a name -> point-array map, always reassigned wholesale
                // (not mutated in place) for the same reason StatusView.qml's
                // expandedJids is - a QML binding only re-evaluates on
                // property reassignment. Capped per sensor
                // (maxHistoryPoints) so a long-running session doesn't grow
                // this unboundedly - pyobs-gui has no such cap (an in-memory
                // pandas DataFrame kept for the life of the plot window,
                // never pruned either), but this project's own window can
                // just as easily stay open indefinitely.
                property var temperatureHistory: ({})
                readonly property int maxHistoryPoints: 500

                function recordTemperatureHistory() {
                    const readings = cameraDelegate.temperatureReadings
                    if (!readings || readings.length === 0) {
                        return
                    }
                    const now = Date.now() / 1000
                    const next = Object.assign({}, cameraDelegate.temperatureHistory)
                    for (let i = 0; i < readings.length; ++i) {
                        const name = cameraDelegate.fieldOf(readings[i], "name")
                        const value = cameraDelegate.fieldOf(readings[i], "value")
                        if (name === undefined || value === undefined || value === null) {
                            continue
                        }
                        const series = (next[name] || []).concat([{ x: now, y: value }])
                        next[name] = series.length > cameraDelegate.maxHistoryPoints
                            ? series.slice(series.length - cameraDelegate.maxHistoryPoints) : series
                    }
                    cameraDelegate.temperatureHistory = next
                }

                onTemperaturesStateChanged: recordTemperatureHistory()

                function sortedTemperatureReadings() {
                    const list = (cameraDelegate.temperatureReadings || []).slice()
                    list.sort(function (a, b) {
                        const nameA = cameraDelegate.fieldOf(a, "name") || ""
                        const nameB = cameraDelegate.fieldOf(b, "name") || ""
                        return nameA < nameB ? -1 : (nameA > nameB ? 1 : 0)
                    })
                    return list
                }

                // Which sensors the "Plot temps" window currently shows,
                // keyed by name - lets a user isolate one/some sensors on a
                // busy multi-sensor camera instead of always plotting every
                // one (pyobs-gui's own temperaturesplotwidget.py has no such
                // toggle, always plots every column). A name absent from
                // this map defaults to shown, so a newly-discovered sensor
                // appears selected without needing its own explicit entry.
                property var selectedTemperatureSeries: ({})

                function isTemperatureSeriesSelected(name) {
                    return cameraDelegate.selectedTemperatureSeries[name] !== false
                }

                function setTemperatureSeriesSelected(name, selected) {
                    const next = Object.assign({}, cameraDelegate.selectedTemperatureSeries)
                    next[name] = selected
                    cameraDelegate.selectedTemperatureSeries = next
                }

                // "Plot temps" window's time-range filter - ports pyobs-gui's
                // temperaturesplotwidget.py comboShow ("All"/"Last minute"/
                // "Last 5 minutes"), just with "Last hour" instead of "Last
                // minute" (a `maxHistoryPoints`-capped, ~1-point-per-second
                // buffer makes "last minute" barely distinguishable from
                // "last 5 minutes" here). -1 means "All" - no cutoff.
                property int temperaturePlotWindowSeconds: -1

                function temperaturePlotSeries() {
                    const names = Object.keys(cameraDelegate.temperatureHistory).sort()
                    const cutoff = cameraDelegate.temperaturePlotWindowSeconds > 0
                        ? (Date.now() / 1000 - cameraDelegate.temperaturePlotWindowSeconds) : -Infinity
                    const result = []
                    for (let i = 0; i < names.length; ++i) {
                        if (!cameraDelegate.isTemperatureSeriesSelected(names[i])) {
                            continue
                        }
                        const points = cameraDelegate.temperatureHistory[names[i]].filter(function (p) {
                            return p.x >= cutoff
                        })
                        result.push({ label: names[i], points: points })
                    }
                    return result
                }

                ApplicationWindow {
                    id: temperaturesPlotWindow
                    width: 640
                    height: 420
                    title: "Temperatures — " + cameraDelegate.name
                    visible: false

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Flow {
                                Layout.fillWidth: true
                                spacing: 12

                                Repeater {
                                    // Every sensor seen so far, not just the
                                    // ones currently selected - a deselected
                                    // sensor's checkbox must stay put (just
                                    // unchecked), not disappear.
                                    model: Object.keys(cameraDelegate.temperatureHistory).sort()

                                    delegate: CheckBox {
                                        text: modelData
                                        checked: cameraDelegate.isTemperatureSeriesSelected(modelData)
                                        onToggled: cameraDelegate.setTemperatureSeriesSelected(modelData, checked)
                                    }
                                }
                            }

                            Label { text: "Show:" }
                            ComboBox {
                                id: temperaturePlotWindowCombo
                                model: ["Last 5 minutes", "Last hour", "All"]
                                currentIndex: 2

                                onActivated: {
                                    switch (currentIndex) {
                                    case 0:
                                        cameraDelegate.temperaturePlotWindowSeconds = 5 * 60
                                        break
                                    case 1:
                                        cameraDelegate.temperaturePlotWindowSeconds = 60 * 60
                                        break
                                    default:
                                        cameraDelegate.temperaturePlotWindowSeconds = -1
                                        break
                                    }
                                }
                            }
                        }

                        PlotItem {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            xLabel: "Time"
                            yLabel: "Temperature (°C)"
                            xTicksAsTime: true
                            series: cameraDelegate.temperaturePlotSeries()
                        }
                    }
                }

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
                                        enabled: cameraDelegate.remainingExposures === 0
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

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Image"; font.bold: true }
                            Item { Layout.fillWidth: true }
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
                        // checkTrimSec), split onto its own row rather
                        // than crammed into the Cuts/Zoom row above -
                        // this page's columns are narrower than
                        // qfitswidget's own standalone window, and a
                        // RowLayout child wider than its column already
                        // bit this exact page once (see
                        // DEVELOPMENT.md's CameraView.qml layout-pass
                        // write-up).
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Stretch:" }
                            ComboBox {
                                id: toneCurveCombo
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
                            Label { text: "Colormap:" }
                            ComboBox {
                                id: colormapCombo
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
                            CheckBox {
                                text: "reversed"
                                checked: fitsImageItem.reversedColormap
                                onToggled: fitsImageItem.reversedColormap = checked
                            }
                            Item { Layout.fillWidth: true }
                            CheckBox {
                                text: "trimsec"
                                checked: fitsImageItem.trimSecEnabled
                                onToggled: fitsImageItem.trimSecEnabled = checked
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
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            CheckBox {
                                text: "Auto-update"
                                checked: cameraDelegate.autoUpdate
                                onToggled: cameraDelegate.autoUpdate = checked
                            }
                            Item { Layout.fillWidth: true }
                            CheckBox {
                                text: "Auto-save:"
                                checked: cameraDelegate.autoSaveEnabled
                                onToggled: cameraDelegate.autoSaveEnabled = checked
                            }
                            Label {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 220
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
                            Item { Layout.fillWidth: true }
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

                    // --- Third column: ICooling and, since the direct
                    // request below, ITemperatures too (IFilters/IFocuser
                    // still out of scope, see TODO.md's ITelescope-MVP
                    // deferral). Mirrors camerawidget.ui's own right-hand
                    // sidebar position for Cooling/Temperatures/FITS
                    // headers.
                    //
                    // ITemperatures follow-up, direct request ("the camera
                    // page is missing a widget for ITemperatures, right?
                    // check pyobs-gui"): ports pyobs-gui's
                    // temperatureswidget.py (a sorted-by-name read-only
                    // sensor list) plus temperaturesplotwidget.py (a "Plot
                    // temps" button opening a live multi-line history
                    // window) - see cameraDelegate's own
                    // temperatureHistory/recordTemperatureHistory() comment
                    // above for why the plot's history has to be
                    // accumulated client-side rather than read straight off
                    // the wire. The plot itself needed plot::PlotItem
                    // extended with genuine multi-series support (`series`/
                    // `xTicksAsTime`, see PlotItem.h) - AutoFocusView's/
                    // AcquisitionView's own single-series usage is
                    // untouched.
                    ColumnLayout {
                        Layout.preferredWidth: 220
                        Layout.maximumWidth: 220
                        Layout.alignment: Qt.AlignTop
                        spacing: 8
                        visible: cameraDelegate.coolingInterface !== null || cameraDelegate.temperaturesInterface !== null

                        GroupBox {
                            title: "Cooling"
                            Layout.fillWidth: true
                            visible: cameraDelegate.coolingInterface !== null

                            ColumnLayout {
                                width: parent.width
                                spacing: 6

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

                                RowLayout {
                                    Layout.fillWidth: true
                                    CheckBox {
                                        id: coolingCheck
                                        text: "Enabled"
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label {
                                        text: parent.parent.currentEnabled
                                            ? (parent.parent.currentPower !== undefined && parent.parent.currentPower !== null
                                               ? parent.parent.currentPower + "%" : "")
                                            : "OFF"
                                        color: "grey"
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Setpoint:" }
                                    Label {
                                        text: parent.parent.currentEnabled && parent.parent.currentSetpoint !== undefined && parent.parent.currentSetpoint !== null
                                            ? parent.parent.currentSetpoint.toFixed(1) + "°C" : "-"
                                        color: "grey"
                                    }
                                    Item { Layout.fillWidth: true }
                                    SpinBox {
                                        id: setpointSpin
                                        from: -1000
                                        to: 500
                                        editable: true
                                        textFromValue: (value) => (value / 10).toFixed(1)
                                        valueFromText: (text) => Math.round(parseFloat(text) * 10)
                                    }
                                    Label { text: "°C" }
                                }

                                Button {
                                    Layout.fillWidth: true
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
                        }

                        GroupBox {
                            title: "Temperatures"
                            Layout.fillWidth: true
                            visible: cameraDelegate.temperaturesInterface !== null

                            ColumnLayout {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: cameraDelegate.sortedTemperatureReadings()

                                    delegate: RowLayout {
                                        Layout.fillWidth: true

                                        readonly property var rawValue: cameraDelegate.fieldOf(modelData, "value")

                                        Label { text: cameraDelegate.fieldOf(modelData, "name") + ":" }
                                        Item { Layout.fillWidth: true }
                                        Label {
                                            text: (parent.rawValue === undefined || parent.rawValue === null)
                                                ? "N/A" : parent.rawValue.toFixed(2) + "°C"
                                            color: "grey"
                                        }
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    visible: cameraDelegate.sortedTemperatureReadings().length === 0
                                    text: "(no readings yet)"
                                    color: "grey"
                                    font.italic: true
                                }

                                Button {
                                    Layout.fillWidth: true
                                    text: "Plot temps"
                                    onClicked: temperaturesPlotWindow.visible = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
