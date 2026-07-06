#include "VariantBridge.h"

#include <QVariantList>
#include <QVariantMap>

namespace codec {

QVariant toQVariant(const WireValue &value)
{
    if (value.isNull()) {
        return {};
    }
    if (value.isBool()) {
        return value.toBool();
    }
    if (value.isInt()) {
        return static_cast<qlonglong>(value.toInt());
    }
    if (value.isDouble()) {
        return value.toDouble();
    }
    if (value.isString()) {
        return value.toString();
    }
    if (value.isList()) {
        QVariantList list;
        for (const WireValue &item : value.toList()) {
            list.push_back(toQVariant(item));
        }
        return list;
    }
    if (value.isDict()) {
        QVariantList entries;
        for (const auto &[key, val] : value.toDict()) {
            QVariantMap entry;
            entry.insert(QStringLiteral("key"), key);
            entry.insert(QStringLiteral("value"), toQVariant(val));
            entries.push_back(entry);
        }
        return entries;
    }
    Q_UNREACHABLE();
}

}
