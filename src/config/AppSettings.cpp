#include "AppSettings.h"

namespace config {

namespace {
constexpr auto kLastSelectedAccountIdKey = "login/lastSelectedAccountId";
} // namespace

AppSettings::AppSettings(QObject *parent)
    : QObject(parent)
{
}

QString AppSettings::lastSelectedAccountId() const
{
    return m_settings.value(kLastSelectedAccountIdKey).toString();
}

void AppSettings::setLastSelectedAccountId(const QString &id)
{
    if (id == lastSelectedAccountId()) {
        return;
    }

    m_settings.setValue(kLastSelectedAccountIdKey, id);
    Q_EMIT lastSelectedAccountIdChanged();
}

} // namespace config
