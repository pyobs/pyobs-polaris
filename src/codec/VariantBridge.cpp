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

WireValue fromQVariant(const QVariant &value, const WireType &type)
{
    using Kind = WireType::Kind;

    if (!value.isValid() || value.isNull()) {
        return {};
    }

    const Kind kind = type.kind() == Kind::Optional ? type.inner().kind() : type.kind();
    switch (kind) {
    case Kind::Bool:
        return WireValue(value.toBool());
    case Kind::Int32:
        return WireValue(static_cast<qint64>(value.toLongLong()));
    case Kind::Float64:
        return WireValue(value.toDouble());
    case Kind::String:
    case Kind::Enum:
    case Kind::DateTime:
        return WireValue(value.toString());
    case Kind::Void:
    case Kind::Any:
    case Kind::Struct:
    case Kind::Array:
    case Kind::Optional:
        return {};
    }
    Q_UNREACHABLE();
}

}
