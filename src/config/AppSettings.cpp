#include "AppSettings.h"

#include <QDir>
#include <QFileInfo>
#include <QUrl>

namespace config {

namespace {
constexpr auto kLastSelectedAccountIdKey = "login/lastSelectedAccountId";
constexpr auto kPluginsDirectoryKey = "plugins/directory";
constexpr auto kObserverLatitudeKey = "observer/latitude";
constexpr auto kObserverLongitudeKey = "observer/longitude";
constexpr auto kObserverElevationKey = "observer/elevation";
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

double AppSettings::observerLatitude() const
{
    return m_settings.value(kObserverLatitudeKey, 0.0).toDouble();
}

void AppSettings::setObserverLatitude(double value)
{
    if (value == observerLatitude()) {
        return;
    }

    m_settings.setValue(kObserverLatitudeKey, value);
    Q_EMIT observerLatitudeChanged();
}

double AppSettings::observerLongitude() const
{
    return m_settings.value(kObserverLongitudeKey, 0.0).toDouble();
}

void AppSettings::setObserverLongitude(double value)
{
    if (value == observerLongitude()) {
        return;
    }

    m_settings.setValue(kObserverLongitudeKey, value);
    Q_EMIT observerLongitudeChanged();
}

double AppSettings::observerElevation() const
{
    return m_settings.value(kObserverElevationKey, 0.0).toDouble();
}

void AppSettings::setObserverElevation(double value)
{
    if (value == observerElevation()) {
        return;
    }

    m_settings.setValue(kObserverElevationKey, value);
    Q_EMIT observerElevationChanged();
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

bool AppSettings::hasObserverLocation() const
{
    return m_settings.contains(kObserverLatitudeKey) && m_settings.contains(kObserverLongitudeKey);
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
