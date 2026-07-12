#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include "AppSettings.h"

using namespace config;

class TestAppSettings : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanup();

    void lastSelectedAccountIdPersistsAndNotifies();
    void settingTheSameValueDoesNotNotifyAgain();
    void pluginsDirectoryDefaultsToEmpty();
    void pluginsDirectoryPersistsAndNotifies();
    void pluginFilesIsEmptyWhenDirectoryUnset();
    void pluginFilesIsEmptyWhenDirectoryDoesNotExist();
    void pluginFilesListsOnlyQmlFilesSortedByName();
    void sidebarWidthDefaultsAndPersists();
    void sidebarCollapsedDefaultsAndPersists();
};

void TestAppSettings::initTestCase()
{
    // Distinct org/app name from the real app's - AppSettings' QSettings
    // resolves its file from these, and tests must never touch the real
    // config a developer might actually have real saved accounts in.
    QCoreApplication::setOrganizationName(QStringLiteral("pyobs-tests"));
    QCoreApplication::setApplicationName(QStringLiteral("tst_appsettings"));
}

void TestAppSettings::cleanup()
{
    QSettings settings;
    settings.clear();
}

void TestAppSettings::lastSelectedAccountIdPersistsAndNotifies()
{
    AppSettings settings;
    QSignalSpy spy(&settings, &AppSettings::lastSelectedAccountIdChanged);

    QVERIFY(settings.lastSelectedAccountId().isEmpty());

    settings.setLastSelectedAccountId(QStringLiteral("abc-123"));

    QCOMPARE(settings.lastSelectedAccountId(), QStringLiteral("abc-123"));
    QCOMPARE(spy.count(), 1);

    // A fresh instance must see the same persisted value.
    AppSettings reloaded;
    QCOMPARE(reloaded.lastSelectedAccountId(), QStringLiteral("abc-123"));
}

void TestAppSettings::settingTheSameValueDoesNotNotifyAgain()
{
    AppSettings settings;
    settings.setLastSelectedAccountId(QStringLiteral("abc-123"));

    QSignalSpy spy(&settings, &AppSettings::lastSelectedAccountIdChanged);
    settings.setLastSelectedAccountId(QStringLiteral("abc-123"));

    QCOMPARE(spy.count(), 0);
}

void TestAppSettings::pluginsDirectoryDefaultsToEmpty()
{
    AppSettings settings;
    QVERIFY(settings.pluginsDirectory().isEmpty());
}

void TestAppSettings::pluginsDirectoryPersistsAndNotifies()
{
    AppSettings settings;
    QSignalSpy spy(&settings, &AppSettings::pluginsDirectoryChanged);

    settings.setPluginsDirectory(QStringLiteral("/home/user/.pyobs-gui-plugins"));

    QCOMPARE(settings.pluginsDirectory(), QStringLiteral("/home/user/.pyobs-gui-plugins"));
    QCOMPARE(spy.count(), 1);

    AppSettings reloaded;
    QCOMPARE(reloaded.pluginsDirectory(), QStringLiteral("/home/user/.pyobs-gui-plugins"));

    spy.clear();
    settings.setPluginsDirectory(QStringLiteral("/home/user/.pyobs-gui-plugins"));
    QCOMPARE(spy.count(), 0);
}

void TestAppSettings::pluginFilesIsEmptyWhenDirectoryUnset()
{
    AppSettings settings;
    QVERIFY(settings.pluginFiles().isEmpty());
}

void TestAppSettings::pluginFilesIsEmptyWhenDirectoryDoesNotExist()
{
    AppSettings settings;
    settings.setPluginsDirectory(QStringLiteral("/does/not/exist/anywhere"));
    QVERIFY(settings.pluginFiles().isEmpty());
}

void TestAppSettings::pluginFilesListsOnlyQmlFilesSortedByName()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    QVERIFY(QFile(dir.filePath(QStringLiteral("Zebra.qml"))).open(QIODevice::WriteOnly));
    QVERIFY(QFile(dir.filePath(QStringLiteral("Apple.qml"))).open(QIODevice::WriteOnly));
    QVERIFY(QFile(dir.filePath(QStringLiteral("notes.txt"))).open(QIODevice::WriteOnly));

    AppSettings settings;
    settings.setPluginsDirectory(dir.path());

    const QStringList files = settings.pluginFiles();
    QCOMPARE(files.size(), 2);
    QVERIFY(files.at(0).endsWith(QStringLiteral("Apple.qml")));
    QVERIFY(files.at(1).endsWith(QStringLiteral("Zebra.qml")));
    QVERIFY(files.at(0).startsWith(QStringLiteral("file://")));
}

void TestAppSettings::sidebarWidthDefaultsAndPersists()
{
    AppSettings settings;
    QCOMPARE(settings.sidebarWidth(), 220.0);

    QSignalSpy spy(&settings, &AppSettings::sidebarWidthChanged);
    settings.setSidebarWidth(300.0);

    QCOMPARE(settings.sidebarWidth(), 300.0);
    QCOMPARE(spy.count(), 1);

    AppSettings reloaded;
    QCOMPARE(reloaded.sidebarWidth(), 300.0);

    spy.clear();
    settings.setSidebarWidth(300.0);
    QCOMPARE(spy.count(), 0);
}

void TestAppSettings::sidebarCollapsedDefaultsAndPersists()
{
    AppSettings settings;
    QVERIFY(!settings.sidebarCollapsed());

    QSignalSpy spy(&settings, &AppSettings::sidebarCollapsedChanged);
    settings.setSidebarCollapsed(true);

    QVERIFY(settings.sidebarCollapsed());
    QCOMPARE(spy.count(), 1);

    AppSettings reloaded;
    QVERIFY(reloaded.sidebarCollapsed());

    spy.clear();
    settings.setSidebarCollapsed(true);
    QCOMPARE(spy.count(), 0);
}

QTEST_MAIN(TestAppSettings)
#include "tst_appsettings.moc"
