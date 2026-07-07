#include <QSignalSpy>
#include <QTest>

#include "ModuleInfo.h"
#include "ModuleListModel.h"

using namespace comm;

class TestModuleListModel : public QObject
{
    Q_OBJECT

private slots:
    void newModuleDefaultsToReady();
    void versionComesFromIModuleCapabilities();
    void versionIsEmptyWithoutIModuleCapabilities();
    void updatePresenceUpdatesInPlaceAndReturnsTrue();
    void updatePresenceOnUnknownJidReturnsFalse();
    void hasInterfaceFindsAMatchAmongMultipleModules();
    void hasInterfaceIsFalseWhenNoModuleHasIt();
};

namespace {

ModuleInfo makeModule(const QString &jid)
{
    ModuleInfo info;
    info.jid = jid;
    info.fullJid = jid + QStringLiteral("/pyobs");
    info.name = jid;
    return info;
}

}

void TestModuleListModel::newModuleDefaultsToReady()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QCOMPARE(model.data(model.index(0), ModuleListModel::PresenceStateRole).toString(), QStringLiteral("ready"));
    QCOMPARE(model.data(model.index(0), ModuleListModel::PresenceErrorRole).toString(), QString());
}

void TestModuleListModel::versionComesFromIModuleCapabilities()
{
    ModuleInfo info = makeModule(QStringLiteral("roof@localhost"));
    info.capabilities.insert(QStringLiteral("IModule"),
                             codec::WireValue(codec::WireDict {
                                 { QStringLiteral("label"), codec::WireValue(QStringLiteral("Roof")) },
                                 { QStringLiteral("version"), codec::WireValue(QStringLiteral("1.2.3")) },
                             }));

    ModuleListModel model;
    model.upsert(info);

    QCOMPARE(model.data(model.index(0), ModuleListModel::VersionRole).toString(), QStringLiteral("1.2.3"));
}

void TestModuleListModel::versionIsEmptyWithoutIModuleCapabilities()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QCOMPARE(model.data(model.index(0), ModuleListModel::VersionRole).toString(), QString());
}

void TestModuleListModel::updatePresenceUpdatesInPlaceAndReturnsTrue()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QSignalSpy spy(&model, &ModuleListModel::dataChanged);
    QVERIFY(model.updatePresence(QStringLiteral("roof@localhost"), QStringLiteral("error"),
                                 QStringLiteral("stuck door")));

    QCOMPARE(spy.count(), 1);
    QCOMPARE(model.data(model.index(0), ModuleListModel::PresenceStateRole).toString(), QStringLiteral("error"));
    QCOMPARE(model.data(model.index(0), ModuleListModel::PresenceErrorRole).toString(), QStringLiteral("stuck door"));
    // Rest of the row is untouched by a presence-only update.
    QCOMPARE(model.data(model.index(0), ModuleListModel::JidRole).toString(), QStringLiteral("roof@localhost"));
}

void TestModuleListModel::updatePresenceOnUnknownJidReturnsFalse()
{
    ModuleListModel model;
    QVERIFY(!model.updatePresence(QStringLiteral("roof@localhost"), QStringLiteral("error"), QString()));
}

void TestModuleListModel::hasInterfaceFindsAMatchAmongMultipleModules()
{
    ModuleInfo telescope = makeModule(QStringLiteral("telescope@localhost"));
    telescope.interfaces.insert(QStringLiteral("ITelescope"), codec::InterfaceSchema { QStringLiteral("ITelescope") });

    ModuleInfo roof = makeModule(QStringLiteral("roof@localhost"));
    roof.interfaces.insert(QStringLiteral("IRoof"), codec::InterfaceSchema { QStringLiteral("IRoof") });

    ModuleListModel model;
    model.upsert(telescope);
    model.upsert(roof);

    QVERIFY(model.hasInterface(QStringLiteral("IRoof")));
    QVERIFY(model.hasInterface(QStringLiteral("ITelescope")));
}

void TestModuleListModel::hasInterfaceIsFalseWhenNoModuleHasIt()
{
    ModuleInfo telescope = makeModule(QStringLiteral("telescope@localhost"));
    telescope.interfaces.insert(QStringLiteral("ITelescope"), codec::InterfaceSchema { QStringLiteral("ITelescope") });

    ModuleListModel model;
    model.upsert(telescope);

    QVERIFY(!model.hasInterface(QStringLiteral("IRoof")));

    ModuleListModel empty;
    QVERIFY(!empty.hasInterface(QStringLiteral("IRoof")));
}

QTEST_MAIN(TestModuleListModel)
#include "tst_modulelistmodel.moc"
