#include "VfsEndpointsModel.h"

#include <qtkeychain/keychain.h>

#include <QUuid>

namespace config {

namespace {
// Same keychain service as SavedAccountsModel - entries are keyed on
// this class's own generated `id`s (independent random QUuids), so
// sharing a service name with SavedAccountsModel's entries can't collide.
constexpr auto kKeychainService = "Polaris";
constexpr auto kEndpointsArrayKey = "vfsEndpoints";
} // namespace

VfsEndpointsModel::VfsEndpointsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    load();
}

QString VfsEndpointsModel::currentJid() const
{
    return m_currentJid;
}

void VfsEndpointsModel::setCurrentJid(const QString &jid)
{
    if (m_currentJid == jid) {
        return;
    }
    beginResetModel();
    m_currentJid = jid;
    endResetModel();
    Q_EMIT currentJidChanged();
}

int VfsEndpointsModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return visibleIndices().size();
}

QVariant VfsEndpointsModel::data(const QModelIndex &index, int role) const
{
    const QVector<int> visible = visibleIndices();
    if (!index.isValid() || index.row() < 0 || index.row() >= visible.size()) {
        return {};
    }

    const Endpoint &endpoint = m_endpoints.at(visible.at(index.row()));
    switch (role) {
    case IdRole:
        return endpoint.id;
    case RootRole:
        return endpoint.root;
    case BaseUrlRole:
        return endpoint.baseUrl;
    case UsernameRole:
        return endpoint.username;
    case HasStoredPasswordRole:
        return endpoint.hasStoredPassword;
    default:
        return {};
    }
}

QHash<int, QByteArray> VfsEndpointsModel::roleNames() const
{
    return {
        {IdRole, "id"},
        {RootRole, "root"},
        {BaseUrlRole, "baseUrl"},
        {UsernameRole, "username"},
        {HasStoredPasswordRole, "hasStoredPassword"},
    };
}

QVariantMap VfsEndpointsModel::endpointById(const QString &id) const
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return {};
    }

    const Endpoint &endpoint = m_endpoints.at(idx);
    return {
        {QStringLiteral("root"), endpoint.root},
        {QStringLiteral("baseUrl"), endpoint.baseUrl},
        {QStringLiteral("username"), endpoint.username},
        {QStringLiteral("hasStoredPassword"), endpoint.hasStoredPassword},
    };
}

QString VfsEndpointsModel::addEndpoint(const QString &root, const QString &baseUrl, const QString &username)
{
    if (m_currentJid.isEmpty()) {
        return {};
    }

    Endpoint endpoint;
    endpoint.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    endpoint.bareJid = m_currentJid;
    endpoint.root = root;
    endpoint.baseUrl = baseUrl;
    endpoint.username = username;

    const int row = visibleIndices().size();
    beginInsertRows(QModelIndex(), row, row);
    m_endpoints.append(endpoint);
    endInsertRows();
    save();

    return endpoint.id;
}

void VfsEndpointsModel::updateEndpoint(const QString &id, const QString &root, const QString &baseUrl,
                                        const QString &username)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    m_endpoints[idx].root = root;
    m_endpoints[idx].baseUrl = baseUrl;
    m_endpoints[idx].username = username;
    save();

    const int row = visibleIndices().indexOf(idx);
    if (row >= 0) {
        const QModelIndex modelIdx = index(row);
        Q_EMIT dataChanged(modelIdx, modelIdx, {RootRole, BaseUrlRole, UsernameRole});
    }
}

void VfsEndpointsModel::removeEndpoint(const QString &id)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    const int row = visibleIndices().indexOf(idx);
    if (row >= 0) {
        beginRemoveRows(QModelIndex(), row, row);
        m_endpoints.removeAt(idx);
        endRemoveRows();
    } else {
        m_endpoints.removeAt(idx);
    }
    save();

    // Fire-and-forget, same reasoning as SavedAccountsModel::removeAccount().
    auto *job = new QKeychain::DeletePasswordJob(kKeychainService, this);
    job->setKey(id);
    job->start();
}

void VfsEndpointsModel::storePassword(const QString &id, const QString &password)
{
    auto *job = new QKeychain::WritePasswordJob(kKeychainService, this);
    job->setKey(id);
    job->setTextData(password);
    connect(job, &QKeychain::Job::finished, this, [this, job, id] {
        if (job->error() == QKeychain::NoError) {
            setHasStoredPassword(id, true);
            Q_EMIT credentialsSaved(id);
        } else {
            Q_EMIT credentialsSaveFailed(id);
        }
    });
    job->start();
}

