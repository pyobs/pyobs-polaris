import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Generic "boring" state display: renders a decoded dataclass-shaped
// WireValue - bridged to a QVariantList of {key, value} entries by
// codec::toQVariant (order-preserving, never re-sorted, see
// codec/VariantBridge.h) - as field-name -> value rows via a Repeater.
// Every future interface-specific widget embeds this for whatever it
// doesn't want to hand-design its own UI for - same role as
// ModuleStateCard.vue/KeyValueCard.vue in the web client.
ColumnLayout {
    id: root

    // QVariantList of {"key":..., "value":...} entries (see
    // StateSubscription.value / codec::toQVariant), or undefined/null
    // before the first value has arrived.
    property var value

    spacing: 2

    // Not Array.isArray(value): a QVariantList crossing the C++/QML
    // boundary as a `QVariant value` Q_PROPERTY (StateSubscription::value)
    // arrives as a list-like/iterable object - JSON.stringify and Repeater
    // both handle it as a sequence, but it fails the strict ECMAScript
    // Array.isArray() check, so gating rendering on that check left every
    // real value stuck behind the "no value yet" placeholder. undefined/
    // null (before the first value arrives) is the only thing to exclude.
    readonly property bool hasValue: value !== undefined && value !== null

    function formatValue(v) {
        if (v === null || v === undefined) {
            return "—" // em dash, matches KeyValueCard.vue's "—" for null/undefined
        }
        if (typeof v === "boolean") {
            return v ? "true" : "false"
        }
        if (typeof v === "object") {
            return JSON.stringify(v)
        }
        return String(v)
    }

    Label {
        Layout.fillWidth: true
        visible: !root.hasValue
        text: "(no value yet)"
        color: "grey"
        font.italic: true
    }

    Repeater {
        model: root.hasValue ? root.value : []

        delegate: RowLayout {
            Layout.fillWidth: true

            Label {
                Layout.preferredWidth: 140
                text: modelData.key
                color: "grey"
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: root.formatValue(modelData.value)
                wrapMode: Text.WrapAnywhere
            }
        }
    }
}
