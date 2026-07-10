#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <qqmlintegration.h>

namespace config {

// Wraps QSettings (resolves to the system's default config location - see
// main.cpp's setOrganizationName()/setApplicationName(), e.g.
// ~/.config/pyobs/Polaris.conf on Linux) for general, app-wide
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
    // `QSettings`'s own on-disk ini at ~/.config/pyobs/Polaris.conf on
    // Linux, `[General]` section, `pluginsDirectory=`), same "add more
    // settings here as features need them, don't design a UI speculatively"
    // discipline this class's own header comment already states.
    Q_PROPERTY(
        QString pluginsDirectory READ pluginsDirectory WRITE setPluginsDirectory NOTIFY pluginsDirectoryChanged)
    // Client-side observer location (TODO.md's "ITelescope follow-up") -
    // TelescopeView.qml's destination-coordinate preview needs this, but
    // pyobs-core has no wire path for it at all (confirmed against
    // source: the legacy Python GUI only had it because it ran in-process
    // as a pyobs.modules.Module inside the same MultiModule tree as the
    // telescope, sharing an in-memory astroplan.Observer - never
    // serialized to XMPP). Unlike pluginsDirectory above (a one-time
    // developer-only knob with deliberately no settings UI), this is a
    // genuinely interactive end-user feature - TelescopeView.qml gives it
    // real inline TextFields, not "edit the ini directly". Degrees,
    // degrees, meters - see hasObserverLocation() for why the getters
    // alone don't distinguish "never set" from "set to 0".
    Q_PROPERTY(double observerLatitude READ observerLatitude WRITE setObserverLatitude NOTIFY
                   observerLatitudeChanged)
    Q_PROPERTY(double observerLongitude READ observerLongitude WRITE setObserverLongitude NOTIFY
                   observerLongitudeChanged)
    Q_PROPERTY(double observerElevation READ observerElevation WRITE setObserverElevation NOTIFY
                   observerElevationChanged)

public:
    explicit AppSettings(QObject *parent = nullptr);

    QString lastSelectedAccountId() const;
    void setLastSelectedAccountId(const QString &id);

    QString pluginsDirectory() const;
    void setPluginsDirectory(const QString &path);

    double observerLatitude() const;
    void setObserverLatitude(double value);
    double observerLongitude() const;
    void setObserverLongitude(double value);
    double observerElevation() const;
    void setObserverElevation(double value);

    // Getters above default to 0.0 when unset - indistinguishable from a
    // real location at (0,0). This is the actual "has the user set this
    // yet" check TelescopeView.qml's destination preview gates on before
    // showing anything, checked via QSettings::contains() rather than a
    // NaN sentinel (a double NaN's round-trip through QSettings' on-disk
    // ini serialization isn't guaranteed reliable across platforms/Qt
    // versions - contains() sidesteps that entirely). Elevation
    // deliberately isn't part of this check - it defaults to sea level
    // (0m) harmlessly, and coordxform::equatorialToHorizontal() doesn't
    // even use it (see CoordinateTransform.cpp) - only lat/lon actually
    // gate whether a preview can be computed at all.
    Q_INVOKABLE bool hasObserverLocation() const;

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
    void observerLatitudeChanged();
    void observerLongitudeChanged();
    void observerElevationChanged();

private:
    QSettings m_settings;
};

} // namespace config
