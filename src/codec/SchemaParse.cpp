#include "SchemaParse.h"

#include "Decode.h"

#include <QDomElement>

namespace codec {

namespace {

QString featureKindString(FeatureKind kind)
{
    switch (kind) {
    case FeatureKind::Interface:
        return QStringLiteral("interface");
    case FeatureKind::State:
        return QStringLiteral("state");
    case FeatureKind::Event:
        return QStringLiteral("event");
    case FeatureKind::Capabilities:
        return QStringLiteral("capabilities");
    }
    Q_UNREACHABLE();
}

QMap<QString, QVector<QString>> parseEnums(const QDomElement &typesEl)
{
    QMap<QString, QVector<QString>> enums;
    for (QDomElement enumEl = typesEl.firstChildElement(); !enumEl.isNull(); enumEl = enumEl.nextSiblingElement()) {
        if (localTag(enumEl) != QLatin1String("enum")) {
            continue;
        }
        const QString name = enumEl.attribute(QStringLiteral("name"));
        QVector<QString> values;
        for (QDomElement v = enumEl.firstChildElement(); !v.isNull(); v = v.nextSiblingElement()) {
            if (localTag(v) != QLatin1String("value")) {
                continue;
            }
            values.push_back(v.text());
        }
        enums.insert(name, values);
    }
    return enums;
}

QVector<FieldSchema> parseFields(const QDomElement &parent, const QString &childTag)
{
    QVector<FieldSchema> fields;
    for (QDomElement f = parent.firstChildElement(); !f.isNull(); f = f.nextSiblingElement()) {
        if (localTag(f) != childTag) {
            continue;
        }
        FieldSchema field;
        field.name = f.attribute(QStringLiteral("name"));
        field.type = parseWireType(f.hasAttribute(QStringLiteral("type")) ? f.attribute(QStringLiteral("type"))
                                                                           : QStringLiteral("any"));
        field.unit = f.attribute(QStringLiteral("unit"));
        fields.push_back(field);
    }
    return fields;
}

}

std::optional<VersionedFeature> parseVersionedFeature(FeatureKind kind, const QString &feat)
{
    const QString prefix = QStringLiteral("urn:pyobs:%1:").arg(featureKindString(kind));
    if (!feat.startsWith(prefix)) {
        return std::nullopt;
    }
    const QString rest = feat.mid(prefix.size());
    const int idx = rest.lastIndexOf(QLatin1Char(':'));
    if (idx < 0) {
        return std::nullopt;
    }
    bool ok = false;
    const int version = rest.mid(idx + 1).toInt(&ok);
    if (!ok) {
        return std::nullopt;
    }
    return VersionedFeature { rest.left(idx), version };
}

InterfaceSchema parseInterfaceSchema(const QDomElement &element)
{
    const auto ref = parseVersionedFeature(FeatureKind::Interface, element.namespaceURI());

    InterfaceSchema schema;
    schema.name = ref ? ref->name : element.attribute(QStringLiteral("name"));
    schema.version = ref ? ref->version : 1;

    for (QDomElement child = element.firstChildElement(); !child.isNull(); child = child.nextSiblingElement()) {
        const QString tag = localTag(child);
        if (tag == QLatin1String("types")) {
            schema.enums = parseEnums(child);
        } else if (tag == QLatin1String("command")) {
            CommandSchema cmd;
            cmd.name = child.attribute(QStringLiteral("name"));
            cmd.params = parseFields(child, QStringLiteral("parameter"));
            schema.commands.insert(cmd.name, cmd);
        } else if (tag == QLatin1String("state")) {
            StateSchema state;
            state.node = child.attribute(QStringLiteral("node"));
            state.fields = parseFields(child, QStringLiteral("field"));
            schema.state = state;
        }
    }

    return schema;
}

EventSchema parseEventSchema(const QDomElement &element)
{
    const auto ref = parseVersionedFeature(FeatureKind::Event, element.namespaceURI());

    EventSchema schema;
    schema.name = ref ? ref->name : element.attribute(QStringLiteral("name"));
    schema.version = ref ? ref->version : 1;

    const QDomElement typesEl = [&] {
        for (QDomElement child = element.firstChildElement(); !child.isNull(); child = child.nextSiblingElement()) {
            if (localTag(child) == QLatin1String("types")) {
                return child;
            }
        }
        return QDomElement();
    }();
    if (!typesEl.isNull()) {
        schema.enums = parseEnums(typesEl);
    }

    schema.fields = parseFields(element, QStringLiteral("field"));

    return schema;
}

}
