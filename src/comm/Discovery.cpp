#include "Discovery.h"

#include "../codec/Decode.h"
#include "../codec/SchemaParse.h"

#include <QDebug>
#include <QDomElement>
#include <QStringList>
#include <QXmlStreamWriter>
#include <QXmppClient.h>
#include <QXmppIq.h>
#include <QXmppTask.h>

namespace comm {

namespace {

constexpr auto kDiscoInfoNs = "http://jabber.org/protocol/disco#info";

class DiscoInfoRequestIq : public QXmppIq
{
public:
    DiscoInfoRequestIq()
        : QXmppIq(QXmppIq::Get)
    {
    }

protected:
    void toXmlElementFromChild(QXmlStreamWriter *writer) const override
    {
        writer->writeStartElement(QStringLiteral("query"));
        writer->writeAttribute(QStringLiteral("xmlns"), QString::fromLatin1(kDiscoInfoNs));
        writer->writeEndElement();
    }
};

QDomElement firstChildByLocalTag(const QDomElement &parent, const QString &tag)
{
    for (QDomElement child = parent.firstChildElement(); !child.isNull(); child = child.nextSiblingElement()) {
        if (codec::localTag(child) == tag) {
            return child;
        }
    }
    return {};
}

ModuleInfo moduleInfoFromJid(const QString &bareJid, const QString &fullJid)
{
    ModuleInfo info;
    info.jid = bareJid;
    info.fullJid = fullJid;
    info.name = bareJid;
    return info;
}

// result.xml is the <iq> - the <query> is its child, everything pyobs adds
// (interface/event/capabilities) are grandchildren, exactly as in
// useXmpp.ts and pyobs-core's own _get_capabilities() (see serializer.py).
ModuleInfo parseDiscoInfoResponse(const QDomElement &iqElement, const QString &bareJid, const QString &fullJid)
{
    ModuleInfo info = moduleInfoFromJid(bareJid, fullJid);

    const QDomElement query = firstChildByLocalTag(iqElement, QStringLiteral("query"));
    if (query.isNull()) {
        return info;
    }

    for (QDomElement identity = query.firstChildElement(QStringLiteral("identity")); !identity.isNull();
         identity = identity.nextSiblingElement(QStringLiteral("identity"))) {
        const QString identityName = identity.attribute(QStringLiteral("name"));
        if (!identityName.isEmpty()) {
            info.name = identityName;
            break;
        }
    }

    for (QDomElement child = query.firstChildElement(); !child.isNull(); child = child.nextSiblingElement()) {
        const QString tag = codec::localTag(child);
        const QString ns = child.namespaceURI();
        if (tag == QLatin1String("interface") && ns.startsWith(QLatin1String("urn:pyobs:interface:"))) {
            const codec::InterfaceSchema schema = codec::parseInterfaceSchema(child);
            info.interfaces.insert(schema.name, schema);
        } else if (tag == QLatin1String("event") && ns.startsWith(QLatin1String("urn:pyobs:event:"))) {
            const codec::EventSchema schema = codec::parseEventSchema(child);
            info.events.insert(schema.name, schema);
        } else if (tag == QLatin1String("capabilities") && ns.startsWith(QLatin1String("urn:pyobs:capabilities:"))) {
            if (const auto ref = codec::parseVersionedFeature(codec::FeatureKind::Capabilities, ns)) {
                info.capabilities.insert(ref->name, codec::xmlToValue(child));
            }
        }
    }

    return info;
}

QString wireTypeToString(const codec::WireType &type)
{
    using Kind = codec::WireType::Kind;
    switch (type.kind()) {
    case Kind::Bool:
        return QStringLiteral("bool");
    case Kind::Int32:
        return QStringLiteral("int32");
    case Kind::Float64:
        return QStringLiteral("float64");
    case Kind::String:
        return QStringLiteral("string");
    case Kind::Void:
        return QStringLiteral("void");
    case Kind::DateTime:
        return QStringLiteral("datetime");
    case Kind::Any:
        return QStringLiteral("any");
    case Kind::Enum:
        return QStringLiteral("enum(%1)").arg(type.name());
    case Kind::Struct:
        return QStringLiteral("struct<%1>").arg(type.name());
    case Kind::Array:
        return QStringLiteral("array<%1>").arg(wireTypeToString(type.item()));
    case Kind::Optional:
        return QStringLiteral("optional<%1>").arg(wireTypeToString(type.inner()));
    }
    Q_UNREACHABLE();
}

QString fieldListToString(const QVector<codec::FieldSchema> &fields)
{
    QStringList parts;
    for (const codec::FieldSchema &f : fields) {
        parts << QStringLiteral("%1: %2%3").arg(f.name, wireTypeToString(f.type),
                                                  f.unit.isEmpty() ? QString() : QStringLiteral(" [%1]").arg(f.unit));
    }
    return parts.join(QStringLiteral(", "));
}

void logEnums(const QMap<QString, QVector<QString>> &enums)
{
    for (auto it = enums.constBegin(); it != enums.constEnd(); ++it) {
        QStringList values;
        for (const QString &v : it.value()) {
            values << v;
        }
        qInfo().noquote() << "    enum" << it.key() << "{" << values.join(QStringLiteral(", ")) << "}";
    }
}

}

void fetchModuleInfo(QXmppClient &client, const QString &bareJid, const QString &fullJid,
                     std::function<void(ModuleInfo)> callback)
{
    DiscoInfoRequestIq iq;
    iq.setTo(fullJid);

    client.sendIq(std::move(iq))
        .then(&client, [bareJid, fullJid, callback = std::move(callback)](QXmppClient::IqResult &&result) {
            if (const auto *element = std::get_if<QDomElement>(&result)) {
                callback(parseDiscoInfoResponse(*element, bareJid, fullJid));
            } else {
                // XMPP error or malformed reply - use defaults derived from
                // the JID, matching useXmpp.ts's fetchModuleInfo catch{}.
                callback(moduleInfoFromJid(bareJid, fullJid));
            }
        });
}

void logModuleInfo(const ModuleInfo &info)
{
    qInfo().noquote() << "module" << info.name << "(" << info.fullJid << ")";

    for (auto it = info.interfaces.constBegin(); it != info.interfaces.constEnd(); ++it) {
        const codec::InterfaceSchema &schema = it.value();
        qInfo().noquote() << "  interface" << schema.name << "v" << schema.version;
        logEnums(schema.enums);
        for (auto cmdIt = schema.commands.constBegin(); cmdIt != schema.commands.constEnd(); ++cmdIt) {
            qInfo().noquote() << "    command" << cmdIt.key() << "(" << fieldListToString(cmdIt.value().params)
                               << ")";
        }
        if (schema.state) {
            qInfo().noquote() << "    state" << schema.state->node << "{" << fieldListToString(schema.state->fields)
                               << "}";
        }
    }

    for (auto it = info.events.constBegin(); it != info.events.constEnd(); ++it) {
        qInfo().noquote() << "  event" << it.key() << "v" << it.value().version << "{"
                           << fieldListToString(it.value().fields) << "}";
        logEnums(it.value().enums);
    }

    for (auto it = info.capabilities.constBegin(); it != info.capabilities.constEnd(); ++it) {
        qInfo().noquote() << "  capabilities" << it.key();
    }
}

}
