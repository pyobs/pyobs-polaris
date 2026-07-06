#include "Decode.h"

#include <QDomElement>

namespace codec {

QString localTag(const QDomElement &element)
{
    const QString tag = element.tagName();
    const int idx = tag.indexOf(QLatin1Char(':'));
    return idx >= 0 ? tag.mid(idx + 1) : tag;
}

namespace {

// Firstborn element child carrying the actual self-tagged value, or a null
// WireValue if there isn't one - mirrors the TS port's repeated
// `c.firstElementChild ? xmlToValue(c.firstElementChild) : null` idiom.
WireValue decodeFirstChild(const QDomElement &parent)
{
    const QDomElement child = parent.firstChildElement();
    return child.isNull() ? WireValue() : xmlToValue(child);
}

}

WireValue xmlToValue(const QDomElement &element)
{
    const QString tag = localTag(element);

    if (tag == QLatin1String("nil")) {
        return WireValue();
    }
    if (tag == QLatin1String("boolean")) {
        return WireValue(element.text() == QLatin1String("true"));
    }
    if (tag == QLatin1String("int")) {
        // Qt's toLongLong() requires the whole string to be a valid
        // integer (returns 0 otherwise), unlike JS's lenient prefix-parsing
        // parseInt() - stricter is the right call here since pyobs-core
        // only ever emits well-formed integer text; silently accepting
        // garbage would just hide a real bug in the sender.
        return WireValue(static_cast<qint64>(element.text().toLongLong()));
    }
    if (tag == QLatin1String("double")) {
        return WireValue(element.text().toDouble());
    }
    if (tag == QLatin1String("string")) {
        return WireValue(element.text());
    }
    if (tag == QLatin1String("items") || tag == QLatin1String("tuple")) {
        WireList list;
        for (QDomElement item = element.firstChildElement(); !item.isNull(); item = item.nextSiblingElement()) {
            if (localTag(item) != QLatin1String("item")) {
                continue;
            }
            list.push_back(decodeFirstChild(item));
        }
        return WireValue(std::move(list));
    }
    if (tag == QLatin1String("dict")) {
        WireDict dict;
        for (QDomElement entry = element.firstChildElement(); !entry.isNull(); entry = entry.nextSiblingElement()) {
            if (localTag(entry) != QLatin1String("entry")) {
                continue;
            }
            QDomElement keyEl;
            QDomElement valEl;
            for (QDomElement c = entry.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) {
                const QString childTag = localTag(c);
                if (childTag == QLatin1String("key")) {
                    keyEl = c;
                } else if (childTag == QLatin1String("val")) {
                    valEl = c;
                }
            }
            if (keyEl.isNull()) {
                continue; // no key -> skip, mirrors `if (key !== undefined)`
            }
            const WireValue key = decodeFirstChild(keyEl);
            // Dict keys are always plain strings on the real pyobs wire;
            // unlike the TS port's `String(key)` this doesn't handle a
            // non-string key coercing to a display string, since that path
            // never fires in practice and isn't worth the complexity.
            const WireValue val = valEl.isNull() ? WireValue() : decodeFirstChild(valEl);
            dict.emplace_back(key.isString() ? key.toString() : QString(), val);
        }
        return WireValue(std::move(dict));
    }

    // Anything else is a dataclass root (state/capabilities): one child
    // element per field, each wrapping exactly one more self-tagged value.
    WireDict fields;
    for (QDomElement field = element.firstChildElement(); !field.isNull(); field = field.nextSiblingElement()) {
        fields.emplace_back(localTag(field), decodeFirstChild(field));
    }
    return WireValue(std::move(fields));
}

}
