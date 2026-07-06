#pragma once

#include <QString>
#include <memory>

namespace codec {

// Mirrors pyobs-codec.ts's WireType. `enum`/`struct` carry a name, `array`/
// `optional` wrap one nested WireType - held via shared_ptr so WireType
// itself stays cheaply copyable (these are immutable, parsed-once schema
// descriptions, so sharing the nested data is fine).
class WireType
{
public:
    enum class Kind { Bool, Int32, Float64, String, Void, DateTime, Any, Enum, Struct, Array, Optional };

    // Defaults to Any, matching parseWireType's fallback for anything
    // unrecognized.
    WireType()
        : m_kind(Kind::Any)
    {
    }

    static WireType boolType() { return WireType(Kind::Bool); }
    static WireType int32Type() { return WireType(Kind::Int32); }
    static WireType float64Type() { return WireType(Kind::Float64); }
    static WireType stringType() { return WireType(Kind::String); }
    static WireType voidType() { return WireType(Kind::Void); }
    static WireType dateTimeType() { return WireType(Kind::DateTime); }
    static WireType anyType() { return WireType(Kind::Any); }

    static WireType enumType(QString name)
    {
        WireType t(Kind::Enum);
        t.m_name = std::move(name);
        return t;
    }
    static WireType structType(QString name)
    {
        WireType t(Kind::Struct);
        t.m_name = std::move(name);
        return t;
    }
    static WireType arrayType(WireType item)
    {
        WireType t(Kind::Array);
        t.m_nested = std::make_shared<WireType>(std::move(item));
        return t;
    }
    static WireType optionalType(WireType inner)
    {
        WireType t(Kind::Optional);
        t.m_nested = std::make_shared<WireType>(std::move(inner));
        return t;
    }

    Kind kind() const { return m_kind; }
    const QString &name() const { return m_name; } // Enum / Struct
    const WireType &item() const { return *m_nested; } // Array
    const WireType &inner() const { return *m_nested; } // Optional

    bool operator==(const WireType &other) const
    {
        if (m_kind != other.m_kind) {
            return false;
        }
        switch (m_kind) {
        case Kind::Enum:
        case Kind::Struct:
            return m_name == other.m_name;
        case Kind::Array:
        case Kind::Optional:
            return *m_nested == *other.m_nested;
        default:
            return true;
        }
    }

private:
    explicit WireType(Kind kind)
        : m_kind(kind)
    {
    }

    Kind m_kind;
    QString m_name;
    std::shared_ptr<WireType> m_nested;
};

// Ports pyobs-codec.ts's parseWireType: maps a disco#info type string
// (`bool`, `int32`, `enum(Name)`, `array<T>`, ...) to a WireType. Falls back
// to WireType::anyType() for anything unrecognized, same as the TS port.
WireType parseWireType(const QString &typeStr);

}
