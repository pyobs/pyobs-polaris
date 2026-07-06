#pragma once

#include <QString>
#include <QtGlobal>
#include <utility>
#include <variant>
#include <vector>

namespace codec {

class WireValue;

// dict and dataclass-root both decode to an ordered name/value list rather
// than a QVariantMap: QVariantMap is a QMap, which sorts by key, but
// pyobs-web-client's KeyValueCard.vue relies on Object.entries() preserving
// JS object insertion order (i.e. wire/declaration order) when it renders
// state fields. std::variant (not QVariant) is the WireValue backing store
// specifically so this ordered container is available as a plain variant
// alternative - QVariant has no order-preserving string-keyed container
// built in.
using WireList = std::vector<WireValue>;
using WireDict = std::vector<std::pair<QString, WireValue>>;

// Schema-less decoded value from pyobs-core's wire protocol - mirrors the
// TS `unknown` return of pyobs-codec.ts's xmlToValue. See DEVELOPMENT.md
// Phase 1.5.
class WireValue
{
public:
    WireValue()
        : m_data(std::monostate {})
    {
    }
    WireValue(bool value)
        : m_data(value)
    {
    }
    WireValue(qint64 value)
        : m_data(value)
    {
    }
    WireValue(double value)
        : m_data(value)
    {
    }
    WireValue(QString value)
        : m_data(std::move(value))
    {
    }
    WireValue(WireList value)
        : m_data(std::move(value))
    {
    }
    WireValue(WireDict value)
        : m_data(std::move(value))
    {
    }

    bool isNull() const { return std::holds_alternative<std::monostate>(m_data); }
    bool isBool() const { return std::holds_alternative<bool>(m_data); }
    bool isInt() const { return std::holds_alternative<qint64>(m_data); }
    bool isDouble() const { return std::holds_alternative<double>(m_data); }
    bool isString() const { return std::holds_alternative<QString>(m_data); }
    bool isList() const { return std::holds_alternative<WireList>(m_data); }
    bool isDict() const { return std::holds_alternative<WireDict>(m_data); }

    bool toBool() const { return std::get<bool>(m_data); }
    qint64 toInt() const { return std::get<qint64>(m_data); }
    double toDouble() const { return std::get<double>(m_data); }
    const QString &toString() const { return std::get<QString>(m_data); }
    const WireList &toList() const { return std::get<WireList>(m_data); }
    const WireDict &toDict() const { return std::get<WireDict>(m_data); }

    bool operator==(const WireValue &other) const = default;

private:
    std::variant<std::monostate, bool, qint64, double, QString, WireList, WireDict> m_data;
};

}
