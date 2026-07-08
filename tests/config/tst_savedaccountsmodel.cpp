#include <QSettings>
#include <QSignalSpy>
#include <QTest>

#include <qtkeychain/keychain.h>

#include "SavedAccountsModel.h"

using namespace config;

class TestSavedAccountsModel : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanup();

    void addAccountAppendsRowWithGeneratedId();
    void updateAccountChangesJidAndLabelOnly();
    void hostAndPortOverridePersist();
    void insecureSkipTlsPersists();
    void removeAccountDropsTheRow();
    void accountByIdReturnsEmptyMapWhenNotFound();
    void persistsAcrossInstances();
    void loadPasswordFailsWhenNothingStored();
    void storeAndLoadPasswordRoundTripsThroughKeychain();
    void removeAccountDeletesItsKeychainEntry();
};

namespace {
QVariantMap rowAt(const SavedAccountsModel &model, int row)
{
    const QModelIndex idx = model.index(row);
    return {
        {"id", model.data(idx, SavedAccountsModel::IdRole)},
        {"jid", model.data(idx, SavedAccountsModel::JidRole)},
        {"label", model.data(idx, SavedAccountsModel::LabelRole)},
        {"hasStoredPassword", model.data(idx, SavedAccountsModel::HasStoredPasswordRole)},
        {"host", model.data(idx, SavedAccountsModel::HostRole)},
        {"port", model.data(idx, SavedAccountsModel::PortRole)},
        {"insecureSkipTls", model.data(idx, SavedAccountsModel::InsecureSkipTlsRole)},
    };
}

// QKeychain::isAvailable() only checks that libsecret's symbols resolved
// via dlopen - not whether a real Secret Service is actually reachable
// over D-Bus. On a bare CI runner (no session D-Bus/keyring daemon at
// all) it wrongly returns true, which used to make these two tests hang
// until QSignalSpy::wait()'s timeout instead of skipping. Getting a real
// Secret Service running headlessly in CI turned out to be genuinely
// fragile (gnome-keyring's collection-creation flow needs its
// interactive gcr-prompter, which failed a different way in each of
// several attempts - see git history on .github/workflows/build.yml) -
// on the user's direct call, these two tests stay real-backend-only
// (dev machines, which do have one) and skip under CI specifically,
// rather than chase a mock D-Bus Secret Service implementation just for
// this. `CI` is the de facto standard env var GitHub Actions (and most
// other CI providers) set for exactly this kind of "am I running in CI"
// check.
bool realKeychainBackendAvailable()
{
    return QKeychain::isAvailable() && !qEnvironmentVariableIsSet("CI");
}
} // namespace

void TestSavedAccountsModel::initTestCase()
{
    QCoreApplication::setOrganizationName(QStringLiteral("pyobs-tests"));
    QCoreApplication::setApplicationName(QStringLiteral("tst_savedaccountsmodel"));
}

void TestSavedAccountsModel::cleanup()
{
    QSettings settings;
    settings.clear();
}

void TestSavedAccountsModel::addAccountAppendsRowWithGeneratedId()
{
    SavedAccountsModel model;
    QCOMPARE(model.rowCount(), 0);

    const QString id = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral("Roof"));

    QVERIFY(!id.isEmpty());
    QCOMPARE(model.rowCount(), 1);
    const QVariantMap row = rowAt(model, 0);
    QCOMPARE(row.value("id").toString(), id);
    QCOMPARE(row.value("jid").toString(), QStringLiteral("roof@localhost"));
    QCOMPARE(row.value("label").toString(), QStringLiteral("Roof"));
    QCOMPARE(row.value("hasStoredPassword").toBool(), false);
    QCOMPARE(row.value("host").toString(), QString());
    QCOMPARE(row.value("port").toInt(), 0);
    QCOMPARE(row.value("insecureSkipTls").toBool(), false);
}

void TestSavedAccountsModel::updateAccountChangesJidAndLabelOnly()
{
    SavedAccountsModel model;
    const QString id = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral("Roof"));

    model.updateAccount(id, QStringLiteral("roof2@localhost"), QStringLiteral("Roof 2"));

    const QVariantMap row = rowAt(model, 0);
    QCOMPARE(row.value("jid").toString(), QStringLiteral("roof2@localhost"));
    QCOMPARE(row.value("label").toString(), QStringLiteral("Roof 2"));
    QCOMPARE(row.value("id").toString(), id);

    // Unknown id is a silent no-op, not a crash.
    model.updateAccount(QStringLiteral("no-such-id"), QStringLiteral("x"), QStringLiteral("y"));
    QCOMPARE(model.rowCount(), 1);
}

void TestSavedAccountsModel::hostAndPortOverridePersist()
{
    SavedAccountsModel model;
    const QString id = model.addAccount(QStringLiteral("admin@monet.saao.ac.za"), QStringLiteral("SAAO"),
                                        QStringLiteral("monet.saao.ac.za"), 5222);

    QVariantMap row = rowAt(model, 0);
    QCOMPARE(row.value("host").toString(), QStringLiteral("monet.saao.ac.za"));
    QCOMPARE(row.value("port").toInt(), 5222);

    // Clearing the override (empty host, port 0) must actually clear it,
    // not just leave the previous values in place.
    model.updateAccount(id, QStringLiteral("admin@monet.saao.ac.za"), QStringLiteral("SAAO"));
    row = rowAt(model, 0);
    QCOMPARE(row.value("host").toString(), QString());
    QCOMPARE(row.value("port").toInt(), 0);

    // Persists across instances, same as jid/label/id.
    model.updateAccount(id, QStringLiteral("admin@monet.saao.ac.za"), QStringLiteral("SAAO"),
                        QStringLiteral("monet.saao.ac.za"), 5222);
    SavedAccountsModel reloaded;
    const QVariantMap reloadedRow = rowAt(reloaded, 0);
    QCOMPARE(reloadedRow.value("host").toString(), QStringLiteral("monet.saao.ac.za"));
    QCOMPARE(reloadedRow.value("port").toInt(), 5222);
}

