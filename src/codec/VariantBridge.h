#pragma once

#include "WireType.h"
#include "WireValue.h"

#include <QVariant>

namespace codec {

// Bridges a decoded WireValue to QVariant for QML consumption (KeyValueCard
// and friends). dict/list order is preserved: a WireDict becomes a
// QVariantList of {"key":..., "value":...} entries (index-ordered, exactly
// what a QML Repeater iterates), never a QVariantMap - that's a QMap and
// would silently re-sort fields alphabetically, undoing the entire reason
// WireValue itself isn't QVariant-based (see WireValue.h).
QVariant toQVariant(const WireValue &value);

// The encode-side counterpart: bridges a QML-supplied QVariant (real
// command-parameter values, e.g. AutoFocusView.qml's count/step/
// exposure_time spin boxes) into a WireValue built with the C++ type
// `type` actually calls for. This matters because WireValue is a
// std::variant and codec::valueToXml() dispatches by the *target* WireType
// but reads the value out via the matching std::get<> accessor
// (value.toDouble() for Float64, etc.) - handing it a WireValue holding a
// qint64 for a Float64 param would throw inside valueToXml rather than
// just encoding wrong, so the conversion has to happen here, against the
// schema, not left to QVariant's own looser coercion. Optional unwraps to
// its inner type; an invalid/null QVariant always yields a null WireValue
// regardless of `type` (valueToXml already writes <nil/> for that). Only
// the scalar kinds real command params use today (bool/int32/float64/
// string/enum/datetime) are supported - array/struct/any/void return a
// null WireValue, same "no real command needs one today" reasoning as
// Encode.cpp's own struct/any/void throw.
WireValue fromQVariant(const QVariant &value, const WireType &type);

}
