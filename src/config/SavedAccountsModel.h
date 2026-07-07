#pragma once

#include <QAbstractListModel>
#include <QSettings>
#include <QString>
#include <QVector>
#include <qqmlintegration.h>

namespace config {

// A list of saved login accounts (JID + optional display label + whether
// a password is stored for it), persisted via QSettings (see AppSettings
// for where that resolves to). Each account has a stable internal `id`
// (a QUuid, generated on addAccount()) distinct from its jid/label -
// both of those are freely editable via updateAccount(), and the id is
// what the keychain entry is actually keyed on, so renaming an account's
// jid never orphans its stored password.
//
// Saving an account and storing its password are two independent,
// explicit choices (see storePassword()/clearStoredPassword()) - nothing
// here ever stores a password just because an account was added. This
// mirrors the project's existing rule for anything security-sensitive
// (see insecureSkipTlsVerification in XmppClient): visible, opt-in, never
// implicit.
class SavedAccountsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        JidRole,
        LabelRole,
        HasStoredPasswordRole,
        // Optional explicit host/port override, bypassing DNS SRV lookup
        // - see XmppClient::connectToServer()'s own doc comment for why
        // this exists. Empty host / port <= 0 means "no override, use
        // normal SRV-based discovery".
        HostRole,
        PortRole,
        // Per-account remembered "skip TLS certificate verification"
        // choice. Unlike XmppClient::insecureSkipTlsVerification's own
        // session-only default (see its doc comment - deliberately never
        // ambient/ persisted, so a real server never silently ends up with
        // TLS verification off), a *saved account* is an explicit, visible
        // opt-in on its own: the account itself is a stored, user-created
        // record naming a specific dev server, so remembering this choice
        // for it is no less visible than remembering its host/port
        // override next to it.
        InsecureSkipTlsRole,
    };
    Q_ENUM(Role)

    explicit SavedAccountsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // {"jid":..., "label":..., "hasStoredPassword":..., "host":...,
    // "port":..., "insecureSkipTls":...} for the account with this id, or
    // an empty map if no such account exists - lets QML code outside a
    // delegate's own context (e.g. after an async passwordReady(id, ...)
    // signal) look an account back up by id alone.
    Q_INVOKABLE QVariantMap accountById(const QString &id) const;

    // Adds a new saved account (no password stored yet) and returns its
    // generated id. host/port default to no override - see HostRole/PortRole.
    // insecureSkipTls defaults to off, matching XmppClient's own default.
    Q_INVOKABLE QString addAccount(const QString &jid, const QString &label, const QString &host = QString(),
                                   int port = 0, bool insecureSkipTls = false);

    // Updates jid/label/host/port/insecureSkipTls for an existing account.
    // No-op if id isn't found. Never touches whether a password is stored
    // - see storePassword()/clearStoredPassword() for that.
    Q_INVOKABLE void updateAccount(const QString &id, const QString &jid, const QString &label,
                                   const QString &host = QString(), int port = 0, bool insecureSkipTls = false);

    // Removes the account and starts an async keychain delete for it
    // (regardless of hasStoredPassword, in case that flag is ever stale -
    // deleting a nonexistent keychain entry is treated as success). No-op
    // if id isn't found.
    Q_INVOKABLE void removeAccount(const QString &id);

    // Starts an async keychain write for this account's password.
    // credentialsSaved(id)/credentialsSaveFailed(id) fires once it
    // completes; hasStoredPassword only flips to true on success - see
    // AppSettings' original design note on why this can't be optimistic.
    Q_INVOKABLE void storePassword(const QString &id, const QString &password);

    // Starts an async keychain delete for this account's password.
    // credentialsForgotten(id)/credentialsForgetFailed(id) fires once it
    // completes; hasStoredPassword only flips to false on success (or if
    // there was nothing to delete).
    Q_INVOKABLE void clearStoredPassword(const QString &id);

    // Starts an async keychain read for this account's password.
    // passwordReady(id, password) or passwordLoadFailed(id) fires once it
    // completes. No-op (immediate passwordLoadFailed()) if the account
    // isn't found or hasStoredPassword is false.
    Q_INVOKABLE void loadPassword(const QString &id);

Q_SIGNALS:
    void credentialsSaved(const QString &id);
    void credentialsSaveFailed(const QString &id);
    void credentialsForgotten(const QString &id);
    void credentialsForgetFailed(const QString &id);
    void passwordReady(const QString &id, const QString &password);
    void passwordLoadFailed(const QString &id);

private:
    struct Account {
        QString id;
        QString jid;
        QString label;
        bool hasStoredPassword = false;
        QString host;
        int port = 0;
        bool insecureSkipTls = false;
    };

    void load();
    void save();
    int indexOfId(const QString &id) const;
    void setHasStoredPassword(const QString &id, bool value);

    QVector<Account> m_accounts;
    QSettings m_settings;
};

} // namespace config
