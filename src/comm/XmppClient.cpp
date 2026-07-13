#include "XmppClient.h"

#include "Discovery.h"
#include "EventManager.h"
#include "Rpc.h"
#include "StateSubscriptionManager.h"

#include "../codec/VariantBridge.h"
#include "../shell/ShellCommandParser.h"

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

// Mirrors pyobs-core's XmppComm._got_online/_got_presence_update mapping
// from XMPP presence show/status onto ModuleState: dnd -> error, away/xa ->
// local, anything else (available, chat) -> ready. "closed" has no mapping
// here since unavailable presence removes the module from the list instead.
QString presenceStateFor(const QXmppPresence &presence)
{
    switch (presence.availableStatusType()) {
    case QXmppPresence::DND:
        return QStringLiteral("error");
    case QXmppPresence::Away:
    case QXmppPresence::XA:
        return QStringLiteral("local");
    default:
        return QStringLiteral("ready");
    }
}
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

void XmppClient::connectToServer(const QString &jid, const QString &password, const QString &host, int port)
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
    if (!host.isEmpty()) {
        config.setHost(host);
        if (port > 0) {
            config.setPort(port);
        }
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
    fetchModuleInfo(bareJid, fullJid, QStringLiteral("ready"), QString());
}

void XmppClient::fetchModuleInfo(const QString &bareJid, const QString &fullJid, const QString &presenceState,
                                 const QString &presenceError)
{
    comm::fetchModuleInfo(m_client, bareJid, fullJid,
                          [this, presenceState, presenceError](ModuleInfo info) {
        logModuleInfo(info);
        info.presenceState = presenceState;
        info.presenceError = presenceError;
        m_modules->upsert(info);
        // Un-deduped on purpose, matches useXmpp.ts's own fetchModuleInfo:
        // re-subscribing to an already-subscribed node from the same JID
        // is a harmless no-op server-side.
        m_eventManager->subscribeToEvents(info.jid, info.events);
        fetchPermittedMethods(info.jid, info.fullJid, info.interfaces);
    });
}

void XmppClient::fetchPermittedMethods(const QString &bareJid, const QString &fullJid,
                                       const QMap<QString, codec::InterfaceSchema> &interfaces)
{
    const auto imodule = interfaces.constFind(QStringLiteral("IModule"));
    if (imodule == interfaces.constEnd() || !imodule->commands.contains(QStringLiteral("get_permitted_methods"))) {
        // No IModule, or this module's pyobs-core version doesn't declare
        // the command - stays fail-open (ModuleInfo::permittedMethods
        // stays nullopt from the fresh upsert() above).
        return;
    }

    comm::executeMethod(m_client, fullJid, QStringLiteral("get_permitted_methods"), {}, {},
                        [this, bareJid](RpcResult result) {
        if (!result.success) {
            // Transport error or a genuine remote fault - fail open, same
            // as "command not declared" above. Don't touch m_modules at
            // all, rather than writing an empty list (which would mean
            // "permits nothing").
            return;
        }
        QStringList methods;
        for (const QVariant &entry : codec::toQVariant(result.value).toList()) {
            methods.push_back(entry.toString());
        }
        m_modules->setPermittedMethods(bareJid, methods);
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
        return;
    }

    const QString state = presenceStateFor(presence);
    const QString errorText = presence.statusText();
    if (m_modules->updatePresence(bareJid, state, errorText)) {
        return;
    }
    fetchModuleInfo(bareJid, from, state, errorText);
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
                        [this, methodName, callback](RpcResult result) { reportRpcResult(methodName, result, callback); });
}

void XmppClient::executeMethod(const QString &bareJid, const QString &methodName, const QVariantList &params,
                               const QJSValue &callback)
{
    const codec::CommandSchema *schema = nullptr;
    if (const ModuleInfo *info = m_modules->find(bareJid)) {
        for (const codec::InterfaceSchema &iface : info->interfaces) {
            const auto it = iface.commands.constFind(methodName);
            if (it != iface.commands.constEnd()) {
                schema = &it.value();
                break;
            }
        }
    }
    if (!schema) {
        RpcResult result;
        result.errorMessage = QStringLiteral("Unknown command '%1' on %2").arg(methodName, bareJid);
        reportRpcResult(methodName, result, callback);
        return;
    }

    QVector<codec::WireValue> wireParams;
    QVector<codec::FieldSchema> paramSchemas = schema->params;
    wireParams.reserve(paramSchemas.size());
    for (int i = 0; i < paramSchemas.size(); ++i) {
        wireParams.push_back(codec::fromQVariant(i < params.size() ? params[i] : QVariant(), paramSchemas[i].type));
    }

    const QString fullJid = bareJid + QStringLiteral("/pyobs");
    comm::executeMethod(m_client, fullJid, methodName, wireParams, paramSchemas,
                        [this, methodName, callback](RpcResult result) { reportRpcResult(methodName, result, callback); });
}

void XmppClient::executeShellCommand(const QString &commandText, const QJSValue &callback)
{
    const auto parsed = shell::ShellCommandParser::parse(commandText);
    if (!parsed) {
        RpcResult result;
        result.errorMessage = QStringLiteral("Invalid command syntax: %1").arg(commandText);
        reportRpcResult(commandText, result, callback);
        return;
    }

    const QString bareJid = m_modules->jidForModuleName(parsed->module);
    if (bareJid.isEmpty()) {
        RpcResult result;
        result.errorMessage = QStringLiteral("Unknown module '%1'").arg(parsed->module);
        reportRpcResult(parsed->command, result, callback);
        return;
    }

    executeMethod(bareJid, parsed->command, parsed->params, callback);
}

void XmppClient::reportRpcResult(const QString &methodName, const RpcResult &result, const QJSValue &callback)
{
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
