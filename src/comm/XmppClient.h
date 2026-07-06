#pragma once

#include "ModuleListModel.h"
#include "StateSubscription.h"

#include <QObject>
#include <QString>
#include <QXmppClient.h>
#include <QXmppPresence.h>
#include <qqmlintegration.h>

namespace comm {

// StateSubscription.h is a full include, not a forward declaration: moc
// needs the complete type for subscribeState()'s Q_INVOKABLE return type
// (Qt6's constexpr metaobject codegen requires it - a forward declaration
// only "worked" once by accident, because CMake's combined
// mocs_compilation.cpp happened to pull in StateSubscription.h from another
// file's moc output first; that ordering isn't guaranteed).
class StateSubscriptionManager;

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
    Q_PROPERTY(comm::ModuleListModel *modules READ modules CONSTANT)

public:
    explicit XmppClient(QObject *parent = nullptr);

    QString status() const;
    QString errorMessage() const;
    ModuleListModel *modules() const { return m_modules; }

    // Off by default. Skips TLS certificate validation entirely for this
    // client - only ever meant for a self-signed/local dev ejabberd instance.
    // Deliberately explicit and opt-in per session (never persisted, not an
    // ambient env var) so it's visible in the UI whenever it's in effect,
    // never silently on.
    bool insecureSkipTlsVerification() const;
    void setInsecureSkipTlsVerification(bool value);

    Q_INVOKABLE void connectToServer(const QString &jid, const QString &password);
    Q_INVOKABLE void disconnectFromServer();

    // Since Phase 3, this both logs the parsed result via qInfo() (kept from
    // Phase 2's debug button, still handy) and upserts it into `modules` -
    // it's also what handlePresence() calls internally on every non-
    // "unavailable" presence, so Main.qml's manual debug button and live
    // presence-driven discovery share the exact same code path.
    Q_INVOKABLE void fetchModuleInfo(const QString &bareJid, const QString &fullJid);

    // Ref-counted PubSub state subscription - mirrors useXmpp.ts's
    // subscribeState() exactly (see StateSubscriptionManager). `parent` is
    // required (not defaulted to nullptr) deliberately: parenting the
    // returned StateSubscription to a real QML Item ties its destruction to
    // normal, deterministic Qt object-tree cleanup rather than relying on
    // JS garbage-collection timing for the resulting server unsubscribe.
    Q_INVOKABLE comm::StateSubscription *subscribeState(const QString &bareJid, const QString &interfaceName,
                                                        int version, QObject *parent);

Q_SIGNALS:
    void statusChanged();
    void insecureSkipTlsVerificationChanged();

private:
    enum class Status { Disconnected, Connecting, Connected, Error };

    void setStatus(Status status, const QString &message = {});

    // pyobs modules always connect with resource "pyobs" (matches
    // PYOBS_RESOURCE in useXmpp.ts); anything else is ignored. Unavailable
    // presence removes the module from `m_modules`, anything else triggers
    // fetchModuleInfo() to (re-)populate it.
    void handlePresence(const QXmppPresence &presence);

    // Without this, a client that connects *after* modules are already
    // online never learns about them - live presence pushes only fire for
    // state *changes*, not the already-online state at connect time. Called
    // once per roster fetch (QXmppRosterManager::rosterReceived(), which
    // QXmppClient triggers automatically after connecting).
    void probeRosterPresence();

    QXmppClient m_client;
    ModuleListModel *m_modules;
    // Owned by m_client (added via addNewExtension, same pattern as its
    // BasicExtensions) - not by XmppClient itself, hence a raw non-owning
    // pointer here.
    StateSubscriptionManager *m_stateSubscriptions;
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
