import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Dedicated page for IWeather modules - see TODO.md's "Custom widget:
// IWeather" for the full design rationale, and DEVELOPMENT.md for why
// there's no live-verification fixture yet (no Dummy* module implements
// IWeather - the only real implementation, pyobs.modules.weather.Weather,
// is an HTTP client to a separate pyobs-weather service).
//
// Deliberately simpler than the ported weatherwidget.py: WeatherState is
// a plain dataclass pushed via normal state publication (good: bool,
// readings: list[WeatherSensorReading{sensor, value, unit, time}]), no
// RPC polling needed at all. Tiles are rendered one per reading
// *present* (readings only ever contains entries for sensors the
// station actually has, not a fixed 11-tile grid) - same dynamic-count
// idiom this project's other custom widgets already use for
// variable-length server-reported lists (e.g. ModeView.qml's
// modeGroups). Units come straight off each reading's own `unit` field
// (module-owned, per Weather's own SENSOR_UNITS) rather than a
// client-side constant map.
//
// Real behavior change vs. weatherwidget.py, not a missing feature:
// WeatherSensorReading no longer carries a per-sensor `good` flag (only
// WeatherState.good, one overall flag) - so there's no wire data left to
// color individual tiles independently. This page colors a single
// "Weather OK"/"Weather BAD" banner from that one flag instead.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    Label {
        text: "Weather"
        font.bold: true
        font.pixelSize: 16
    }

    Repeater {
        model: root.xmppClient.modules

        // Same in-place-update caveat as every other custom widget's
        // Repeater (RoofView.qml/AutoGuidingView.qml/ModeView.qml): this
        // model is a real QAbstractListModel, so delegates are updated
        // in place rather than recreated - explicitly unsubscribe/
        // re-fetch rather than relying on bindings alone.
        delegate: ColumnLayout {
            id: weatherDelegate
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

            // Same indexed-loop safety note as every other custom
            // widget's fieldOf() (see RoofView.qml/AutoGuidingView.qml) -
            // only ever called on an already-reactive `property var`
            // capture, never directly inline on a subscription's
            // `.value`.
            function fieldOf(entries, key) {
                const list = entries || []
                for (let i = 0; i < list.length; ++i) {
                    if (list[i].key === key) {
                        return list[i].value
                    }
                }
                return undefined
            }

            readonly property var weatherInterface: findInterface("IWeather")
            visible: weatherInterface !== null

            property var weatherSubscription: null

            function refreshSubscription() {
                if (weatherSubscription) {
                    weatherSubscription.unsubscribe()
                    weatherSubscription = null
                }
                if (visible && weatherInterface) {
                    weatherSubscription = root.xmppClient.subscribeState(
                        jid, "IWeather", weatherInterface.version, weatherDelegate)
                }
            }

            onVisibleChanged: refreshSubscription()
            onWeatherInterfaceChanged: refreshSubscription()
            Component.onCompleted: refreshSubscription()

            readonly property var weatherState: weatherSubscription ? weatherSubscription.value : undefined

            readonly property var goodValue: fieldOf(weatherState, "good")
            readonly property bool hasGood: goodValue !== undefined && goodValue !== null

            readonly property var readingsList: fieldOf(weatherState, "readings") || []

            // Port of weatherwidget.py's AVERAGE_SENSOR_FIELDS label
            // text, minus "sunalt" (no equivalent left in the current
            // WeatherSensors enum - confirmed from source, not a gap to
            // fill) plus a new "skymag" entry ("Sky mag.", no display
            // entry existed in the old widget to port from). Keyed by
            // each WeatherSensors member's wire *value* (a StrEnum, e.g.
            // "temp"/"humid"), not its member name.
            readonly property var sensorLabels: ({
                "time": "Time",
                "temp": "Temp.",
                "humid": "Rel. humid.",
                "dewpoint": "Dew point",
                "press": "Press.",
                "winddir": "Wind dir",
                "windspeed": "Wind speed",
                "particles": "Particles",
                "rain": "Rain",
                "skytemp": "Rel. sky temp.",
                "skymag": "Sky mag."
            })

            function labelFor(sensor) {
                return weatherDelegate.sensorLabels[sensor] || sensor
            }

            function formatReadingValue(sensor, value) {
                if (value === undefined || value === null) {
                    return "N/A"
                }
                // Matches weatherwidget.py's own "%d" vs "%.2f" split -
                // rain is a 0/1 flag, not a continuous quantity.
                return sensor === "rain" ? value.toFixed(0) : value.toFixed(2)
            }

            RowLayout {
                Label {
                    text: weatherDelegate.name
                    font.bold: true
                }
                Label {
                    text: weatherDelegate.jid
                    color: "grey"
                }
            }

            Label {
                Layout.leftMargin: 8
                visible: weatherDelegate.hasGood
                text: weatherDelegate.goodValue ? "Weather OK" : "Weather BAD"
                color: weatherDelegate.goodValue ? "limegreen" : "red"
                font.bold: true
            }

            Label {
                Layout.leftMargin: 8
                visible: weatherDelegate.readingsList.length === 0
                text: "(no readings yet)"
                color: "grey"
                font.italic: true
            }

            // Flow, not a fixed-column GridLayout: the tile count varies
            // per station (0 to 10 sensors) - see the file header comment.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                spacing: 8

                Repeater {
                    model: weatherDelegate.readingsList

                    delegate: Frame {
                        id: sensorTile
                        required property var modelData

                        readonly property string sensor: weatherDelegate.fieldOf(modelData, "sensor") || ""
                        readonly property var value: weatherDelegate.fieldOf(modelData, "value")
                        readonly property string unit: weatherDelegate.fieldOf(modelData, "unit") || ""

                        implicitWidth: 110

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: weatherDelegate.labelFor(sensorTile.sensor)
                                color: "grey"
                                font.pixelSize: 11
                            }
                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: weatherDelegate.formatReadingValue(sensorTile.sensor, sensorTile.value)
                                font.bold: true
                                font.pixelSize: 16
                            }
                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: sensorTile.unit.length > 0
                                text: sensorTile.unit
                                color: "grey"
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
