import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

// Example plugin (TODO.md's "Plugin mechanism for custom module widgets",
// step 2) - see PluginLoader.qml's own doc comment for the full contract
// this file implements. Ships as a worked reference, not wired into the
// app's own build (this directory is never in CMakeLists.txt's
// QML_FILES) - point AppSettings::pluginsDirectory at this directory to
// actually load it.
//
// Shows ITelescope's IMotion state (that interface is a bare IMotion
// marker with no fields/commands of its own - see TODO.md's own
// "Custom widget: ITelescope (MVP)" notes) with Init/Park/Stop buttons -
// essentially RoofView.qml's own shape pointed at a different interface,
// proof that a plugin can cover a real interface this repo ships no
// built-in widget for at all.
QtObject {
    id: pluginRoot

    // Bound by PluginLoader.qml to the app's real XmppClient when this
    // plugin is instantiated - the exact same context every built-in
    // widget already gets (`modules`, `subscribeState()`,
    // `executeMethod()`), not a narrower plugin-only API.
    required property var xmppClient

    // Registration metadata, read by PluginLoader.qml after instantiating
    // this root object - see its own doc comment for the full field list.
    readonly property string targetInterface: "ITelescope"
    readonly property string iconGlyph: "🔭"
    readonly property string label: "Telescope (plugin)"

    // The actual widget UI - instantiated later via Loader (see
    // MainWindow.qml's StackLayout), same as a built-in widget's own
    // Component. References pluginRoot.xmppClient via closure exactly
    // like MainWindow.qml's own `roofComponent` etc. reference `root.
    // xmppClient` - this Component is declared inside the same file as
    // pluginRoot, so that closure works the same way here.
    readonly property Component widget: Component {
        ColumnLayout {
            spacing: 8

            Label {
                text: "Telescope (plugin)"
                font.bold: true
                font.pixelSize: 16
            }

            Repeater {
                model: pluginRoot.xmppClient.modules

                // Same in-place-update caveat as every built-in widget's
                // own per-module Repeater (RoofView.qml et al.): this
                // model is a real QAbstractListModel, so delegates are
                // updated in place rather than recreated - explicitly
                // unsubscribe/re-fetch rather than relying on bindings
                // alone.
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

                    readonly property var motionInterface: findInterface("IMotion")
                    visible: findInterface("ITelescope") !== null

                    property var subscription: null

                    function refreshSubscription() {
                        if (subscription) {
                            subscription.unsubscribe()
                            subscription = null
                        }
                        if (visible && motionInterface) {
                            subscription = pluginRoot.xmppClient.subscribeState(
                                jid, "IMotion", motionInterface.version, telescopeDelegate)
                        }
                    }

                    onVisibleChanged: refreshSubscription()
                    onMotionInterfaceChanged: refreshSubscription()
                    Component.onCompleted: refreshSubscription()

                    property string running: "" // action currently in flight, "" if none
                    property string lastError: ""

                    function run(action, paramCount) {
                        telescopeDelegate.running = action
                        telescopeDelegate.lastError = ""
                        pluginRoot.xmppClient.executeMethod(jid, action, paramCount, function (result) {
                            if (!result.success) {
                                telescopeDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "")
                                    + result.errorMessage
                            }
                            telescopeDelegate.running = ""
                        })
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
                        value: telescopeDelegate.subscription ? telescopeDelegate.subscription.value : undefined
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
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
