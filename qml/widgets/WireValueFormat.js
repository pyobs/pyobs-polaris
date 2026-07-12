.pragma library

// Shared by KeyValueCard.qml (per-row values) and StatusView.qml (single-
// line "Capabilities (X): ..."/"State (X): ..." rows) - ports pyobs-gui's
// statuswidget.py _detail_colors()/_format_value_html()/
// _format_dataclass_html() color-coded rendering. One fixed color set,
// not pyobs-gui's own light/dark-palette-aware pair: this app has no
// other runtime light/dark branching anywhere, and always renders with
// Fusion's dark look in practice - see DEVELOPMENT.md.
var keyColor = "#e8eaed"
var valueColor = "#f2a660"
var punctuationColor = "#9aa0a6"

function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function span(color, text) {
    return "<span style=\"color:" + color + ";\">" + text + "</span>"
}

// A WireDict (nested struct/capabilities value) and a WireList both cross
// the C++/QML boundary as the same kind of list-like object (see
// codec::toQVariant / VariantBridge.h) - a dict is always encoded as a
// list of {"key":..., "value":...} entries, so that shape is what
// distinguishes "this is really a dict" from an ordinary list of values.
function isDictShaped(list) {
    return list.length > 0 && typeof list[0] === "object" && list[0] !== null
           && list[0].key !== undefined && list[0].value !== undefined
}

// Recurses into nested dicts/lists exactly like pyobs-gui's own
// _format_value_html() - `{field=value, field=value}` for a dict,
// `[value, value]` for a list - just without a leading type name
// (pyobs-gui's Python dataclasses carry a real class name at render time
// via type(value).__name__; codec::WireValue is schema-less by design and
// never reconstructs one, see WireValue.h).
function formatValueHtml(v) {
    if (v === null || v === undefined) {
        return span(valueColor, "—") // em dash, matches KeyValueCard.vue's "—" for null/undefined
    }
    if (typeof v === "boolean") {
        return span(valueColor, v ? "true" : "false")
    }
    if (typeof v === "object") {
        if (isDictShaped(v)) {
            const fields = []
            for (let i = 0; i < v.length; ++i) {
                fields.push(span(keyColor, escapeHtml(v[i].key)) + "=" + formatValueHtml(v[i].value))
            }
            return span(punctuationColor, "{") + fields.join(span(punctuationColor, ", ")) + span(punctuationColor, "}")
        }
        const items = []
        for (let i = 0; i < v.length; ++i) {
            items.push(formatValueHtml(v[i]))
        }
        return span(punctuationColor, "[") + items.join(span(punctuationColor, ", ")) + span(punctuationColor, "]")
    }
    return span(valueColor, escapeHtml(v))
}

// Top-level counterpart to formatValueHtml() above - ports
// statuswidget.py's _format_dataclass_html(), used to render a whole
// State/Capabilities dict as one line ("State (IWeather): good=true,
// readings=[...]"): comma-joined "key=value" pairs with no enclosing
// braces, unlike a *nested* dict value (which does get braces, from
// formatValueHtml() above - the closest available substitute for
// pyobs-gui's own TypeName(...) wrapper, see that function's own doc
// comment on why there's no type name available here).
function formatDictInline(list) {
    if (!list || list.length === 0) {
        return span(punctuationColor, "(empty)")
    }
    const fields = []
    for (let i = 0; i < list.length; ++i) {
        fields.push(span(keyColor, escapeHtml(list[i].key)) + "=" + formatValueHtml(list[i].value))
    }
    return fields.join(span(punctuationColor, ", "))
}
