#pragma once

#include "EventLogModel.h"
#include "ModuleListModel.h"
#include "StateSubscription.h"

#include <QJSValue>
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
class EventManager;

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
    Q_PROPERTY(QString jid READ jid NOTIFY statusChanged)
    Q_PROPERTY(bool insecureSkipTlsVerification READ insecureSkipTlsVerification
                   WRITE setInsecureSkipTlsVerification NOTIFY insecureSkipTlsVerificationChanged)
    Q_PROPERTY(comm::ModuleListModel *modules READ modules CONSTANT)
    Q_PROPERTY(comm::EventLogModel *events READ events CONSTANT)
    Q_PROPERTY(QString lastRpcResult READ lastRpcResult NOTIFY lastRpcResultChanged)

public:
    explicit XmppClient(QObject *parent = nullptr);

    QString status() const;
    QString errorMessage() const;
    // The JID last passed to connectToServer() - matches AppLayout.vue's
    // sidebar footer, which shows the signed-in JID next to "sign out".
    // Tied to statusChanged rather than its own signal since it only ever
    // changes together with a new connection attempt.
    QString jid() const { return m_jid; }
    ModuleListModel *modules() const { return m_modules; }
    EventLogModel *events() const { return m_events; }
    QString lastRpcResult() const { return m_lastRpcResult; }

    // Off by default. Skips TLS certificate validation entirely for this
    // client - only ever meant for a self-signed/local dev ejabberd instance.
    // Deliberately explicit and opt-in per session (never persisted, not an
    // ambient env var) so it's visible in the UI whenever it's in effect,
    // never silently on.
    bool insecureSkipTlsVerification() const;
    void setInsecureSkipTlsVerification(bool value);

    // host/port are an optional explicit override, skipping DNS SRV lookup
    // and QXmpp's default connection-order fallback (legacy TLS on 5223,
    // then STARTTLS on 5222) entirely - QXmppConfiguration connects
    // straight to host:port once host is non-empty. Needed for servers
    // with no SRV records where 5223 is closed/filtered rather than
    // actively refused: QXmpp then has to wait out a full TCP connect
    // timeout (a minute or more) before falling through to the working
    // port, which otherwise looks indistinguishable from actually being
    // stuck. port defaults to 0, meaning "use QXmppConfiguration's own
    // default (5222)".
    Q_INVOKABLE void connectToServer(const QString &jid, const QString &password, const QString &host = QString(),
                                     int port = 0);
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

    // Phase 5: no real param-entry UI yet (see DEVELOPMENT.md) - every
    // param is passed as null, which pyobs-core's own IRoof/IMotion
    // commands all accept since their params are declared optional. Full
    // JID is derived as bareJid + "/pyobs" (matches PYOBS_RESOURCE,
    // already the convention Main.qml's debug fetch button uses).
    // Dispatch is by method name alone - pyobs-core routes RPC calls
    // without an interface qualifier, so this doesn't need one either.
    Q_INVOKABLE void executeMethod(const QString &bareJid, const QString &methodName, int paramCount);

    // Phase 7: an overload that also reports the result back to a QML JS
    // callback (called with one object argument: {success, errorClass,
    // errorMessage}) - RoofWidget.qml needs this for its own per-module
    // running/error tracking (RoofView.vue's reactive running/errors
    // maps), unlike Phase 5's shared lastRpcResult debug label, which
    // isn't enough once more than one module's commands can be in flight
    // at once.
    Q_INVOKABLE void executeMethod(const QString &bareJid, const QString &methodName, int paramCount,
                                   const QJSValue &callback);

Q_SIGNALS:
    void statusChanged();
    void insecureSkipTlsVerificationChanged();
    void lastRpcResultChanged();

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
    EventLogModel *m_events;
    // Owned by m_client (added via addNewExtension, same pattern as its
    // BasicExtensions) - not by XmppClient itself, hence raw non-owning
    // pointers here.
    StateSubscriptionManager *m_stateSubscriptions;
    EventManager *m_eventManager;
    Status m_status = Status::Disconnected;
    QString m_errorMessage;
    // Set for the duration of one connection attempt: once errorOccurred()
    // has reported a failure, the disconnected() signal that inevitably
    // follows (the stream tears itself down) must not clobber the "error"
    // status back to "disconnected" - regardless of which order QXmppClient
    // happens to emit those two signals in internally.
    bool m_hadError = false;
    bool m_insecureSkipTlsVerification = false;
    QString m_lastRpcResult;
    QString m_jid;
};

}
