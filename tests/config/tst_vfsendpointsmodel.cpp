#include <QSettings>
#include <QSignalSpy>
#include <QTest>

#include <qtkeychain/keychain.h>

#include "VfsEndpointsModel.h"

using namespace config;

class TestVfsEndpointsModel : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void cleanup();

    void addEndpointAppendsRowWithGeneratedId();
    void addEndpointFailsWithoutCurrentJid();
    void updateEndpointChangesFieldsOnly();
    void removeEndpointDropsTheRow();
    void endpointByIdReturnsEmptyMapWhenNotFound();
    void persistsAcrossInstances();
    void currentJidFiltersRows();
    void resolveVfsPathSplitsRootAndJoinsBaseUrl();
    void resolveVfsPathReturnsEmptyMapWhenUnresolved();
    void loadPasswordFailsWhenNothingStored();
    void storeAndLoadPasswordRoundTripsThroughKeychain();
    void removeEndpointDeletesItsKeychainEntry();
};

namespace {
QVariantMap rowAt(const VfsEndpointsModel &model, int row)
{
    const QModelIndex idx = model.index(row);
    return {
        {"id", model.data(idx, VfsEndpointsModel::IdRole)},
        {"root", model.data(idx, VfsEndpointsModel::RootRole)},
        {"baseUrl", model.data(idx, VfsEndpointsModel::BaseUrlRole)},
        {"username", model.data(idx, VfsEndpointsModel::UsernameRole)},
        {"hasStoredPassword", model.data(idx, VfsEndpointsModel::HasStoredPasswordRole)},
    };
}

// Same CI-skip reasoning as tst_savedaccountsmodel.cpp's own comment -
// verbatim copy, not re-derived.
bool realKeychainBackendAvailable()
{
    return QKeychain::isAvailable() && !qEnvironmentVariableIsSet("CI");
}
} // namespace

void TestVfsEndpointsModel::initTestCase()
{
    QCoreApplication::setOrganizationName(QStringLiteral("pyobs-tests"));
    QCoreApplication::setApplicationName(QStringLiteral("tst_vfsendpointsmodel"));
}

void TestVfsEndpointsModel::cleanup()
{
    QSettings settings;
    settings.clear();
}

void TestVfsEndpointsModel::addEndpointAppendsRowWithGeneratedId()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    QCOMPARE(model.rowCount(), 0);

    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://localhost:37075/"),
                                          QStringLiteral("alice"));

    QVERIFY(!id.isEmpty());
    QCOMPARE(model.rowCount(), 1);
    const QVariantMap row = rowAt(model, 0);
    QCOMPARE(row.value("id").toString(), id);
    QCOMPARE(row.value("root").toString(), QStringLiteral("cache"));
    QCOMPARE(row.value("baseUrl").toString(), QStringLiteral("http://localhost:37075/"));
    QCOMPARE(row.value("username").toString(), QStringLiteral("alice"));
    QCOMPARE(row.value("hasStoredPassword").toBool(), false);
}

void TestVfsEndpointsModel::addEndpointFailsWithoutCurrentJid()
{
    VfsEndpointsModel model;
    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://localhost/"), QString());
    QVERIFY(id.isEmpty());
    QCOMPARE(model.rowCount(), 0);
}

void TestVfsEndpointsModel::updateEndpointChangesFieldsOnly()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QString());

    model.updateEndpoint(id, QStringLiteral("pyobs"), QStringLiteral("http://b/"), QStringLiteral("bob"));

    const QVariantMap row = rowAt(model, 0);
    QCOMPARE(row.value("root").toString(), QStringLiteral("pyobs"));
    QCOMPARE(row.value("baseUrl").toString(), QStringLiteral("http://b/"));
    QCOMPARE(row.value("username").toString(), QStringLiteral("bob"));
    QCOMPARE(row.value("id").toString(), id);

    // Unknown id is a silent no-op, not a crash.
    model.updateEndpoint(QStringLiteral("no-such-id"), QStringLiteral("x"), QStringLiteral("y"), QString());
    QCOMPARE(model.rowCount(), 1);
}

void TestVfsEndpointsModel::removeEndpointDropsTheRow()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    const QString first = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QString());
    const QString second = model.addEndpoint(QStringLiteral("pyobs"), QStringLiteral("http://b/"), QString());

    model.removeEndpoint(first);

    QCOMPARE(model.rowCount(), 1);
    QCOMPARE(rowAt(model, 0).value("id").toString(), second);
}

void TestVfsEndpointsModel::endpointByIdReturnsEmptyMapWhenNotFound()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    QVERIFY(model.endpointById(QStringLiteral("no-such-id")).isEmpty());

    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QStringLiteral("x"));
    const QVariantMap found = model.endpointById(id);
    QCOMPARE(found.value("root").toString(), QStringLiteral("cache"));
    QCOMPARE(found.value("baseUrl").toString(), QStringLiteral("http://a/"));
}

void TestVfsEndpointsModel::persistsAcrossInstances()
{
    QString id;
    {
        VfsEndpointsModel model;
        model.setCurrentJid(QStringLiteral("user@localhost"));
        id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QString());
    }

    VfsEndpointsModel reloaded;
    reloaded.setCurrentJid(QStringLiteral("user@localhost"));
    QCOMPARE(reloaded.rowCount(), 1);
    QCOMPARE(rowAt(reloaded, 0).value("id").toString(), id);
}

