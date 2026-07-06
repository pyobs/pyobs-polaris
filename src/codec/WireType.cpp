#include "WireType.h"

#include <QRegularExpression>

namespace codec {

WireType parseWireType(const QString &typeStr)
{
    const QString s = typeStr.trimmed();

    if (s == QLatin1String("bool")) {
        return WireType::boolType();
    }
    if (s == QLatin1String("int32")) {
        return WireType::int32Type();
    }
    if (s == QLatin1String("float64")) {
        return WireType::float64Type();
    }
    if (s == QLatin1String("string")) {
        return WireType::stringType();
    }
    if (s == QLatin1String("void")) {
        return WireType::voidType();
    }
    if (s == QLatin1String("datetime")) {
        return WireType::dateTimeType();
    }

    static const QRegularExpression enumRe(QStringLiteral("^enum\\((.+)\\)$"));
    if (const auto m = enumRe.match(s); m.hasMatch()) {
        return WireType::enumType(m.captured(1));
    }
    static const QRegularExpression structRe(QStringLiteral("^struct<(.+)>$"));
    if (const auto m = structRe.match(s); m.hasMatch()) {
        return WireType::structType(m.captured(1));
    }
    static const QRegularExpression arrayRe(QStringLiteral("^array<(.+)>$"));
    if (const auto m = arrayRe.match(s); m.hasMatch()) {
        return WireType::arrayType(parseWireType(m.captured(1)));
    }
    static const QRegularExpression optionalRe(QStringLiteral("^optional<(.+)>$"));
    if (const auto m = optionalRe.match(s); m.hasMatch()) {
        return WireType::optionalType(parseWireType(m.captured(1)));
    }

    return WireType::anyType();
}

}
