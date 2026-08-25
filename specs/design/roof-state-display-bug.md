# Roof state display bug: `Array.isArray()` is unreliable across the C++/QML boundary

Status: implemented, closed.

`RoofView.qml`'s `KeyValueCard` was stuck on "(no value yet)" even after a
real state change, first flagged as never-visually-verified in the old
`RoofWidget` TODO entry (see `specs/design/dashboard-and-roofwidget-removed.md`) and
finally checked against a live `DummyRoof` module + real display this
session. Root-caused with the same headless/live-verification discipline
as everywhere else in this project - registered a throwaway `roof` XMPP
account on the dev ejabberd server (password `pyobs`, matching the other
dummy modules'), ran a real `DummyRoof`, and read temporary `qInfo()`/
`console.log()` diagnostics while clicking Open/Close in a real window on
a real Wayland session.

The whole C++ side was already correct: `subscribe()`/`subscribeToNode()`/
`fetchCurrentValue()` all succeeded, and `dispatchValue()` fired repeatedly
with the right `QVariant` content (a `QVariantList` of `{"key", "value"}`
entries, exactly what `codec::toQVariant()` is supposed to produce). The
diagnostic that pinned it down was in `KeyValueCard.qml` itself:
`JSON.stringify(value)` printed proper `[...]` array syntax, but
`Array.isArray(value)` on that same value was `false`. **A `QVariantList`
crossing into QML via a `Q_PROPERTY(QVariant ...)` (here,
`StateSubscription::value`) arrives as a list-like/iterable object that
`JSON.stringify` and `Repeater.model` both handle as a sequence, but which
fails the strict ECMAScript `Array.isArray()` check.** `KeyValueCard.qml`
gated *both* its placeholder text's visibility and its `Repeater`'s
`model` on `Array.isArray(root.value)` - so the value was correctly
delivered all the way to QML and then silently discarded by that check on
every single dispatch.

Fix: `KeyValueCard.qml` now gates on `value !== undefined && value !==
null` (`hasValue`) instead of `Array.isArray(value)` - the only thing that
ever needs excluding is "no value has arrived yet." `Repeater.model`
itself was always fine consuming the list-like value directly; it was
only the `Array.isArray()` guard in front of it that was wrong. No C++
changes were needed - `codec::toQVariant()`, `StateSubscriptionManager`,
and `StateSubscription` were all already correct, confirmed by this
session's live trace. Worth remembering for any future generic-rendering
code that inspects a `QVariant`-typed value in QML: don't reach for
`Array.isArray()`/`typeof value === "object"` assumptions borrowed from
plain JS - a value that *behaves* like an array/object across this
boundary doesn't necessarily *pass as* one under strict JS type checks.

