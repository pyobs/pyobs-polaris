#include "AppSettings.h"

#include <QDir>
#include <QFileInfo>
#include <QUrl>

namespace config {

namespace {
constexpr auto kLastSelectedAccountIdKey = "login/lastSelectedAccountId";
constexpr auto kPluginsDirectoryKey = "plugins/directory";
constexpr auto kSidebarWidthKey = "sidebar/width";
constexpr auto kSidebarCollapsedKey = "sidebar/collapsed";
constexpr double kDefaultSidebarWidth = 220.0;
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

QString AppSettings::pluginsDirectory() const
{
    return m_settings.value(kPluginsDirectoryKey).toString();
}

void AppSettings::setPluginsDirectory(const QString &path)
{
    if (path == pluginsDirectory()) {
        return;
    }

    m_settings.setValue(kPluginsDirectoryKey, path);
    Q_EMIT pluginsDirectoryChanged();
}

double AppSettings::sidebarWidth() const
{
    return m_settings.value(kSidebarWidthKey, kDefaultSidebarWidth).toDouble();
}

void AppSettings::setSidebarWidth(double value)
{
    if (value == sidebarWidth()) {
        return;
    }

    m_settings.setValue(kSidebarWidthKey, value);
    Q_EMIT sidebarWidthChanged();
}

bool AppSettings::sidebarCollapsed() const
{
    return m_settings.value(kSidebarCollapsedKey, false).toBool();
}

void AppSettings::setSidebarCollapsed(bool value)
{
    if (value == sidebarCollapsed()) {
        return;
    }

    m_settings.setValue(kSidebarCollapsedKey, value);
    Q_EMIT sidebarCollapsedChanged();
}

QStringList AppSettings::pluginFiles() const
{
    const QString dir = pluginsDirectory();
    if (dir.isEmpty()) {
        return {};
    }

    const QDir qdir(dir);
    if (!qdir.exists()) {
        return {};
    }

    QStringList result;
    const QFileInfoList entries =
        qdir.entryInfoList(QStringList { QStringLiteral("*.qml") }, QDir::Files, QDir::Name);
    result.reserve(entries.size());
    for (const QFileInfo &info : entries) {
        result.push_back(QUrl::fromLocalFile(info.absoluteFilePath()).toString());
    }
    return result;
}

} // namespace config
