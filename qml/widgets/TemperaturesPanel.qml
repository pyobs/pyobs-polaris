import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Self-contained ITemperatures widget: a sorted read-only sensor readout
// plus a "Plot temps" window with a live multi-sensor history plot,
// per-sensor checkboxes, and a time-range filter - ports pyobs-gui's
// temperatureswidget.py/temperaturesplotwidget.py. Originally built
// inline in CameraView.qml's cameraDelegate; factored out here once
// TelescopeView.qml needed the exact same widget (DummyTelescope also
// implements ITemperatures) rather than duplicating this much state/UI.
//
// The host page (CameraView.qml/TelescopeView.qml) still owns its own
// findInterface()/statefulInterfaces lookup and just hands the result in
// via `interfaceInfo` - this component manages its own subscription
// lifecycle (Component.onCompleted/onDestruction) independently, so it
// works the same regardless of which page embeds it.
GroupBox {
    id: root

    required property var xmppClient
    required property string jid
    required property string moduleName // for the plot window's title
    required property var statefulInterfaces

    function findInterface(name) {
        const list = root.statefulInterfaces || []
        for (let i = 0; i < list.length; ++i) {
            if (list[i].name === name) {
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

    readonly property var interfaceInfo: root.findInterface("ITemperatures")

    title: "Temperatures"
    visible: root.interfaceInfo !== null

    property var subscription: null

    function refreshSubscription() {
        if (root.subscription) {
            root.subscription.unsubscribe()
            root.subscription = null
        }
        if (root.visible && root.interfaceInfo) {
            root.subscription = root.xmppClient.subscribeState(
                root.jid, "ITemperatures", root.interfaceInfo.version, root)
        }
    }

    onVisibleChanged: refreshSubscription()
    onInterfaceInfoChanged: refreshSubscription()
    Component.onCompleted: refreshSubscription()

    readonly property var state: root.subscription ? root.subscription.value : undefined
    readonly property var readings: fieldOf(root.state, "readings") || []

    // ITemperatures' own wire state is only ever the latest snapshot (see
    // pyobs.interfaces.ITemperatures) - there's no history on the wire,
    // so the "Plot temps" window's history is accumulated client-side
    // here, mirroring pyobs-gui's TemperaturesWidget._on_temperatures_state()/
    // TemperaturesPlotWidget.add_data(): every new snapshot appends one
    // point per sensor name. A plain JS object used as a name -> point-
    // array map, always reassigned wholesale (not mutated in place) - a
    // QML binding only re-evaluates on property reassignment. Capped per
    // sensor (maxHistoryPoints) so a long-running session doesn't grow
    // this unboundedly - pyobs-gui has no such cap (an in-memory pandas
    // DataFrame kept for the life of the plot window, never pruned
    // either), but this project's own window can just as easily stay
    // open indefinitely.
    property var history: ({})
    readonly property int maxHistoryPoints: 500

    function recordHistory() {
        const currentReadings = root.readings
        if (!currentReadings || currentReadings.length === 0) {
            return
        }
        const now = Date.now() / 1000
        const next = Object.assign({}, root.history)
        for (let i = 0; i < currentReadings.length; ++i) {
            const name = fieldOf(currentReadings[i], "name")
            const value = fieldOf(currentReadings[i], "value")
            if (name === undefined || value === undefined || value === null) {
                continue
            }
            const series = (next[name] || []).concat([{ x: now, y: value }])
            next[name] = series.length > root.maxHistoryPoints
                ? series.slice(series.length - root.maxHistoryPoints) : series
        }
        root.history = next
    }

    onStateChanged: recordHistory()

    function sortedReadings() {
        const list = (root.readings || []).slice()
        list.sort(function (a, b) {
            const nameA = fieldOf(a, "name") || ""
            const nameB = fieldOf(b, "name") || ""
            return nameA < nameB ? -1 : (nameA > nameB ? 1 : 0)
        })
        return list
    }

    // Which sensors the "Plot temps" window currently shows, keyed by
    // name - lets a user isolate one/some sensors on a busy multi-sensor
    // module instead of always plotting every one (pyobs-gui's own
    // temperaturesplotwidget.py has no such toggle, always plots every
    // column). A name absent from this map defaults to shown, so a
    // newly-discovered sensor appears selected without needing its own
    // explicit entry.
    property var selectedSeries: ({})

    function isSeriesSelected(name) {
        return root.selectedSeries[name] !== false
    }

    function setSeriesSelected(name, selected) {
        const next = Object.assign({}, root.selectedSeries)
        next[name] = selected
        root.selectedSeries = next
    }

    // "Plot temps" window's time-range filter - ports pyobs-gui's
    // temperaturesplotwidget.py comboShow ("All"/"Last minute"/
    // "Last 5 minutes"), just with "Last hour" instead of "Last minute"
    // (a maxHistoryPoints-capped, ~1-point-per-second buffer makes "last
    // minute" barely distinguishable from "last 5 minutes" here). -1
    // means "All" - no cutoff.
    property int plotWindowSeconds: -1

    function plotSeries() {
        const names = Object.keys(root.history).sort()
        const cutoff = root.plotWindowSeconds > 0 ? (Date.now() / 1000 - root.plotWindowSeconds) : -Infinity
        const result = []
        for (let i = 0; i < names.length; ++i) {
            if (!root.isSeriesSelected(names[i])) {
                continue
            }
            const points = root.history[names[i]].filter(function (p) { return p.x >= cutoff })
            result.push({ label: names[i], points: points })
        }
        return result
    }

    // Declared before the "Plot temps" Button below that references its
    // id - a real bug hit while building this the first time: this
    // project's AOT-compiled (qmlcachegen) setup didn't resolve a forward
    // id reference from a signal handler across a Window boundary the
    // way plain interpreted QML would (see DEVELOPMENT.md).
    ApplicationWindow {
        id: plotWindow
        width: 640
        height: 420
        title: "Temperatures — " + root.moduleName
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
                        // Every sensor seen so far, not just the ones
                        // currently selected - a deselected sensor's
                        // checkbox must stay put (just unchecked), not
                        // disappear.
                        model: Object.keys(root.history).sort()

                        delegate: CheckBox {
                            text: modelData
                            checked: root.isSeriesSelected(modelData)
                            onToggled: root.setSeriesSelected(modelData, checked)
                        }
                    }
                }

                Label { text: "Show:" }
                ComboBox {
                    id: plotWindowRangeCombo
                    model: ["Last 5 minutes", "Last hour", "All"]
                    currentIndex: 2

                    onActivated: {
                        switch (currentIndex) {
                        case 0:
                            root.plotWindowSeconds = 5 * 60
                            break
                        case 1:
                            root.plotWindowSeconds = 60 * 60
                            break
                        default:
                            root.plotWindowSeconds = -1
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
                series: root.plotSeries()
            }
        }
    }

    ColumnLayout {
        width: parent.width
        spacing: 6

        Repeater {
            model: root.sortedReadings()

            delegate: RowLayout {
                Layout.fillWidth: true

                readonly property var rawValue: root.fieldOf(modelData, "value")

                Label { text: root.fieldOf(modelData, "name") + ":" }
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
            visible: root.sortedReadings().length === 0
            text: "(no readings yet)"
            color: "grey"
            font.italic: true
        }

        Button {
            Layout.fillWidth: true
            text: "Plot temps"
            onClicked: plotWindow.visible = true
        }
    }
}