void TestSavedAccountsModel::insecureSkipTlsPersists()
{
    SavedAccountsModel model;
    const QString id = model.addAccount(QStringLiteral("admin@localhost"), QStringLiteral("Dev"), QString(), 0,
                                        true);

    QVariantMap row = rowAt(model, 0);
    QCOMPARE(row.value("insecureSkipTls").toBool(), true);

    // Turning it back off via updateAccount must actually clear it.
    model.updateAccount(id, QStringLiteral("admin@localhost"), QStringLiteral("Dev"), QString(), 0, false);
    row = rowAt(model, 0);
    QCOMPARE(row.value("insecureSkipTls").toBool(), false);

    // Persists across instances, same as host/port.
    model.updateAccount(id, QStringLiteral("admin@localhost"), QStringLiteral("Dev"), QString(), 0, true);
    SavedAccountsModel reloaded;
    QCOMPARE(rowAt(reloaded, 0).value("insecureSkipTls").toBool(), true);
}

void TestSavedAccountsModel::removeAccountDropsTheRow()
{
    SavedAccountsModel model;
    const QString first = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral(""));
    const QString second = model.addAccount(QStringLiteral("telescope@localhost"), QStringLiteral(""));

    model.removeAccount(first);

    QCOMPARE(model.rowCount(), 1);
    QCOMPARE(rowAt(model, 0).value("id").toString(), second);
}

void TestSavedAccountsModel::accountByIdReturnsEmptyMapWhenNotFound()
{
    SavedAccountsModel model;
    QVERIFY(model.accountById(QStringLiteral("no-such-id")).isEmpty());

    const QString id = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral("Roof"));
    const QVariantMap found = model.accountById(id);
    QCOMPARE(found.value("jid").toString(), QStringLiteral("roof@localhost"));
    QCOMPARE(found.value("label").toString(), QStringLiteral("Roof"));
}

void TestSavedAccountsModel::persistsAcrossInstances()
{
    QString id;
    {
        SavedAccountsModel model;
        id = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral("Roof"));
    }

    SavedAccountsModel reloaded;
    QCOMPARE(reloaded.rowCount(), 1);
    QCOMPARE(rowAt(reloaded, 0).value("id").toString(), id);
}

void TestSavedAccountsModel::loadPasswordFailsWhenNothingStored()
{
    SavedAccountsModel model;
    const QString id = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral(""));

    QSignalSpy failedSpy(&model, &SavedAccountsModel::passwordLoadFailed);
    QSignalSpy readySpy(&model, &SavedAccountsModel::passwordReady);

    model.loadPassword(id);

    QCOMPARE(failedSpy.count(), 1);
    QCOMPARE(failedSpy.first().first().toString(), id);
    QCOMPARE(readySpy.count(), 0);
}

void TestSavedAccountsModel::storeAndLoadPasswordRoundTripsThroughKeychain()
{
    if (!realKeychainBackendAvailable()) {
        QSKIP("No real platform keychain backend available in this environment");
    }

    SavedAccountsModel model;
    const QString id = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral(""));

    QSignalSpy savedSpy(&model, &SavedAccountsModel::credentialsSaved);
    model.storePassword(id, QStringLiteral("hunter2"));
    QVERIFY(savedSpy.wait());
    QCOMPARE(savedSpy.first().first().toString(), id);
    QCOMPARE(rowAt(model, 0).value("hasStoredPassword").toBool(), true);

    QSignalSpy readySpy(&model, &SavedAccountsModel::passwordReady);
    model.loadPassword(id);
    QVERIFY(readySpy.wait());
    QCOMPARE(readySpy.first().at(0).toString(), id);
    QCOMPARE(readySpy.first().at(1).toString(), QStringLiteral("hunter2"));

    QSignalSpy forgottenSpy(&model, &SavedAccountsModel::credentialsForgotten);
    model.clearStoredPassword(id);
    QVERIFY(forgottenSpy.wait());
    QCOMPARE(rowAt(model, 0).value("hasStoredPassword").toBool(), false);
}

void TestSavedAccountsModel::removeAccountDeletesItsKeychainEntry()
{
    if (!realKeychainBackendAvailable()) {
        QSKIP("No real platform keychain backend available in this environment");
    }

    SavedAccountsModel model;
    const QString id = model.addAccount(QStringLiteral("roof@localhost"), QStringLiteral(""));

    QSignalSpy savedSpy(&model, &SavedAccountsModel::credentialsSaved);
    model.storePassword(id, QStringLiteral("hunter2"));
    QVERIFY(savedSpy.wait());

    model.removeAccount(id);
    QCOMPARE(model.rowCount(), 0);

    // Read it back directly (bypassing the now-gone model row) to confirm
    // the keychain entry itself is actually gone, not just the QSettings
    // row - removeAccount() fires its delete job fire-and-forget, so give
    // it a moment to land.
    auto *job = new QKeychain::ReadPasswordJob(QStringLiteral("pyobs-gui++"));
    job->setAutoDelete(true);
    job->setKey(id);
    QSignalSpy finishedSpy(job, &QKeychain::Job::finished);
    job->start();
    QVERIFY(finishedSpy.wait());
    QCOMPARE(job->error(), QKeychain::EntryNotFound);
}

QTEST_MAIN(TestSavedAccountsModel)
#include "tst_savedaccountsmodel.moc"
