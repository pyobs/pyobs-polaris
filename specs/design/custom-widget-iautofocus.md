# Custom widget: `IAutoFocus`

Status: implemented, closed.

First of the three custom widgets tracked in `TODO.md`
("`IAutoFocus`/`IAcquisition`/`IAutoGuiding`"), ported from pyobs-gui's
`autofocuswidget.py` - `qml/views/AutoFocusView.qml`, gated in the
sidebar the same way as Roof (`MainWindow.qml`'s `hasAutoFocusModule`,
`ModuleListModel::hasInterface("IAutoFocus")`). Live-verified against a
real `DummyAutoFocus` (`fixtures/autofocus.yaml`) end to end: running a
series, watching the plot update live, the fitted-focus result appearing
after completion, and aborting mid-run.

**New capability this widget needed that nothing before it did: real RPC
parameters.** Every command call in this project up to now
(`RoofView.qml`'s Open/Close/Stop, `ShellView.qml`'s debug panel) sent
all-null params, which only works because those commands' params are all
declared optional. `IAutoFocus.auto_focus(count: int32, step: float64,
exposure_time: float64)` has none - all three are required, so the
all-null path would fail server-side. Added:
- `codec::fromQVariant(QVariant, WireType)` (`VariantBridge.h/.cpp`) - the
  encode-side counterpart to Phase 4's `toQVariant`. Necessary, not just
  symmetric: `codec::valueToXml()` reads a `WireValue` out via the
  `std::get<>` accessor matching the *target* `WireType` (`toDouble()`
  for `Float64`, etc.), so a `WireValue` built from a plain QVariant
  without checking the schema (e.g. an int-backed `WireValue` for a
  `float64` param - easy to get wrong from a QML `SpinBox`'s integer
  value) throws inside `valueToXml()` rather than just encoding wrong.
- `ModuleListModel::find(bareJid)` - a plain C++-internal lookup (not
  `Q_INVOKABLE`; QML never needs a whole `ModuleInfo`), returning
  `const ModuleInfo *`.
- `XmppClient::executeMethod(bareJid, methodName, QVariantList params,
  QJSValue callback)` - a third overload alongside Phase 5/7's
  paramCount-based ones. Looks up the command's `CommandSchema` from the
  module's already-fetched disco#info (first interface declaring a
  command of that name - same "dispatch by name alone" convention as the
  existing overloads), encodes each `params` entry against the matching
  `FieldSchema` via `fromQVariant`. Reports a client-side failure through
  `callback` without touching the network if the module/command can't be
  found, rather than sending something malformed.

**`PlotItem` (`src/plot/PlotItem.h/.cpp`)** is the first plotting
capability in this project - see `TODO.md`'s "no external library"
decision. A `QQuickPaintedItem` (`QPainter`-based), deliberately minimal:
one scatter series, axes/gridlines/tick labels, one optional dashed
vertical reference line with a label. `points` is a raw, unprocessed
`QVariant` (an array of dataclass-shaped records, e.g.
`AutoFocusState.points`, each a `WireDict`-shaped `{focus, value}` pair)
- parsed entirely in `setPoints()`, in C++, via `QVariant::toList()`/
`toMap()`, positionally (first field = x, second = y, not looked up by
name - wire order is exactly what this project's codec preserves
dict/dataclass fields for everywhere else, so `AutoFocusPoint{focus,
value}` needs no extra config). This is deliberate, not incidental:
letting `AutoFocusView.qml` do that extraction itself in QML/JS (`.map()`
over the state's decoded value) would touch the exact same C++→QML
boundary that caused the roof state-display bug (`specs/design/roof-state-display-bug.md`) - keeping it in
C++ sidesteps that whole class of risk rather than re-verifying JS
array semantics are safe here too.

**A second, real instance of that same C++→QML boundary risk turned up
while wiring this up, caught by trying it - not by static reasoning.**
The natural-looking approach was a `StateSubscription::field(name)`
`Q_INVOKABLE` helper (pull one named field out of the subscription's
current `value`, so QML never has to search it). That method was written
and then found to break reactivity: QML's binding dependency tracking
only captures *property reads*, not C++ method calls - `field()` reads
`m_value` directly in C++, invisible to the tracker, so a binding that
calls `subscription.field("running")` never re-evaluates when the
subscription's `value` actually changes. Removed before it shipped.
`AutoFocusView.qml` instead reads `.value` directly into a `readonly
property var` (a real property read, correctly tracked - the exact same
pattern `RoofView.qml` already uses for its `KeyValueCard.value`
binding), then extracts named fields from *that* via a plain QML-defined
JS function (`fieldOf()`, styled after `RoofView.qml`'s own
`findInterface()`): a JS function call **does** propagate binding
dependencies, because it executes within the same evaluation context as
the binding itself - only a call across the C++/QML meta-object boundary
is opaque to the tracker. `findInterface()`'s plain indexed
`list.length`/`list[i]` loop (not `Array.isArray()`, not `.map()`/
`.filter()`) was already proven safe live before this widget existed;
`fieldOf()` reuses that exact style for the same reason.

**A third gotcha, also only caught live:** the fitted-focus result
(`FocusFoundEvent`) never showed up in the plot on the first end-to-end
run, despite the RPC itself succeeding and the event genuinely being
sent - `EventManager::handlePubSubEvent` sets `PyobsEvent::module` from
`QXmppUtils::jidToUser(element.attribute("from"))`, i.e. just the
JID's user part ("autofocus"), never the bare JID ("autofocus@localhost")
`ModuleListModel`'s `jid` role holds. `AutoFocusView.qml` was comparing
`FocusFoundEvent` entries against the bare JID directly, which silently
never matched. `LogsView.qml` never hit this because its own module
filter only ever compares event-supplied `module` values against each
other, never against `ModuleListModel`. Fixed by comparing against
`jid.split("@")[0]` instead - worth checking for again in
`AcquisitionView`/`AutoGuidingView` if they end up matching events to a
specific module the same way.

