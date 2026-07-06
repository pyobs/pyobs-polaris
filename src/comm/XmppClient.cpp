#include "XmppClient.h"

#include "Discovery.h"
#include "StateSubscriptionManager.h"

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
    , m_stateSubscriptions(m_client.addNewExtension<StateSubscriptionManager>())
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
}

void XmppClient::fetchModuleInfo(const QString &bareJid, const QString &fullJid)
{
    comm::fetchModuleInfo(m_client, bareJid, fullJid, [this](ModuleInfo info) {
        logModuleInfo(info);
        m_modules->upsert(info);
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
