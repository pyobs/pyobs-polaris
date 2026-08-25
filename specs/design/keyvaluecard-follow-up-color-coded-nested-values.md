# `KeyValueCard.qml` follow-up: color-coded nested values, ported from `statuswidget.py`

Status: implemented, closed.

Direct request: "I like the way pyobs-gui does this better" - `KeyValueCard`'s
nested/list values (e.g. `IWeather`'s `readings` field, a `WireList` of
per-sensor `WireDict`s) were previously dumped with a plain
`JSON.stringify()`, unreadable next to `statuswidget.py`'s own recursive,
color-coded `_format_value_html()`/`_format_dataclass_html()`. Ported that
scheme: field names in a normal-contrast "key" color, leaf values in an
amber "value" accent, brackets/braces in a muted punctuation color,
recursing into nested dicts (`{field=value, field=value}`) and lists
(`[value, value]`) the same way. One deliberate simplification: no
leading type name for a nested dict the way pyobs-gui prefixes one via
Python's `type(value).__name__` - `codec::WireValue` is schema-less by
design (see `WireValue.h`) and never reconstructs a dataclass name at
decode time, so there's nothing to put there. Also deliberately just one
fixed color set, not pyobs-gui's own light/dark-palette-aware pair
(`_detail_colors()`) - this app has no other runtime light/dark branching
anywhere (every other hand-picked color in this codebase is a single
fixed value) and always renders with Fusion's dark look in practice.

The real ambiguity: a `WireDict` and a `WireList` both cross the C++/QML
boundary as the same kind of list-like object (`codec::toQVariant`, see
`VariantBridge.h`) - a dict is always encoded as a list of `{"key":...,
"value":...}` entries, so `isDictShaped()` treats exactly that shape (a
non-empty list whose first element has both a `key` and a `value`
property) as "this is really a dict," everything else as a plain list.
Verified live with a throwaway synthetic value temporarily substituted
into `StatusView.qml` (a nested dict, a plain list, and a list of dicts
shaped like a real `IWeather` reading - `{sensor=temp, value=15}` came out
exactly as expected, then removed once confirmed) plus a full
`scripts/screenshot_page.py Status ... --click "Expand all"` pass against
the live fixtures - every real field (`IModule` capabilities, `IRunning`/
`IAcquisition`/`IAutoFocus` state, empty `IConfig capabilities` `caps: []`)
rendered with the right colors and no leftover raw JSON anywhere.

