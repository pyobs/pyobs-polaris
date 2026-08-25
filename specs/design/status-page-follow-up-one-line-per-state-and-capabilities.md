# Status page follow-up: one-line-per-State/Capabilities, matching `statuswidget.py` exactly

Status: implemented, closed.

Direct follow-up: "I mean I like the overall design for this whole
feature better in pyobs-gui. The one-line per State/Cap." The previous
section's first pass (badges row for interfaces, a bold interface-name
heading followed by a whole `KeyValueCard` table per stateful/
capabilities-bearing interface) was closer to this project's own earlier
generic-rendering conventions than to `statuswidget.py`'s actual
`_add_module_details()` shape, which is one *single* rich-text line per
category: `"Interfaces: A, B, C"` (plain, one line total), then one
`"Capabilities (X): field=value, ..."` line per capabilities-bearing
interface, then one `"State (X): field=value, ..."` line per stateful
interface - reordered/rewritten in `StatusView.qml` to match that
directly, replacing the badges `Flow` and both `KeyValueCard`-based
`Repeater`s with plain `Label`s. Colors are `_DARK_DETAIL_COLORS`'s own
`interfaces`/`capabilities`/`state` entries (`#9aa0a6`/`#8ab4f8`/
`#81c995`), stored as `StatusView.qml`-local properties since they're
this page's own row-*category* colors, distinct from
`WireValueFormat.js`'s wire-*value* colors (key/value/punctuation) below.

This split the recursive value-formatting logic (previously private to
`KeyValueCard.qml`) out into a new shared `qml/widgets/WireValueFormat.js`
(a plain `.pragma library` JS module, added to `CMakeLists.txt`'s
`QML_FILES` like any other qml-module resource) - `KeyValueCard.qml`
still needs it for its own per-row values (RoofView/TelescopeQuickView's
plugin example still render a whole live-state table that way, a
different and still-valid design for a single-interface widget embedded
in a `GroupBox`), while `StatusView.qml` now needs the *same* recursive
formatter but for a single inline line instead of a table. Added one
genuinely new function alongside the ported `formatValueHtml()`
(nested values, kept its brace-wrapping): `formatDictInline()`, the
top-level counterpart matching `_format_dataclass_html()` exactly -
comma-joined `field=value` pairs with *no* enclosing braces, since only
*nested* dict values get pyobs-gui's `TypeName(...)`-style wrapping (here,
just `{...}`, see the previous section's note on why no type name).

Live state lines keep exactly the same `subscribeState()` lifecycle as
before (`Component.onCompleted`/`Component.onDestruction` on the
`Repeater` delegate, now a `Label` instead of a `ColumnLayout` wrapping a
`KeyValueCard`) - only the visual output changed, not the subscription
plumbing. Verified live the same way as the previous two rounds
(`scripts/screenshot_page.py Status ... --click "Expand all"` against the
real fixtures): every module's `Interfaces:`/`Capabilities (X):`/
`State (X):` lines rendered correctly in one line each, including
`IWeather`'s `readings` field recursing correctly into a list of
per-sensor dicts (`{sensor=temp, value=15, unit=celsius, ...}`) inline
rather than as a separate table row, and `--click "Collapse all"`
afterward tore every subscription down cleanly with no QML errors in the
log.

