#include "StateSubscriptionManager.h"

#include "StateSubscription.h"

#include "../codec/Decode.h"
#include "../codec/VariantBridge.h"

#include <QDomElement>
#include <QTimer>
#include <QXmppClient.h>
#include <QXmppPubSubManager.h>
#include <QXmppUtils.h>

namespace comm {

namespace {

// Only override parsePayload(): this client never publishes state itself,
// so serializePayload() can stay the (unused) no-op default.
class WireValueItem : public QXmppPubSubBaseItem
{
public:
    codec::WireValue value;

protected:
    void parsePayload(const QDomElement &payloadElement) override { value = codec::xmlToValue(payloadElement); }
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

}

StateSubscription *StateSubscriptionManager::subscribe(const QString &bareJid, const QString &interfaceName,
                                                        int version, QObject *parent)
{
    const QString moduleUsername = QXmppUtils::jidToUser(bareJid);
    const QString node = QStringLiteral("pyobs:state:%1:%2:%3").arg(moduleUsername, interfaceName).arg(version);

    auto it = m_entries.find(node);
    if (it == m_entries.end()) {
        it = m_entries.insert(node, Entry {});
        it->pubsubService = QStringLiteral("pubsub.%1").arg(QXmppUtils::jidToDomain(bareJid));
    }
    Entry &entry = it.value();
    entry.refCount += 1;

    auto *subscription = new StateSubscription(this, node, parent);
    entry.watchers.push_back(subscription);
    if (!entry.value.isNull()) {
        // A prior watcher already has a value for this node - hand it to
        // the new one immediately rather than making it wait for the next
        // server push.
        subscription->notifyValueChanged(codec::toQVariant(entry.value));
    }

    if (!entry.subscribing) {
        entry.subscribing = true;
        subscribeWithRetry(entry.pubsubService, client()->configuration().jidBare(), node, kSubscribeRetries);
    }

    return subscription;
}

void StateSubscriptionManager::release(const QString &node, StateSubscription *watcher)
{
    auto it = m_entries.find(node);
    if (it == m_entries.end()) {
        return;
    }
    it->watchers.removeAll(watcher);
    it->refCount -= 1;
    if (it->refCount <= 0) {
        auto *pubsub = client()->findExtension<QXmppPubSubManager>();
        if (pubsub) {
            // Fire-and-forget, matches useXmpp.ts's unsubscribe .catch(() => {}).
            pubsub->unsubscribeFromNode(it->pubsubService, node, client()->configuration().jidBare());
        }
        m_entries.erase(it);
    }
}

void StateSubscriptionManager::subscribeWithRetry(const QString &pubsubService, const QString &subscriberJid,
                                                   const QString &node, int attemptsLeft)
{
    auto *pubsub = client()->findExtension<QXmppPubSubManager>();
    pubsub->subscribeToNode(pubsubService, node, subscriberJid)
        .then(this, [this, pubsubService, subscriberJid, node, attemptsLeft](QXmppPubSubManager::Result &&result) {
            if (std::holds_alternative<QXmppError>(result) && attemptsLeft > 1) {
                // Publisher's node may not exist yet at subscribe time -
                // wait and retry, matches STATE_SUBSCRIBE_RETRY_WAIT_MS.
                QTimer::singleShot(kSubscribeRetryWaitMs, this, [this, pubsubService, subscriberJid, node, attemptsLeft] {
                    subscribeWithRetry(pubsubService, subscriberJid, node, attemptsLeft - 1);
                });
                return;
            }
            // Either succeeded, or retries exhausted - either way, fetch the
            // current value now to close the race between a live push and
            // the subscribe ack.
            fetchCurrentValue(pubsubService, node);
        });
}

void StateSubscriptionManager::fetchCurrentValue(const QString &pubsubService, const QString &node)
{
    auto *pubsub = client()->findExtension<QXmppPubSubManager>();
    pubsub->requestItems<WireValueItem>(pubsubService, node)
        .then(this, [this, node](QXmppPubSubManager::ItemsResult<WireValueItem> &&result) {
            if (auto *items = std::get_if<QXmppPubSubManager::Items<WireValueItem>>(&result)) {
                if (!items->items.isEmpty()) {
                    dispatchValue(node, items->items.constFirst().value);
                }
            }
            // else: no current value published yet - matches useXmpp.ts's catch{} no-op.
        });
}

void StateSubscriptionManager::dispatchValue(const QString &node, codec::WireValue value)
{
    auto it = m_entries.find(node);
    if (it == m_entries.end()) {
        return; // nobody watching anymore
    }
    it->value = value;
    const QVariant variant = codec::toQVariant(it->value);
    for (StateSubscription *watcher : it->watchers) {
        watcher->notifyValueChanged(variant);
    }
}

bool StateSubscriptionManager::handlePubSubEvent(const QDomElement &element, const QString &pubSubService,
                                                 const QString &nodeName)
{
    Q_UNUSED(pubSubService);

    if (!nodeName.startsWith(QLatin1String("pyobs:state:"))) {
        return false; // not state - Phase 6's events use urn:pyobs:event:*, hosted on PEP not this pubsub path
    }

    const QDomElement eventEl = firstChildByLocalTag(element, QStringLiteral("event"));
    const QDomElement itemsEl = eventEl.isNull() ? QDomElement() : firstChildByLocalTag(eventEl, QStringLiteral("items"));
    const QDomElement itemEl = itemsEl.isNull() ? QDomElement() : firstChildByLocalTag(itemsEl, QStringLiteral("item"));
    const QDomElement payload = itemEl.isNull() ? QDomElement() : itemEl.firstChildElement();
    if (payload.isNull()) {
        return false;
    }

    dispatchValue(nodeName, codec::xmlToValue(payload));
    return true;
}

}