void VfsEndpointsModel::clearStoredPassword(const QString &id)
{
    auto *job = new QKeychain::DeletePasswordJob(kKeychainService, this);
    job->setKey(id);
    connect(job, &QKeychain::Job::finished, this, [this, job, id] {
        if (job->error() == QKeychain::NoError || job->error() == QKeychain::EntryNotFound) {
            setHasStoredPassword(id, false);
            Q_EMIT credentialsForgotten(id);
        } else {
            Q_EMIT credentialsForgetFailed(id);
        }
    });
    job->start();
}

void VfsEndpointsModel::loadPassword(const QString &id)
{
    const int idx = indexOfId(id);
    if (idx < 0 || !m_endpoints.at(idx).hasStoredPassword) {
        Q_EMIT passwordLoadFailed(id);
        return;
    }

    auto *job = new QKeychain::ReadPasswordJob(kKeychainService, this);
    job->setKey(id);
    connect(job, &QKeychain::Job::finished, this, [this, job, id] {
        if (job->error() == QKeychain::NoError) {
            Q_EMIT passwordReady(id, job->textData());
        } else {
            Q_EMIT passwordLoadFailed(id);
        }
    });
    job->start();
}

QVariantMap VfsEndpointsModel::resolveVfsPath(const QString &path) const
{
    QString clean = path;
    if (clean.startsWith(QLatin1Char('/'))) {
        clean = clean.mid(1);
    }
    const int slash = clean.indexOf(QLatin1Char('/'));
    if (slash < 0) {
        return {};
    }
    const QString root = clean.left(slash);
    const QString rest = clean.mid(slash + 1);

    for (const int idx : visibleIndices()) {
        const Endpoint &endpoint = m_endpoints.at(idx);
        if (endpoint.root != root) {
            continue;
        }
        QString base = endpoint.baseUrl;
        if (!base.endsWith(QLatin1Char('/'))) {
            base += QLatin1Char('/');
        }
        return {
            {QStringLiteral("url"), base + rest},
            {QStringLiteral("endpointId"), endpoint.id},
            {QStringLiteral("username"), endpoint.username},
            {QStringLiteral("hasStoredPassword"), endpoint.hasStoredPassword},
        };
    }
    return {};
}

void VfsEndpointsModel::load()
{
    const int count = m_settings.beginReadArray(kEndpointsArrayKey);
    m_endpoints.clear();
    m_endpoints.reserve(count);
    for (int i = 0; i < count; ++i) {
        m_settings.setArrayIndex(i);
        Endpoint endpoint;
        endpoint.id = m_settings.value("id").toString();
        endpoint.bareJid = m_settings.value("bareJid").toString();
        endpoint.root = m_settings.value("root").toString();
        endpoint.baseUrl = m_settings.value("baseUrl").toString();
        endpoint.username = m_settings.value("username").toString();
        endpoint.hasStoredPassword = m_settings.value("hasStoredPassword", false).toBool();
        m_endpoints.append(endpoint);
    }
    m_settings.endArray();
}

void VfsEndpointsModel::save()
{
    m_settings.beginWriteArray(kEndpointsArrayKey);
    for (int i = 0; i < m_endpoints.size(); ++i) {
        m_settings.setArrayIndex(i);
        m_settings.setValue("id", m_endpoints.at(i).id);
        m_settings.setValue("bareJid", m_endpoints.at(i).bareJid);
        m_settings.setValue("root", m_endpoints.at(i).root);
        m_settings.setValue("baseUrl", m_endpoints.at(i).baseUrl);
        m_settings.setValue("username", m_endpoints.at(i).username);
        m_settings.setValue("hasStoredPassword", m_endpoints.at(i).hasStoredPassword);
    }
    m_settings.endArray();
}

int VfsEndpointsModel::indexOfId(const QString &id) const
{
    for (int i = 0; i < m_endpoints.size(); ++i) {
        if (m_endpoints.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

void VfsEndpointsModel::setHasStoredPassword(const QString &id, bool value)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    m_endpoints[idx].hasStoredPassword = value;
    save();

    const int row = visibleIndices().indexOf(idx);
    if (row >= 0) {
        const QModelIndex modelIdx = index(row);
        Q_EMIT dataChanged(modelIdx, modelIdx, {HasStoredPasswordRole});
    }
}

QVector<int> VfsEndpointsModel::visibleIndices() const
{
    QVector<int> result;
    for (int i = 0; i < m_endpoints.size(); ++i) {
        if (m_endpoints.at(i).bareJid == m_currentJid) {
            result.append(i);
        }
    }
    return result;
}

} // namespace config