void TestVfsEndpointsModel::currentJidFiltersRows()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("alice@localhost"));
    model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QString());

    model.setCurrentJid(QStringLiteral("bob@localhost"));
    QCOMPARE(model.rowCount(), 0);
    model.addEndpoint(QStringLiteral("pyobs"), QStringLiteral("http://b/"), QString());
    QCOMPARE(model.rowCount(), 1);
    QCOMPARE(rowAt(model, 0).value("root").toString(), QStringLiteral("pyobs"));

    model.setCurrentJid(QStringLiteral("alice@localhost"));
    QCOMPARE(model.rowCount(), 1);
    QCOMPARE(rowAt(model, 0).value("root").toString(), QStringLiteral("cache"));
}

void TestVfsEndpointsModel::resolveVfsPathSplitsRootAndJoinsBaseUrl()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://localhost:37075"),
                                          QStringLiteral("alice"));

    const QVariantMap resolved = model.resolveVfsPath(QStringLiteral("cache/2024/07/03/image.fits.gz"));
    QCOMPARE(resolved.value("url").toString(), QStringLiteral("http://localhost:37075/2024/07/03/image.fits.gz"));
    QCOMPARE(resolved.value("endpointId").toString(), id);
    QCOMPARE(resolved.value("username").toString(), QStringLiteral("alice"));
    QCOMPARE(resolved.value("hasStoredPassword").toBool(), false);

    // Leading slash is stripped, same as VirtualFileSystem.split_root.
    const QVariantMap resolvedWithSlash = model.resolveVfsPath(QStringLiteral("/cache/image.fits"));
    QCOMPARE(resolvedWithSlash.value("url").toString(), QStringLiteral("http://localhost:37075/image.fits"));

    // A baseUrl already ending in "/" isn't double-slashed.
    model.updateEndpoint(id, QStringLiteral("cache"), QStringLiteral("http://localhost:37075/"),
                          QStringLiteral("alice"));
    const QVariantMap resolvedTrailingSlash = model.resolveVfsPath(QStringLiteral("cache/image.fits"));
    QCOMPARE(resolvedTrailingSlash.value("url").toString(), QStringLiteral("http://localhost:37075/image.fits"));
}

void TestVfsEndpointsModel::resolveVfsPathReturnsEmptyMapWhenUnresolved()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://localhost/"), QString());

    // No root at all.
    QVERIFY(model.resolveVfsPath(QStringLiteral("no-slash-at-all")).isEmpty());
    // Root not covered by any configured endpoint.
    QVERIFY(model.resolveVfsPath(QStringLiteral("unknown-root/image.fits")).isEmpty());
}

void TestVfsEndpointsModel::loadPasswordFailsWhenNothingStored()
{
    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QString());

    QSignalSpy failedSpy(&model, &VfsEndpointsModel::passwordLoadFailed);
    QSignalSpy readySpy(&model, &VfsEndpointsModel::passwordReady);

    model.loadPassword(id);

    QCOMPARE(failedSpy.count(), 1);
    QCOMPARE(failedSpy.first().first().toString(), id);
    QCOMPARE(readySpy.count(), 0);
}

void TestVfsEndpointsModel::storeAndLoadPasswordRoundTripsThroughKeychain()
{
    if (!realKeychainBackendAvailable()) {
        QSKIP("No real platform keychain backend available in this environment");
    }

    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QString());

    QSignalSpy savedSpy(&model, &VfsEndpointsModel::credentialsSaved);
    model.storePassword(id, QStringLiteral("hunter2"));
    QVERIFY(savedSpy.wait());
    QCOMPARE(savedSpy.first().first().toString(), id);
    QCOMPARE(rowAt(model, 0).value("hasStoredPassword").toBool(), true);

    QSignalSpy readySpy(&model, &VfsEndpointsModel::passwordReady);
    model.loadPassword(id);
    QVERIFY(readySpy.wait());
    QCOMPARE(readySpy.first().at(0).toString(), id);
    QCOMPARE(readySpy.first().at(1).toString(), QStringLiteral("hunter2"));

    QSignalSpy forgottenSpy(&model, &VfsEndpointsModel::credentialsForgotten);
    model.clearStoredPassword(id);
    QVERIFY(forgottenSpy.wait());
    QCOMPARE(rowAt(model, 0).value("hasStoredPassword").toBool(), false);
}

void TestVfsEndpointsModel::removeEndpointDeletesItsKeychainEntry()
{
    if (!realKeychainBackendAvailable()) {
        QSKIP("No real platform keychain backend available in this environment");
    }

    VfsEndpointsModel model;
    model.setCurrentJid(QStringLiteral("user@localhost"));
    const QString id = model.addEndpoint(QStringLiteral("cache"), QStringLiteral("http://a/"), QString());

    QSignalSpy savedSpy(&model, &VfsEndpointsModel::credentialsSaved);
    model.storePassword(id, QStringLiteral("hunter2"));
    QVERIFY(savedSpy.wait());

    model.removeEndpoint(id);
    QCOMPARE(model.rowCount(), 0);

    auto *job = new QKeychain::ReadPasswordJob(QStringLiteral("Polaris"));
    job->setAutoDelete(true);
    job->setKey(id);
    QSignalSpy finishedSpy(job, &QKeychain::Job::finished);
    job->start();
    QVERIFY(finishedSpy.wait());
    QCOMPARE(job->error(), QKeychain::EntryNotFound);
}

QTEST_MAIN(TestVfsEndpointsModel)
#include "tst_vfsendpointsmodel.moc"
