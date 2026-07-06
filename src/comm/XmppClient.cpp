#include "XmppClient.h"

#include "Discovery.h"
#include "EventManager.h"
#include "Rpc.h"
#include "StateSubscriptionManager.h"

#include "../codec/VariantBridge.h"

#include <QDebug>
#include <QJSEngine>
#include <QJsonDocument>
#include <QQmlEngine>
#include <QXmppConfiguration.h>
#include <QXmppError.h>
#include <QXmppPubSubManager.h>
#include <QXmppRosterManager.h>
#include <QXmppUtils.h>

namespace comm {

namespace {
constexpr auto kPyobsResource = "pyobs";
}

XmppClient::XmppClient(QObject *parent)
    : QObject(parent)
    , m_client(QXmppClient::BasicExtensions, this)
    , m_modules(new ModuleListModel(this))
    , m_events(new EventLogModel(this))
    , m_stateSubscriptions(m_client.addNewExtension<StateSubscriptionManager>())
    , m_eventManager(m_client.addNewExtension<EventManager>(m_events))
{
    // Not part of BasicExtensions - StateSubscriptionManager's
    // subscribeToNode()/unsubscribeFromNode()/requestItems() calls all go
    // through this. Must be added before any subscribeState() call, or
    // client()->findExtension<QXmppPubSubManager>() returns null.
    m_client.addNewExtension<QXmppPubSubManager>();

    connect(&m_client, &QXmppClient::connected, this, [this] {
        setStatus(Status::Connected);
    });

    connect(&m_client, &QXmppClient::disconnected, this, [this] {
        if (!m_hadError) {
            setStatus(Status::Disconnected);
        }
    });

    connect(&m_client, &QXmppClient::errorOccurred, this, [this](const QXmppError &error) {
        setStatus(Status::Error, error.description);
    });

    connect(&m_client, &QXmppClient::presenceReceived, this, &XmppClient::handlePresence);

    // QXmppClient requests the roster automatically right after connected()
    // fires; QXmppRosterManager::rosterReceived() is our cue to probe it -
    // BasicExtensions (passed to m_client's constructor above) already
    // added the roster manager, so it exists by now.
    connect(m_client.findExtension<QXmppRosterManager>(), &QXmppRosterManager::rosterReceived, this,
            &XmppClient::probeRosterPresence);
}

QString XmppClient::status() const
{
    switch (m_status) {
    case Status::Disconnected:
        return QStringLiteral("disconnected");
    case Status::Connecting:
        return QStringLiteral("connecting");
    case Status::Connected:
        return QStringLiteral("connected");
    case Status::Error:
        return QStringLiteral("error");
    }
    Q_UNREACHABLE();
}

QString XmppClient::errorMessage() const
{
    return m_errorMessage;
}

bool XmppClient::insecureSkipTlsVerification() const
{
    return m_insecureSkipTlsVerification;
}

void XmppClient::setInsecureSkipTlsVerification(bool value)
{
    if (m_insecureSkipTlsVerification == value) {
        return;
    }
    m_insecureSkipTlsVerification = value;
    Q_EMIT insecureSkipTlsVerificationChanged();
}

void XmppClient::connectToServer(const QString &jid, const QString &password)
{
    m_hadError = false;
    m_jid = jid;
    setStatus(Status::Connecting);

    QXmppConfiguration config;
    config.setJid(jid);
    config.setPassword(password);
    // Phase 1 proves one clean connect/error round trip per attempt; QXmpp's
    // built-in silent background retries would obscure that state machine.
    // Session persistence / reconnect policy is a later-phase UI concern.
    config.setAutoReconnectionEnabled(false);
    if (m_insecureSkipTlsVerification) {
        config.setIgnoreSslErrors(true);
    }

    m_client.connectToServer(config);
}

void XmppClient::disconnectFromServer()
{
    m_client.disconnectFromServer();
    m_modules->clear();
    m_events->clear();
}

void XmppClient::fetchModuleInfo(const QString &bareJid, const QString &fullJid)
{
    comm::fetchModuleInfo(m_client, bareJid, fullJid, [this](ModuleInfo info) {
        logModuleInfo(info);
        m_modules->upsert(info);
        // Un-deduped on purpose, matches useXmpp.ts's own fetchModuleInfo:
        // re-subscribing to an already-subscribed node from the same JID
        // is a harmless no-op server-side.
        m_eventManager->subscribeToEvents(info.jid, info.events);
    });
}

void XmppClient::handlePresence(const QXmppPresence &presence)
{
    const QString from = presence.from();
    if (from.isEmpty()) {
        return;
    }
    if (QXmppUtils::jidToResource(from) != QLatin1String(kPyobsResource)) {
        return;
    }

    const QString bareJid = QXmppUtils::jidToBareJid(from);
    if (presence.type() == QXmppPresence::Unavailable) {
        m_modules->remove(bareJid);
    } else {
        fetchModuleInfo(bareJid, from);
    }
}

StateSubscription *XmppClient::subscribeState(const QString &bareJid, const QString &interfaceName, int version,
                                              QObject *parent)
{
    return m_stateSubscriptions->subscribe(bareJid, interfaceName, version, parent);
}

void XmppClient::executeMethod(const QString &bareJid, const QString &methodName, int paramCount)
{
    executeMethod(bareJid, methodName, paramCount, QJSValue());
}

void XmppClient::executeMethod(const QString &bareJid, const QString &methodName, int paramCount,
                               const QJSValue &callback)
{
    const QString fullJid = bareJid + QStringLiteral("/pyobs");
    // All-null params, one FieldSchema slot each (its type is never
    // consulted: valueToXml() writes <nil/> for a null WireValue
    // regardless of the declared type) - see Q_INVOKABLE declaration.
    const QVector<codec::WireValue> params(paramCount);
    const QVector<codec::FieldSchema> paramSchemas(paramCount);

    comm::executeMethod(m_client, fullJid, methodName, params, paramSchemas,
                        [this, methodName, callback](RpcResult result) {
        if (result.success) {
            m_lastRpcResult = result.value.isNull()
                ? QStringLiteral("%1 -> success").arg(methodName)
                : QStringLiteral("%1 -> success: %2")
                      .arg(methodName,
                           QString::fromUtf8(QJsonDocument::fromVariant(codec::toQVariant(result.value))
                                                  .toJson(QJsonDocument::Compact)));
        } else {
            m_lastRpcResult = QStringLiteral("%1 -> error%2: %3")
                                   .arg(methodName,
                                        result.errorClass.isEmpty() ? QString() : QStringLiteral(" (%1)").arg(result.errorClass),
                                        result.errorMessage);
        }
        qInfo().noquote() << "RPC" << m_lastRpcResult;
        Q_EMIT lastRpcResultChanged();

        if (callback.isCallable()) {
            QJSEngine *engine = qjsEngine(this);
            if (engine) {
                QJSValue resultObj = engine->newObject();
                resultObj.setProperty(QStringLiteral("success"), result.success);
                resultObj.setProperty(QStringLiteral("errorClass"), result.errorClass);
                resultObj.setProperty(QStringLiteral("errorMessage"), result.errorMessage);
                QJSValue callableCallback = callback;
                callableCallback.call(QJSValueList { resultObj });
            }
        }
    });
}

void XmppClient::probeRosterPresence()
{
    auto *roster = m_client.findExtension<QXmppRosterManager>();
    if (!roster) {
        return;
    }
    for (const QString &bareJid : roster->getRosterBareJids()) {
        QXmppPresence probe(QXmppPresence::Probe);
        probe.setTo(bareJid);
        m_client.sendPacket(probe);
    }
}

void XmppClient::setStatus(Status status, const QString &message)
{
    if (status == Status::Error) {
        m_hadError = true;
    }
    m_status = status;
    m_errorMessage = message;
    Q_EMIT statusChanged();
}

}
