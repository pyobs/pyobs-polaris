#include "SavedAccountsModel.h"

#include <qtkeychain/keychain.h>

#include <QUuid>

namespace config {

namespace {
// Same keychain service as everything else this app stores - see
// AppSettings' original doc comment. Entries are keyed on the account's
// stable `id`, not its jid, so editing the jid never orphans a stored
// password.
constexpr auto kKeychainService = "pyobs-gui++";
constexpr auto kAccountsArrayKey = "accounts";
} // namespace

SavedAccountsModel::SavedAccountsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    load();
}

int SavedAccountsModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_accounts.size();
}

QVariant SavedAccountsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_accounts.size()) {
        return {};
    }

    const Account &account = m_accounts.at(index.row());
    switch (role) {
    case IdRole:
        return account.id;
    case JidRole:
        return account.jid;
    case LabelRole:
        return account.label;
    case HasStoredPasswordRole:
        return account.hasStoredPassword;
    case HostRole:
        return account.host;
    case PortRole:
        return account.port;
    case InsecureSkipTlsRole:
        return account.insecureSkipTls;
    default:
        return {};
    }
}

QHash<int, QByteArray> SavedAccountsModel::roleNames() const
{
    return {
        {IdRole, "id"},
        {JidRole, "jid"},
        {LabelRole, "label"},
        {HasStoredPasswordRole, "hasStoredPassword"},
        {HostRole, "host"},
        {PortRole, "port"},
        {InsecureSkipTlsRole, "insecureSkipTls"},
    };
}

QVariantMap SavedAccountsModel::accountById(const QString &id) const
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return {};
    }

    const Account &account = m_accounts.at(idx);
    return {
        {QStringLiteral("jid"), account.jid},
        {QStringLiteral("label"), account.label},
        {QStringLiteral("hasStoredPassword"), account.hasStoredPassword},
        {QStringLiteral("host"), account.host},
        {QStringLiteral("port"), account.port},
        {QStringLiteral("insecureSkipTls"), account.insecureSkipTls},
    };
}

QString SavedAccountsModel::addAccount(const QString &jid, const QString &label, const QString &host, int port,
                                       bool insecureSkipTls)
{
    Account account;
    account.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    account.jid = jid;
    account.label = label;
    account.host = host;
    account.port = port;
    account.insecureSkipTls = insecureSkipTls;

    beginInsertRows(QModelIndex(), m_accounts.size(), m_accounts.size());
    m_accounts.append(account);
    endInsertRows();
    save();

    return account.id;
}

void SavedAccountsModel::updateAccount(const QString &id, const QString &jid, const QString &label,
                                       const QString &host, int port, bool insecureSkipTls)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    m_accounts[idx].jid = jid;
    m_accounts[idx].label = label;
    m_accounts[idx].host = host;
    m_accounts[idx].port = port;
    m_accounts[idx].insecureSkipTls = insecureSkipTls;
    save();

    const QModelIndex modelIdx = index(idx);
    Q_EMIT dataChanged(modelIdx, modelIdx, {JidRole, LabelRole, HostRole, PortRole, InsecureSkipTlsRole});
}

void SavedAccountsModel::removeAccount(const QString &id)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    beginRemoveRows(QModelIndex(), idx, idx);
    m_accounts.removeAt(idx);
    endRemoveRows();
    save();

    // Fire-and-forget: the account is already gone from the list either
    // way, and there's no row left to report a keychain failure back to.
    // Deleting a nonexistent entry (hasStoredPassword was false, or
    // already stale) is harmless - QtKeychain just reports
    // EntryNotFound, which nothing here needs to react to.
    auto *job = new QKeychain::DeletePasswordJob(kKeychainService, this);
    job->setKey(id);
    job->start();
}

void SavedAccountsModel::storePassword(const QString &id, const QString &password)
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

void SavedAccountsModel::clearStoredPassword(const QString &id)
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

void SavedAccountsModel::loadPassword(const QString &id)
{
    const int idx = indexOfId(id);
    if (idx < 0 || !m_accounts.at(idx).hasStoredPassword) {
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

void SavedAccountsModel::load()
{
    const int count = m_settings.beginReadArray(kAccountsArrayKey);
    m_accounts.clear();
    m_accounts.reserve(count);
    for (int i = 0; i < count; ++i) {
        m_settings.setArrayIndex(i);
        Account account;
        account.id = m_settings.value("id").toString();
        account.jid = m_settings.value("jid").toString();
        account.label = m_settings.value("label").toString();
        account.hasStoredPassword = m_settings.value("hasStoredPassword", false).toBool();
        account.host = m_settings.value("host").toString();
        account.port = m_settings.value("port", 0).toInt();
        account.insecureSkipTls = m_settings.value("insecureSkipTls", false).toBool();
        m_accounts.append(account);
    }
    m_settings.endArray();
}

void SavedAccountsModel::save()
{
    m_settings.beginWriteArray(kAccountsArrayKey);
    for (int i = 0; i < m_accounts.size(); ++i) {
        m_settings.setArrayIndex(i);
        m_settings.setValue("id", m_accounts.at(i).id);
        m_settings.setValue("jid", m_accounts.at(i).jid);
        m_settings.setValue("label", m_accounts.at(i).label);
        m_settings.setValue("hasStoredPassword", m_accounts.at(i).hasStoredPassword);
        m_settings.setValue("host", m_accounts.at(i).host);
        m_settings.setValue("port", m_accounts.at(i).port);
        m_settings.setValue("insecureSkipTls", m_accounts.at(i).insecureSkipTls);
    }
    m_settings.endArray();
}

int SavedAccountsModel::indexOfId(const QString &id) const
{
    for (int i = 0; i < m_accounts.size(); ++i) {
        if (m_accounts.at(i).id == id) {
            return i;
        }
    }
    return -1;
}

void SavedAccountsModel::setHasStoredPassword(const QString &id, bool value)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    m_accounts[idx].hasStoredPassword = value;
    save();

    const QModelIndex modelIdx = index(idx);
    Q_EMIT dataChanged(modelIdx, modelIdx, {HasStoredPasswordRole});
}

} // namespace config
