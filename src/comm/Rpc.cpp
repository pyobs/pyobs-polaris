#include "Rpc.h"

#include "../codec/Decode.h"
#include "../codec/Encode.h"

#include <QDomElement>
#include <QXmlStreamWriter>
#include <QXmppClient.h>
#include <QXmppIq.h>
#include <QXmppTask.h>
#include <algorithm>

namespace comm {

namespace {

constexpr auto kRpcNs = "jabber:iq:rpc";
constexpr auto kPyobsRpcNs = "urn:pyobs:rpc:1";

class RpcCallIq : public QXmppIq
{
public:
    RpcCallIq(QString methodName, QVector<codec::WireValue> params, QVector<codec::FieldSchema> paramSchemas)
        : QXmppIq(QXmppIq::Set)
        , m_methodName(std::move(methodName))
        , m_params(std::move(params))
        , m_paramSchemas(std::move(paramSchemas))
    {
    }

protected:
    void toXmlElementFromChild(QXmlStreamWriter *writer) const override
    {
        writer->writeStartElement(QStringLiteral("query"));
        writer->writeAttribute(QStringLiteral("xmlns"), QString::fromLatin1(kRpcNs));
        writer->writeStartElement(QStringLiteral("methodCall"));
        writer->writeTextElement(QStringLiteral("methodName"), m_methodName);
        writer->writeStartElement(QStringLiteral("params"));

        const int count = std::min(m_params.size(), m_paramSchemas.size());
        for (int i = 0; i < count; ++i) {
            writer->writeStartElement(QStringLiteral("param"));
            writer->writeStartElement(QStringLiteral("value"));
            writer->writeStartElement(QStringLiteral("value"));
            writer->writeAttribute(QStringLiteral("xmlns"), QString::fromLatin1(kPyobsRpcNs));
            codec::valueToXml(*writer, m_params[i], m_paramSchemas[i].type);
            writer->writeEndElement(); // inner (pyobs-namespaced) value
            writer->writeEndElement(); // outer value
            writer->writeEndElement(); // param
        }

        writer->writeEndElement(); // params
        writer->writeEndElement(); // methodCall
        writer->writeEndElement(); // query
    }

private:
    QString m_methodName;
    QVector<codec::WireValue> m_params;
    QVector<codec::FieldSchema> m_paramSchemas;
};

// Pre-order depth-first search for the first descendant (any depth)
// matching `tag` by local name - mirrors JS's getElementsByTagName()[0]
// (document-order, namespace-oblivious) closely enough for the single-
// match case every real RPC response is.
QDomElement findDescendantByLocalTag(const QDomElement &root, const QString &tag)
{
    for (QDomElement child = root.firstChildElement(); !child.isNull(); child = child.nextSiblingElement()) {
        if (codec::localTag(child) == tag) {
            return child;
        }
        const QDomElement nested = findDescendantByLocalTag(child, tag);
        if (!nested.isNull()) {
            return nested;
        }
    }
    return {};
}

QDomElement firstChildByLocalTag(const QDomElement &parent, const QString &tag)
{
    for (QDomElement child = parent.firstChildElement(); !child.isNull(); child = child.nextSiblingElement()) {
        if (codec::localTag(child) == tag) {
            return child;
        }
    }
    return {};
}

// Ports useXmpp.ts's findRpcFault: returns nullopt if there's no <fault> in
// the response at all (a plain success).
std::optional<RpcResult> findRpcFault(const QDomElement &iqElement)
{
    const QDomElement outerFault = findDescendantByLocalTag(iqElement, QStringLiteral("fault"));
    if (outerFault.isNull()) {
        return std::nullopt;
    }

    const QDomElement outerValue = firstChildByLocalTag(outerFault, QStringLiteral("value"));
    const QDomElement innerFault = outerValue.isNull() ? QDomElement() : firstChildByLocalTag(outerValue, QStringLiteral("fault"));
    const QDomElement exceptionEl = innerFault.isNull() ? QDomElement() : firstChildByLocalTag(innerFault, QStringLiteral("exception"));
    const QDomElement messageEl = innerFault.isNull() ? QDomElement() : firstChildByLocalTag(innerFault, QStringLiteral("message"));

    RpcResult result;
    result.success = false;
    result.errorClass = exceptionEl.isNull() ? QStringLiteral("RemoteError") : exceptionEl.text();
    result.errorMessage = messageEl.isNull() ? QString() : messageEl.text();
    return result;
}

// Ports useXmpp.ts's parseRpcReturn.
codec::WireValue parseReturn(const QDomElement &iqElement)
{
    const QDomElement paramsEl = findDescendantByLocalTag(iqElement, QStringLiteral("params"));
    if (paramsEl.isNull()) {
        return {};
    }
    const QDomElement paramEl = paramsEl.firstChildElement(); // void return: empty <params/>
    if (paramEl.isNull()) {
        return {};
    }
    const QDomElement outerValueEl = firstChildByLocalTag(paramEl, QStringLiteral("value"));
    if (outerValueEl.isNull()) {
        return {};
    }

    QDomElement innerValueEl;
    for (QDomElement c = outerValueEl.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) {
        if (codec::localTag(c) == QLatin1String("value") && c.namespaceURI() == QLatin1String(kPyobsRpcNs)) {
            innerValueEl = c;
            break;
        }
    }
    if (innerValueEl.isNull()) {
        return {};
    }

    const QDomElement contentEl = innerValueEl.firstChildElement();
    return contentEl.isNull() ? codec::WireValue() : codec::xmlToValue(contentEl);
}

}

void executeMethod(QXmppClient &client, const QString &fullJid, const QString &methodName,
                   const QVector<codec::WireValue> &params, const QVector<codec::FieldSchema> &paramSchemas,
                   std::function<void(RpcResult)> callback)
{
    RpcCallIq iq(methodName, params, paramSchemas);
    iq.setTo(fullJid);

    client.sendIq(std::move(iq)).then(&client, [callback = std::move(callback)](QXmppClient::IqResult &&result) {
        if (const auto *element = std::get_if<QDomElement>(&result)) {
            if (const auto fault = findRpcFault(*element)) {
                callback(*fault);
                return;
            }
            RpcResult r;
            r.success = true;
            r.value = parseReturn(*element);
            callback(r);
        } else {
            // XMPP-level error (item-not-found, forbidden, timeout, ...) -
            // not a real remote fault, so errorClass stays empty.
            const QXmppError &error = std::get<QXmppError>(result);
            RpcResult r;
            r.success = false;
            r.errorMessage = error.description;
            callback(r);
        }
    });
}

}
