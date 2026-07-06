#pragma once

#include "WireType.h"
#include "WireValue.h"

class QXmlStreamWriter;

namespace codec {

// Ports pyobs-codec.ts's valueToXml: the encode half of the codec. Unlike
// decoding, encoding needs the WireType (from a CommandSchema, Phase 2) -
// it isn't self-describing (e.g. the int32-vs-float64 ambiguity called out
// in pyobs-codec.ts's header comment applies here too).
//
// Writes directly to a QXmlStreamWriter rather than building a QDomElement
// first: there's no natural "detached DOM element" concept for building
// outgoing XML in Qt the way there is in JS, and outgoing IQs in this
// project are already built via QXmlStreamWriter (see Discovery.cpp).
//
// struct<Name>/any/void can't be encoded from schema alone (pyobs-core
// doesn't publish struct field lists) - throws std::runtime_error, matching
// the TS port's behavior. No real command takes one of these as a
// parameter today.
void valueToXml(QXmlStreamWriter &writer, const WireValue &value, const WireType &type);

}
