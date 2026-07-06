#include "EventManager.h"

#include "EventLogModel.h"

#include "../codec/Decode.h"

#include <QDateTime>
#include <QDomElement>
#include <QJsonDocument>
#include <QJsonObject>
#include <QXmppClient.h>
#include <QXmppPubSubManager.h>
#include <QXmppUtils.h>

namespace comm {

namespace {

QDomElement firstChildByLocalTag(const QDomElement &parent, const QString &tag)
{
    for (QDomElement child = parent.firstChildElement(); !child.isNull(); child = child.nextSiblingElement()) {
        if (codec::localTag(child) == tag) {
            return child;
        }
    }
    return {};
}

}

EventManager::EventManager(EventLogModel *log)
    : m_log(log)
{
}

void EventManager::subscribeToEvents(const QString &bareJid, const QMap<QString, codec::EventSchema> &eventSchemas)
{
    auto *pubsub = client()->findExtension<QXmppPubSubManager>();
    if (!pubsub) {
        return;
    }
    const QString myBareJid = client()->configuration().jidBare();
    for (auto it = eventSchemas.constBegin(); it != eventSchemas.constEnd(); ++it) {
        const QString node = QStringLiteral("urn:pyobs:event:%1:%2").arg(it.value().name).arg(it.value().version);
        // Fire-and-forget, matches useXmpp.ts's subscribe .catch(() => {}).
        pubsub->subscribeToNode(bareJid, node, myBareJid);
    }
}

bool EventManager::handlePubSubEvent(const QDomElement &element, const QString &pubSubService, const QString &nodeName)
{
    Q_UNUSED(pubSubService);

    if (!nodeName.startsWith(QLatin1String("urn:pyobs:event:"))) {
        return false; // not an event node - Phase 4's state uses a different node prefix/service entirely
    }

    const QDomElement eventEl = firstChildByLocalTag(element, QStringLiteral("event"));
    const QDomElement itemsEl = eventEl.isNull() ? QDomElement() : firstChildByLocalTag(eventEl, QStringLiteral("items"));
    const QDomElement itemEl = itemsEl.isNull() ? QDomElement() : firstChildByLocalTag(itemsEl, QStringLiteral("item"));
    const QDomElement payload = itemEl.isNull() ? QDomElement() : itemEl.firstChildElement();
    if (payload.isNull()) {
        return false;
    }

    // The payload is a plain JSON string (Python's Event.to_json()), not
    // the self-tagged WireValue vocabulary state/RPC use - just read its
    // text content directly, no codec::xmlToValue involved.
    const QJsonDocument doc = QJsonDocument::fromJson(payload.text().toUtf8());
    if (!doc.isObject()) {
        return false; // malformed payload - ignore, matches useXmpp.ts's catch{}
    }
    const QJsonObject obj = doc.object();

    const double timestamp = obj.value(QStringLiteral("timestamp")).toDouble();

    // Matches xmppcomm.py's own _handle_event() exactly: discard anything
    // older than 30 seconds - pyobs-core's own documented reason ("avoid
    // resent events after a reconnect") is real, not hypothetical: a fresh
    // subscribe to a PEP node makes ejabberd immediately replay its last
    // published item as a catch-up delivery, confirmed live (see
    // DEVELOPMENT.md) - and that catch-up delivery's `from` is the shared
    // pubsub component's own JID, not the original publisher's, making
    // `module` below unrecoverable for it anyway. A live, freshly-pushed
    // event (arriving after the subscription handshake is done) always
    // carries the correct publisher JID.
    if (QDateTime::currentSecsSinceEpoch() - static_cast<qint64>(timestamp) > 30) {
        return true; // handled (it's a real pyobs event node), just not logged
    }

    PyobsEvent event;
    event.type = obj.value(QStringLiteral("type")).toString(nodeName);
    event.module = QXmppUtils::jidToUser(element.attribute(QStringLiteral("from")));
    event.timestamp = timestamp;
    event.uuid = obj.value(QStringLiteral("uuid")).toString();
    event.data = obj.value(QStringLiteral("data")).toObject();

    m_log->append(event);
    return true;
}

}
