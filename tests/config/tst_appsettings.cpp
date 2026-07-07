#include <QSettings>
#include <QSignalSpy>
#include <QTest>

#include <qtkeychain/keychain.h>

#include "AppSettings.h"

using namespace config;

class TestAppSettings : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanup();

    void rememberCredentialsPersistsJidAndFlag();
    void forgetCredentialsClearsJidAndFlag();
    void loadSavedPasswordFailsWhenNothingRemembered();
    void rememberAndLoadRoundTripsThroughKeychain();
};

void TestAppSettings::initTestCase()
{
    // Distinct org/app name from the real app's - AppSettings' QSettings
    // resolves its file from these, and tests must never touch the real
    // ~/.config/pyobs/pyobs-gui++.conf a developer might actually have a
    // real remembered login in.
    QCoreApplication::setOrganizationName(QStringLiteral("pyobs-tests"));
    QCoreApplication::setApplicationName(QStringLiteral("tst_appsettings"));

    if (!QKeychain::isAvailable()) {
        QSKIP("No platform keychain backend available in this environment");
    }
}

void TestAppSettings::cleanup()
{
    // Every test either forgets what it remembered or never remembered
    // anything - this just guards against a failed test leaving the next
    // one a dirty QSettings file to contend with.
    QSettings settings;
    settings.clear();
}

void TestAppSettings::rememberCredentialsPersistsJidAndFlag()
{
    AppSettings settings;
    QSignalSpy jidSpy(&settings, &AppSettings::lastJidChanged);
    QSignalSpy rememberSpy(&settings, &AppSettings::rememberLoginChanged);
    QSignalSpy savedSpy(&settings, &AppSettings::credentialsSaved);

    settings.rememberCredentials(QStringLiteral("roof@localhost"), QStringLiteral("hunter2"));

    // jid/rememberLogin are only committed once the async keychain write
    // finishes - see AppSettings::rememberCredentials()'s own comment.
    QVERIFY(savedSpy.wait());
    QCOMPARE(settings.lastJid(), QStringLiteral("roof@localhost"));
    QVERIFY(settings.rememberLogin());
    QCOMPARE(jidSpy.count(), 1);
    QCOMPARE(rememberSpy.count(), 1);

    settings.forgetCredentials();
}

void TestAppSettings::forgetCredentialsClearsJidAndFlag()
{
    AppSettings settings;
    settings.rememberCredentials(QStringLiteral("roof@localhost"), QStringLiteral("hunter2"));
    QSignalSpy savedSpy(&settings, &AppSettings::credentialsSaved);
    QVERIFY(savedSpy.wait());

    QSignalSpy forgottenSpy(&settings, &AppSettings::credentialsForgotten);
    settings.forgetCredentials();

    QVERIFY(settings.lastJid().isEmpty());
    QVERIFY(!settings.rememberLogin());
    QVERIFY(forgottenSpy.wait());
}

void TestAppSettings::loadSavedPasswordFailsWhenNothingRemembered()
{
    AppSettings settings;
    QSignalSpy failedSpy(&settings, &AppSettings::passwordLoadFailed);
    QSignalSpy readySpy(&settings, &AppSettings::passwordReady);

    settings.loadSavedPassword();

    QCOMPARE(failedSpy.count(), 1);
    QCOMPARE(readySpy.count(), 0);
}

void TestAppSettings::rememberAndLoadRoundTripsThroughKeychain()
{
    AppSettings settings;
    QSignalSpy savedSpy(&settings, &AppSettings::credentialsSaved);
    settings.rememberCredentials(QStringLiteral("telescope@localhost"), QStringLiteral("s3cr3t"));
    QVERIFY(savedSpy.wait());

    QSignalSpy readySpy(&settings, &AppSettings::passwordReady);
    QSignalSpy failedSpy(&settings, &AppSettings::passwordLoadFailed);
    settings.loadSavedPassword();

    QVERIFY(readySpy.wait());
    QCOMPARE(failedSpy.count(), 0);
    QCOMPARE(readySpy.first().first().toString(), QStringLiteral("s3cr3t"));

    QSignalSpy forgottenSpy(&settings, &AppSettings::credentialsForgotten);
    settings.forgetCredentials();
    QVERIFY(forgottenSpy.wait());
}

QTEST_MAIN(TestAppSettings)
#include "tst_appsettings.moc"
