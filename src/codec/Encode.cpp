#include "Encode.h"

#include <QXmlStreamWriter>
#include <stdexcept>

namespace codec {

void valueToXml(QXmlStreamWriter &writer, const WireValue &value, const WireType &type)
{
    using Kind = WireType::Kind;

    if (type.kind() == Kind::Optional) {
        if (value.isNull()) {
            writer.writeEmptyElement(QStringLiteral("nil"));
        } else {
            valueToXml(writer, value, type.inner());
        }
        return;
    }

    if (value.isNull()) {
        writer.writeEmptyElement(QStringLiteral("nil"));
        return;
    }

    switch (type.kind()) {
    case Kind::Bool:
        writer.writeTextElement(QStringLiteral("boolean"), value.toBool() ? QStringLiteral("true") : QStringLiteral("false"));
        return;
    case Kind::Int32:
        writer.writeTextElement(QStringLiteral("int"), QString::number(value.toInt()));
        return;
    case Kind::Float64:
        writer.writeTextElement(QStringLiteral("double"), QString::number(value.toDouble(), 'g', 17));
        return;
    case Kind::String:
    case Kind::DateTime:
    case Kind::Enum:
        writer.writeTextElement(QStringLiteral("string"), value.isString() ? value.toString() : QString());
        return;
    case Kind::Array: {
        writer.writeStartElement(QStringLiteral("items"));
        for (const WireValue &item : value.toList()) {
            writer.writeStartElement(QStringLiteral("item"));
            valueToXml(writer, item, type.item());
            writer.writeEndElement();
        }
        writer.writeEndElement();
        return;
    }
    case Kind::Struct:
    case Kind::Any:
    case Kind::Void:
    case Kind::Optional:
        break;
    }

    // struct<Name>/any/void params can't be built from schema alone
    // (pyobs-core doesn't publish struct field lists) - no real command
    // takes one today, matches the TS port's behavior.
    throw std::runtime_error("Cannot encode a value for this wire type");
}

}
