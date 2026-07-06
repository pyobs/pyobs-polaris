#pragma once

#include "WireValue.h"

class QDomElement;

namespace codec {

// Strips any namespace prefix from an element's tag name, mirroring
// pyobs-codec.ts's localTag(). Wire value tags are never themselves
// namespace-prefixed, but staying defensive here costs nothing and matches
// the TS port's intent line-for-line.
QString localTag(const QDomElement &element);

// Ports pyobs-codec.ts's xmlToValue: schema-less decode, every value on the
// wire is self-tagged so no type information is needed to decode it.
WireValue xmlToValue(const QDomElement &element);

}
