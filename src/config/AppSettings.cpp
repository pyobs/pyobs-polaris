#include "AppSettings.h"

#include <qtkeychain/keychain.h>

namespace config {

namespace {
// Keychain entries are namespaced by this service string (see
// QKeychain::Job::service()) - arbitrary, just needs to be stable and
// distinct from other apps' entries in the same OS keychain.
constexpr auto kKeychainService = "pyobs-gui++";
constexpr auto kSettingsJidKey = "login/jid";
constexpr auto kSettingsRememberKey = "login/remember";
} // namespace

AppSettings::AppSettings(QObject *parent)
    : QObject(parent)
{
}

QString AppSettings::lastJid() const
{
    return m_settings.value(kSettingsJidKey).toString();
}

bool AppSettings::rememberLogin() const
{
    return m_settings.value(kSettingsRememberKey, false).toBool();
}

void AppSettings::rememberCredentials(const QString &jid, const QString &password)
{
    // jid/rememberLogin are only committed to QSettings once the keychain
    // write actually succeeds (below) - never optimistically up front. A
    // machine with no keychain backend at all (no gnome-keyring/KWallet
    // running) must not end up with rememberLogin=true and no password
    // ever actually stored, which would otherwise pre-fill the jid on next
    // launch while loadSavedPassword() silently fails forever.
    auto *job = new QKeychain::WritePasswordJob(kKeychainService, this);
    job->setKey(jid);
    job->setTextData(password);
    connect(job, &QKeychain::Job::finished, this, [this, job, jid] {
        if (job->error() == QKeychain::NoError) {
            m_settings.setValue(kSettingsJidKey, jid);
            m_settings.setValue(kSettingsRememberKey, true);
            Q_EMIT lastJidChanged();
            Q_EMIT rememberLoginChanged();
            Q_EMIT credentialsSaved();
        } else {
            Q_EMIT credentialsSaveFailed();
        }
    });
    job->start();
}

void AppSettings::forgetCredentials()
{
    const QString jid = lastJid();

    m_settings.remove(kSettingsJidKey);
    m_settings.remove(kSettingsRememberKey);
    Q_EMIT lastJidChanged();
    Q_EMIT rememberLoginChanged();

    if (jid.isEmpty()) {
        return;
    }

    auto *job = new QKeychain::DeletePasswordJob(kKeychainService, this);
    job->setKey(jid);
    connect(job, &QKeychain::Job::finished, this, [this, job] {
        if (job->error() == QKeychain::NoError || job->error() == QKeychain::EntryNotFound) {
            Q_EMIT credentialsForgotten();
        } else {
            Q_EMIT credentialsForgetFailed();
        }
    });
    job->start();
}

void AppSettings::loadSavedPassword()
{
    if (!rememberLogin() || lastJid().isEmpty()) {
        Q_EMIT passwordLoadFailed();
        return;
    }

    auto *job = new QKeychain::ReadPasswordJob(kKeychainService, this);
    job->setKey(lastJid());
    connect(job, &QKeychain::Job::finished, this, [this, job] {
        if (job->error() == QKeychain::NoError) {
            Q_EMIT passwordReady(job->textData());
        } else {
            Q_EMIT passwordLoadFailed();
        }
    });
    job->start();
}

} // namespace config
