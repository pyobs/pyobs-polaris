#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <qqmlintegration.h>

namespace config {

// Wraps QSettings (resolves to the system's default config location - see
// main.cpp's setOrganizationName()/setApplicationName(), e.g.
// ~/.config/pyobs/pyobs-gui++.conf on Linux) for general, app-wide
// settings that aren't per-account - see SavedAccountsModel for the
// actual saved-login list. Starts with just which account was last
// selected (purely to preselect it in the login window on next launch);
// add more settings here as features that need them come up, rather than
// designing a schema speculatively - see TODO.md.
class AppSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString lastSelectedAccountId READ lastSelectedAccountId WRITE setLastSelectedAccountId NOTIFY
                   lastSelectedAccountIdChanged)
    // Empty (the default) means "don't scan for plugins at all" - TODO.md's
    // "Plugin mechanism" item, step 2. No settings-UI control for this yet
    // (out of scope here - edit the config file directly, e.g. via
    // `QSettings`'s own on-disk ini at ~/.config/pyobs/pyobs-gui++.conf on
    // Linux, `[General]` section, `pluginsDirectory=`), same "add more
    // settings here as features need them, don't design a UI speculatively"
    // discipline this class's own header comment already states.
    Q_PROPERTY(
        QString pluginsDirectory READ pluginsDirectory WRITE setPluginsDirectory NOTIFY pluginsDirectoryChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    QString lastSelectedAccountId() const;
    void setLastSelectedAccountId(const QString &id);

    QString pluginsDirectory() const;
    void setPluginsDirectory(const QString &path);

    // Every *.qml file directly inside pluginsDirectory() (non-recursive -
    // matches TODO.md's "a configurable plugins directory" wording, not a
    // tree), sorted by name for a stable, predictable load order, each
    // already a file:// URL string ready for QML's Qt.createComponent() -
    // done here rather than left to ad-hoc string-concatenation in QML,
    // where local-path-to-URL conversion is easy to get subtly wrong
    // (spaces, non-ASCII paths). Empty if pluginsDirectory() is unset or
    // doesn't exist - PluginLoader.qml treats either the same way,
    // "nothing to load".
    Q_INVOKABLE QStringList pluginFiles() const;

Q_SIGNALS:
    void lastSelectedAccountIdChanged();
    void pluginsDirectoryChanged();

private:
    QSettings m_settings;
};

} // namespace config
