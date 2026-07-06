#pragma once

#include "../codec/InterfaceSchema.h"

#include <QMap>
#include <QString>
#include <QXmppClientExtension.h>
#include <QXmppPubSubEventHandler.h>

namespace comm {

class EventLogModel;

// Subscribes to every event a module's disco#info advertised
// (urn:pyobs:event:{name}:{version}), hosted on the module's own bare JID
// via PEP (XEP-0163) - NOT the separate pubsub service state uses (Phase
// 4's StateSubscriptionManager); this distinction bit pyobs-web-client
// once, see DEVELOPMENT.md Phase 6.
//
// No ref-counting like StateSubscriptionManager: there's exactly one
// central event log for the whole app, not per-widget subscriptions, and
// subscribeToEvents() is un-deduped on purpose - matches useXmpp.ts's own
// fetchModuleInfo-triggered subscribe, which re-subscribes every time
// fetchModuleInfo resolves for a module (harmless: subscribing twice to
// the same node from the same JID is a no-op server-side).
//
// Registered as a QXmppClientExtension (via
// QXmppClient::addNewExtension<EventManager>(log), which the client owns/
// deletes) purely so QXmppPubSubManager's incoming-event dispatch finds it,
// same pattern as StateSubscriptionManager.
class EventManager : public QXmppClientExtension, public QXmppPubSubEventHandler
{
    Q_OBJECT

public:
    explicit EventManager(EventLogModel *log);

    void subscribeToEvents(const QString &bareJid, const QMap<QString, codec::EventSchema> &eventSchemas);

    /// \cond
    bool handlePubSubEvent(const QDomElement &element, const QString &pubSubService, const QString &nodeName) override;
    /// \endcond

private:
    EventLogModel *m_log;
};

}
