import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import pyobs.polaris

import "../widgets/Permissions.js" as Permissions

// Dedicated page for IMode modules, ported from pyobs-gui's modewidget.py
// (ModeWidget) - see TODO.md. Only reachable via the sidebar while at
// least one connected module implements IMode (see MainWindow.qml's
// hasModeModule). One row per mode "group" the module reports via its
// static IMode capabilities (ModuleListModel::ModeGroupsRole) - a
// ComboBox per group, populated from that group's static option list.
// Controls stay disabled until IMotion state reaches the same
// "initialized" set modewidget.py::update_gui already uses.
//
// Direct instruction: selecting an option in the ComboBox must NOT itself
// call set_mode - unlike modewidget.py's own onActivated-applies-
// immediately behavior (and unlike this project's own earlier port of
// it), picking an item from a dropdown is too easy to trigger by
// accident (scrolling, a stray click) for that to fire a real mode
// change. A real three-column table instead (label/current/new, one row
// per group - built from three parallel Repeaters over the same
// modeGroups list with the GridLayout's own flow set to TopToBottom, the
// standard way to get a Repeater to fill one whole column at a time
// rather than interleaving row-by-row) with a single shared "Set" button
// below it, batch-applying every group whose staged selection actually
// differs from its current mode - same fetch-once-then-explicit-apply
// shape as CameraView.qml's Window/Gain (staged selections live in
// stagedModes below, seeded once per group from the first state push),
// just one button for every row instead of Camera's one Expose doing
// double duty as both "apply settings" and "the actual action" - Mode
// has no equivalent single action to batch onto, so Set only ever does
// the applying.
//
// Layout: modewidget.ui itself is just a single "Modes" GroupBox (a
// status field, read directly from the .ui) - the mode-group ComboBox
// rows are added to that *same* GroupBox's form layout at runtime
// (modewidget.py:69, one per group, confirmed from source), not a
// separate section. Ported as one GroupBox here too, same as
// CameraView.qml/TelescopeView.qml's GroupBox treatment.
ColumnLayout {
    id: root

    required property var xmppClient

    spacing: 8

    Label {
        text: "Mode"
        font.bold: true
        font.pixelSize: 16
    }

    Repeater {
        model: root.xmppClient.modules

        // Same in-place-update caveat as every other custom widget's
        // Repeater (RoofView.qml/AutoFocusView.qml/AutoGuidingView.qml):
        // this model is a real QAbstractListModel, so delegates are
        // updated in place rather than recreated - explicitly
        // unsubscribe/re-fetch rather than relying on bindings alone.
        delegate: ColumnLayout {
            id: modeDelegate
            Layout.fillWidth: true

            required property string jid
            required property string name
            required property var statefulInterfaces
            required property var modeGroups
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

            // Same indexed-loop safety note as every other custom
            // widget's fieldOf() (see RoofView.qml/AutoFocusView.qml) -
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

            readonly property var modeInterface: findInterface("IMode")
            readonly property var motionInterface: findInterface("IMotion")
            visible: modeInterface !== null

            property var modeSubscription: null
            property var motionSubscription: null

            function refreshSubscriptions() {
                if (modeSubscription) {
                    modeSubscription.unsubscribe()
                    modeSubscription = null
                }
                if (motionSubscription) {
                    motionSubscription.unsubscribe()
                    motionSubscription = null
                }
                if (visible && modeInterface) {
                    modeSubscription = root.xmppClient.subscribeState(
                        jid, "IMode", modeInterface.version, modeDelegate)
                }
                if (visible && motionInterface) {
                    motionSubscription = root.xmppClient.subscribeState(
                        jid, "IMotion", motionInterface.version, modeDelegate)
                }
            }

            onVisibleChanged: refreshSubscriptions()
            onModeInterfaceChanged: refreshSubscriptions()
            onMotionInterfaceChanged: refreshSubscriptions()
            Component.onCompleted: refreshSubscriptions()

            readonly property var modeState: modeSubscription ? modeSubscription.value : undefined
            readonly property var motionState: motionSubscription ? motionSubscription.value : undefined

            // dict[str, str] (group -> current mode), itself decoded as a
            // {key, value}-entry list the same way modeState/motionState
            // are - one more fieldOf() lookup per group below.
            readonly property var modesByGroup: fieldOf(modeState, "modes")

            readonly property string motionStatus: fieldOf(motionState, "status") || ""
            readonly property bool initialized: motionStatus === "slewing" || motionStatus === "tracking"
                || motionStatus === "idle" || motionStatus === "positioned"

            // group -> staged (not-yet-applied) selection. Seeded once per
            // group from the first state push that reports it (fetch-once,
            // same as CameraView.qml's Window/Gain/ExposureTime), then left
            // entirely to the user - the ComboBox delegates below bind
            // their currentIndex to this dict, not to modesByGroup
            // directly, so nothing here ever fights an in-progress
            // selection with a live resync.
            property var stagedModes: ({})

            function stagedModeFor(group) {
                return stagedModes[group] !== undefined ? stagedModes[group] : ""
            }

            function setStagedMode(group, mode) {
                const updated = Object.assign({}, stagedModes)
                updated[group] = mode
                stagedModes = updated
            }

            onModesByGroupChanged: {
                if (!modesByGroup) {
                    return
                }
                const groups = modeDelegate.modeGroups || []
                let updated = null
                for (let i = 0; i < groups.length; ++i) {
                    const group = groups[i].group
                    if (stagedModes[group] !== undefined) {
                        continue
                    }
                    const current = fieldOf(modesByGroup, group)
                    if (current === undefined || current === null) {
                        continue
                    }
                    if (updated === null) {
                        updated = Object.assign({}, stagedModes)
                    }
                    updated[group] = current
                }
                if (updated !== null) {
                    stagedModes = updated
                }
            }

            // Fires set_mode only for groups whose staged selection
            // actually differs from the current mode - re-sending an
            // already-current mode could have real side effects depending
            // on the module (e.g. re-triggering a physical filter wheel
            // move), not just a wasted RPC.
            function applyStagedModes() {
                modeDelegate.lastError = ""
                const groups = modeDelegate.modeGroups || []
                for (let i = 0; i < groups.length; ++i) {
                    const group = groups[i].group
                    const staged = modeDelegate.stagedModeFor(group)
                    const current = fieldOf(modeDelegate.modesByGroup, group) || ""
                    if (staged === "" || staged === current) {
                        continue
                    }
                    root.xmppClient.executeMethod(
                        modeDelegate.jid, "set_mode", [staged, group],
                        function (result) {
                            if (!result.success) {
                                modeDelegate.lastError = (result.errorClass ? result.errorClass + ": " : "") + result.errorMessage
                            }
                        })
                }
            }

            property string lastError: ""

            RowLayout {
                Label {
                    text: modeDelegate.name
                    font.bold: true
                }
                Label {
                    text: modeDelegate.jid
                    color: "grey"
                }
            }

            GroupBox {
                title: "Modes"
                Layout.leftMargin: 8
                Layout.preferredWidth: 320

                ColumnLayout {
                    width: parent.width
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Status:" }
                        Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modeDelegate.motionStatus.toUpperCase()
                        }
                    }

                    // Real three-column table (label/current/new) - three
                    // Repeaters over the same modeGroups list, one per
                    // column, with flow: TopToBottom so each Repeater
                    // fills its whole column before moving to the next
                    // (the standard way to get column-major fill order
                    // out of GridLayout; row-major, the default, would
                    // interleave labels/current/combos across rows
                    // instead of down columns).
                    GridLayout {
                        id: modesGrid
                        Layout.fillWidth: true
                        columns: 3
                        flow: GridLayout.TopToBottom
                        rows: (modeDelegate.modeGroups || []).length
                        columnSpacing: 12
                        rowSpacing: 4

                        Repeater {
                            model: modeDelegate.modeGroups || []
                            delegate: Label {
                                required property string group
                                text: group
                                font.bold: true
                            }
                        }

                        Repeater {
                            model: modeDelegate.modeGroups || []
                            delegate: Label {
                                required property string group
                                text: {
                                    const current = modeDelegate.fieldOf(modeDelegate.modesByGroup, group)
                                    return (current === undefined || current === null || current === "") ? "-" : current
                                }
                                color: "grey"
                            }
                        }

                        Repeater {
                            model: modeDelegate.modeGroups || []
                            delegate: ComboBox {
                                required property string group
                                required property var modes
                                Layout.fillWidth: true
                                model: modes || []
                                enabled: modeDelegate.initialized
                                currentIndex: indexOfValue(modeDelegate.stagedModeFor(group))
                                onActivated: modeDelegate.setStagedMode(group, currentText)
                            }
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Set"
                        enabled: modeDelegate.initialized && Permissions.isPermitted(modeDelegate.permittedMethods, "set_mode")
                        onClicked: modeDelegate.applyStagedModes()
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: modeDelegate.lastError.length > 0
                        text: modeDelegate.lastError
                        color: "red"
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
