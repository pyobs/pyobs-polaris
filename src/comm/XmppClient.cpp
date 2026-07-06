#include "XmppClient.h"

#include "Discovery.h"

#include <QXmppConfiguration.h>
#include <QXmppError.h>

namespace comm {

XmppClient::XmppClient(QObject *parent)
    : QObject(parent)
    , m_client(QXmppClient::BasicExtensions, this)
{
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
}

void XmppClient::fetchModuleInfo(const QString &bareJid, const QString &fullJid)
{
    comm::fetchModuleInfo(m_client, bareJid, fullJid, [](ModuleInfo info) {
        logModuleInfo(info);
    });
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
