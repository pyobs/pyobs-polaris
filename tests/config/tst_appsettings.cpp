#include <QSignalSpy>
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

QTEST_MAIN(TestAppSettings)
#include "tst_appsettings.moc"
