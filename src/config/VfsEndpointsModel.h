#pragma once

#include <QAbstractListModel>
#include <QSettings>
#include <QString>
#include <QVariantMap>
#include <QVector>
#include <qqmlintegration.h>

namespace config {

// A list of VFS (pyobs.vfs.VirtualFileSystem) endpoints: maps a VFS root
// name (the first path segment of a filename like
// NewImageEvent::filename or grab_data()'s return value - see
// VirtualFileSystem.split_root in pyobs-core) to an HTTP base URL this
// client can GET directly, mirroring pyobs-web-client's useVfsConfig.ts
// exactly (same root/baseUrl/username/password shape, same "only the
// HttpFile backend is modeled - a desktop/browser client can't reach
// LocalFile/SFTPFile/SMBFile" reasoning, see that file's own comment).
//
// Endpoints are scoped per-account (currentJid, keyed the same way
// useVfsConfig.ts keys by bareJid): different users of the same
// deployment may hold different archive-server credentials. Storage
// mirrors SavedAccountsModel exactly - one flat QSettings array (now
// carrying a bareJid field per row) filtered to currentJid for display,
// stable generated `id` per endpoint so editing root/baseUrl/username
// never orphans its keychain-stored password. Password is never written
// to QSettings, same rule as SavedAccountsModel's own passwords.
class VfsEndpointsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    // The bare JID whose endpoints this model currently exposes - set
    // this to XmppClient::jid once connected. Resetting it re-filters
    // the exposed rows in place (beginResetModel/endResetModel), it does
    // not reload from disk (all accounts' endpoints are always loaded).
    Q_PROPERTY(QString currentJid READ currentJid WRITE setCurrentJid NOTIFY currentJidChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1,
        RootRole,
        BaseUrlRole,
        UsernameRole,
        HasStoredPasswordRole,
    };
    Q_ENUM(Role)

    explicit VfsEndpointsModel(QObject *parent = nullptr);

    QString currentJid() const;
    void setCurrentJid(const QString &jid);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // {"root":..., "baseUrl":..., "username":..., "hasStoredPassword":...}
    // for the endpoint with this id, or an empty map if not found - same
    // shape/purpose as SavedAccountsModel::accountById(), for QML code
    // outside a delegate's own context.
    Q_INVOKABLE QVariantMap endpointById(const QString &id) const;

    // Adds a new endpoint for currentJid (no password stored yet) and
    // returns its generated id. No-op (returns an empty string) if
    // currentJid is empty.
    Q_INVOKABLE QString addEndpoint(const QString &root, const QString &baseUrl, const QString &username);

    // Updates root/baseUrl/username for an existing endpoint. No-op if id
    // isn't found. Never touches whether a password is stored - see
    // storePassword()/clearStoredPassword() for that.
    Q_INVOKABLE void updateEndpoint(const QString &id, const QString &root, const QString &baseUrl,
                                     const QString &username);

    // Removes the endpoint and starts an async keychain delete for it,
    // same "fire-and-forget, deleting a nonexistent entry is success"
    // shape as SavedAccountsModel::removeAccount().
    Q_INVOKABLE void removeEndpoint(const QString &id);

    // Same async keychain read/write/delete shape as SavedAccountsModel -
    // see its own doc comments, identical contract here.
    Q_INVOKABLE void storePassword(const QString &id, const QString &password);
    Q_INVOKABLE void clearStoredPassword(const QString &id);
    Q_INVOKABLE void loadPassword(const QString &id);

    // Splits `path` via VirtualFileSystem.split_root's own algorithm
    // (leading slash stripped, first "/" is the root/rest boundary),
    // resolves the root against currentJid's endpoints, and returns
    // {"url", "endpointId", "username", "hasStoredPassword"} - or an
    // empty map if no configured endpoint covers that root. Mirrors
    // useVfsConfig.ts's resolveVfsPath() exactly, plus the endpoint
    // metadata a caller needs to then call loadPassword()/VfsClient's
    // fetchFile() itself (this class does no fetching of its own -
    // that's comm::VfsClient, kept separate the same way
    // StateSubscriptionManager/Rpc are separate from XmppClient).
    Q_INVOKABLE QVariantMap resolveVfsPath(const QString &path) const;

Q_SIGNALS:
    void currentJidChanged();
    void credentialsSaved(const QString &id);
    void credentialsSaveFailed(const QString &id);
    void credentialsForgotten(const QString &id);
    void credentialsForgetFailed(const QString &id);
    void passwordReady(const QString &id, const QString &password);
    void passwordLoadFailed(const QString &id);

private:
    struct Endpoint {
        QString id;
        QString bareJid;
        QString root;
        QString baseUrl;
        QString username;
        bool hasStoredPassword = false;
    };

    void load();
    void save();
    int indexOfId(const QString &id) const;
    void setHasStoredPassword(const QString &id, bool value);

    // Real-storage indices (into m_endpoints) whose bareJid matches
    // currentJid, in storage order - the row<->storage-index mapping the
    // exposed filtered model uses everywhere below.
    QVector<int> visibleIndices() const;

    QString m_currentJid;
    QVector<Endpoint> m_endpoints;
    QSettings m_settings;
};

} // namespace config
