#pragma once

#include <QObject>
#include <QString>
#include <QXmppClient.h>
#include <qqmlintegration.h>

namespace comm {

// Thin QML-facing wrapper around QXmppClient. `status` mirrors
// pyobs-web-client's useXmpp.ts XmppStatus type exactly: same four states,
// same names, so the model is recognizable to anyone who knows the web
// client - see DEVELOPMENT.md Phase 1.
class XmppClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY statusChanged)
    Q_PROPERTY(bool insecureSkipTlsVerification READ insecureSkipTlsVerification
                   WRITE setInsecureSkipTlsVerification NOTIFY insecureSkipTlsVerificationChanged)

public:
    explicit XmppClient(QObject *parent = nullptr);

    QString status() const;
    QString errorMessage() const;

    // Off by default. Skips TLS certificate validation entirely for this
    // client - only ever meant for a self-signed/local dev ejabberd instance.
    // Deliberately explicit and opt-in per session (never persisted, not an
    // ambient env var) so it's visible in the UI whenever it's in effect,
    // never silently on.
    bool insecureSkipTlsVerification() const;
    void setInsecureSkipTlsVerification(bool value);

    Q_INVOKABLE void connectToServer(const QString &jid, const QString &password);
    Q_INVOKABLE void disconnectFromServer();

Q_SIGNALS:
    void statusChanged();
    void insecureSkipTlsVerificationChanged();

private:
    enum class Status { Disconnected, Connecting, Connected, Error };

    void setStatus(Status status, const QString &message = {});

    QXmppClient m_client;
    Status m_status = Status::Disconnected;
    QString m_errorMessage;
    // Set for the duration of one connection attempt: once errorOccurred()
    // has reported a failure, the disconnected() signal that inevitably
    // follows (the stream tears itself down) must not clobber the "error"
    // status back to "disconnected" - regardless of which order QXmppClient
    // happens to emit those two signals in internally.
    bool m_hadError = false;
    bool m_insecureSkipTlsVerification = false;
};

}
