#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <qqmlintegration.h>

namespace config {

// Wraps QSettings (resolves to the system's default config location - see
// main.cpp's setOrganizationName()/setApplicationName(), e.g.
// ~/.config/pyobs/pyobs-gui++.conf on Linux) for whatever this app needs
// to persist. Starts with just the login-remembering flow (jid +
// rememberLogin flag); add more settings here as features that need them
// come up, rather than designing a schema speculatively - see TODO.md.
//
// The password itself never touches QSettings/the config file - it goes
// through the OS keychain via QtKeychain (rememberCredentials()/
// loadSavedPassword() below), matching Phase 1's existing rule that
// nothing security-sensitive is persisted without an explicit, visible
// opt-in (see insecureSkipTlsVerification in XmppClient).
class AppSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString lastJid READ lastJid NOTIFY lastJidChanged)
    Q_PROPERTY(bool rememberLogin READ rememberLogin NOTIFY rememberLoginChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    QString lastJid() const;
    bool rememberLogin() const;

    // Starts an async keychain write for the password (keyed on jid,
    // service "pyobs-gui++") - the config file itself never sees the
    // password. jid + rememberLogin=true are only committed to QSettings
    // once that write actually succeeds (credentialsSaved()); on failure
    // (credentialsSaveFailed()) nothing is persisted at all - a machine
    // with no keychain backend available must not end up with
    // rememberLogin=true and no password ever actually stored.
    Q_INVOKABLE void rememberCredentials(const QString &jid, const QString &password);

    // Clears the remembered jid/rememberLogin flag and starts an async
    // keychain delete for the previously-remembered jid, if any. No-op
    // (no signal fires) if nothing was remembered.
    Q_INVOKABLE void forgetCredentials();

    // Kicks off an async keychain read for lastJid(); passwordReady() or
    // passwordLoadFailed() fires when it completes. No-op (immediate
    // passwordLoadFailed()) if rememberLogin() is false.
    Q_INVOKABLE void loadSavedPassword();

Q_SIGNALS:
    void lastJidChanged();
    void rememberLoginChanged();
    void passwordReady(const QString &password);
    void passwordLoadFailed();
    void credentialsSaved();
    void credentialsSaveFailed();
    void credentialsForgotten();
    void credentialsForgetFailed();

private:
    QSettings m_settings;
};

} // namespace config
