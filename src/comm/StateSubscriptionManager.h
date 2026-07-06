#pragma once

#include "../codec/WireValue.h"

#include <QMap>
#include <QString>
#include <QVector>
#include <QXmppClientExtension.h>
#include <QXmppPubSubEventHandler.h>

namespace comm {

class StateSubscription;

// Owns every ref-counted PubSub state subscription for one XmppClient -
// mirrors useXmpp.ts's subscribeState()/stateStore/stateRefCounts/
// stateSubscribing: same node naming
// (pyobs:state:{module}:{Interface}:{version}), same ref-count semantics
// (only actually unsubscribe from the server once the last watcher goes
// away), same retry-with-backoff-then-fetch-current-value dance. See
// DEVELOPMENT.md Phase 4.
//
// Registered as a QXmppClientExtension (via
// QXmppClient::addNewExtension<StateSubscriptionManager>(), which the
// client owns/deletes like any other extension) purely so
// QXmppPubSubManager's incoming-event dispatch - which iterates
// client()->extensions() looking for QXmppPubSubEventHandler - finds it.
class StateSubscriptionManager : public QXmppClientExtension, public QXmppPubSubEventHandler
{
    Q_OBJECT

public:
    // Subscribes (ref-counted) to bareJid's interfaceName state. The
    // returned StateSubscription is parented to `parent` on top of its own
    // ref-counted lifetime management - destroying it (or calling
    // unsubscribe() explicitly) releases the ref.
    StateSubscription *subscribe(const QString &bareJid, const QString &interfaceName, int version, QObject *parent);

    // Called by StateSubscription's destructor/unsubscribe(). Not meant to
    // be called from anywhere else.
    void release(const QString &node, StateSubscription *watcher);

    /// \cond
    bool handlePubSubEvent(const QDomElement &element, const QString &pubSubService, const QString &nodeName) override;
    /// \endcond

private:
    struct Entry {
        int refCount = 0;
        bool subscribing = false;
        QString pubsubService;
        codec::WireValue value;
        QVector<StateSubscription *> watchers;
    };

    void subscribeWithRetry(const QString &pubsubService, const QString &subscriberJid, const QString &node,
                             int attemptsLeft);
    void fetchCurrentValue(const QString &pubsubService, const QString &node);
    void dispatchValue(const QString &node, codec::WireValue value);

    QMap<QString, Entry> m_entries;

    // Matches STATE_SUBSCRIBE_RETRIES / STATE_SUBSCRIBE_RETRY_WAIT_MS in
    // useXmpp.ts - the publisher's node may not exist yet at subscribe time.
    static constexpr int kSubscribeRetries = 30;
    static constexpr int kSubscribeRetryWaitMs = 1000;
};

}
