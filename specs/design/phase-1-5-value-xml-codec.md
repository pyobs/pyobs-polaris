# Phase 1.5 — value/XML codec (schema-less decode)

Status: implemented, closed.

`codec::WireValue` is **`std::variant`-based, not `QVariant`**: `dict`/
dataclass fields must preserve wire/declaration order (`KeyValueCard.vue`
relies on this), and `QVariantMap` is a `QMap` that sorts by key — no
order-preserving string-keyed container ships as a `QVariant` type. So
`dict`/dataclass decode into an ordered
`std::vector<std::pair<QString, WireValue>>` variant alternative instead.
`codec::xmlToValue(QDomElement)` ports `pyobs-codec.ts`'s `xmlToValue`
switch (`nil`/`boolean`/`int`/`double`/`string`/`items`/`tuple`/`dict`,
default = dataclass root). **Qt Test, not Catch2**, is the project's test
framework throughout — ships with system Qt6 already, and later phases
want `QSignalSpy`-based assertions.

