# Phase 4 — generic state subscription + rendering

Status: implemented, closed.

`subscribeState(bareJid, interfaceName, version)`: ref-counted PubSub
subscribe/unsubscribe (server node naming
`pyobs:state:{module}:{Interface}:{version}`; only actually unsubscribes
from the server when the last QML-side watcher goes away), retry-with-
backoff on subscribe races, plus an explicit "fetch current value" IQ to
close the race between a live push and the subscribe ack. `widgets/
KeyValueCard.qml` renders any decoded `WireValue` dataclass-shaped record
generically. `codec::toQVariant` bridges `WireValue` → `QVariant`: a
`WireDict` becomes an order-preserving `QVariantList` of `{"key", "value"}`
entries, never a `QVariantMap` (would re-sort alphabetically). Gotchas:
`QXmppPubSubManager` is **not** part of `BasicExtensions` and must be added
explicitly, or `findExtension<QXmppPubSubManager>()` returns null and the
first `subscribe()` segfaults (caught by `tst_statesubscription`'s
double-subscribe/single-unsubscribe test before any live testing).

