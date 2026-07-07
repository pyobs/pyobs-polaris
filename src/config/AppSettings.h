#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
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

public:
    explicit AppSettings(QObject *parent = nullptr);

    QString lastSelectedAccountId() const;
    void setLastSelectedAccountId(const QString &id);

Q_SIGNALS:
    void lastSelectedAccountIdChanged();

private:
    QSettings m_settings;
};

} // namespace config
