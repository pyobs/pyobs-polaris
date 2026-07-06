#pragma once

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

}
