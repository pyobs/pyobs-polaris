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
    void interfacesRoleListsEveryDeclaredInterfaceRegardlessOfState();
    void interfacesRoleIsEmptyWithNoInterfaces();
    void capabilitiesRoleListsEveryInterfacesWholeCapabilitiesDict();
    void capabilitiesRoleIsEmptyWithNoCapabilities();
    void versionComesFromIModuleCapabilities();
    void versionIsEmptyWithoutIModuleCapabilities();
    void modeGroupsComeFromIModeCapabilities();
    void modeGroupsIsEmptyWithoutIModeCapabilities();
    void binningOptionsComeFromIBinningCapabilities();
    void binningOptionsIsEmptyWithoutIBinningCapabilities();
    void windowExtentComesFromIWindowCapabilities();
    void windowExtentIsEmptyWithoutIWindowCapabilities();
    void imageFormatsComeFromIImageFormatCapabilities();
    void imageFormatsIsEmptyWithoutIImageFormatCapabilities();
    void commandSchemasExposeFullParamList();
    void commandSchemasMarkOptionalParamsAndUnwrapTheirType();
    void commandSchemasIsEmptyWithoutCommands();
    void updatePresenceUpdatesInPlaceAndReturnsTrue();
    void updatePresenceOnUnknownJidReturnsFalse();
    void hasInterfaceFindsAMatchAmongMultipleModules();
    void hasInterfaceIsFalseWhenNoModuleHasIt();
    void hasModuleFindsAnExactJidMatch();
    void hasModuleIsFalseWhenNoModuleHasThatJid();
    void jidForModuleNameMatchesTheJidsLocalPart();
    void jidForModuleNameIsEmptyWhenNoModuleMatches();
    void jidForModuleNameDoesNotMatchTheDisplayName();
    void jidsListsEveryModuleInRowOrder();
    void jidsIsEmptyWithNoModules();
    void allCommandsListsOneEntryPerCommandAcrossModules();
    void allCommandsDedupesACommandDeclaredByMultipleInterfaces();
    void allCommandsIsEmptyWithNoModules();
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

void TestModuleListModel::interfacesRoleListsEveryDeclaredInterfaceRegardlessOfState()
{
    codec::InterfaceSchema stateful;
    stateful.name = QStringLiteral("IRoof");
    stateful.version = 2;
    stateful.state = codec::StateSchema {};

    codec::InterfaceSchema stateless;
    stateless.name = QStringLiteral("IModule");
    stateless.version = 1;

    ModuleInfo info = makeModule(QStringLiteral("roof@localhost"));
    info.interfaces.insert(stateful.name, stateful);
    info.interfaces.insert(stateless.name, stateless);

    ModuleListModel model;
    model.upsert(info);

    const QVariantList interfaces = model.data(model.index(0), ModuleListModel::InterfacesRole).toList();
    QCOMPARE(interfaces.size(), 2);

    const QVariantMap first = interfaces.at(0).toMap();
    QCOMPARE(first.value(QStringLiteral("name")).toString(), QStringLiteral("IModule"));
    QCOMPARE(first.value(QStringLiteral("version")).toInt(), 1);

    const QVariantMap second = interfaces.at(1).toMap();
    QCOMPARE(second.value(QStringLiteral("name")).toString(), QStringLiteral("IRoof"));
    QCOMPARE(second.value(QStringLiteral("version")).toInt(), 2);
}

void TestModuleListModel::interfacesRoleIsEmptyWithNoInterfaces()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QVERIFY(model.data(model.index(0), ModuleListModel::InterfacesRole).toList().isEmpty());
}

void TestModuleListModel::capabilitiesRoleListsEveryInterfacesWholeCapabilitiesDict()
{
    ModuleInfo info = makeModule(QStringLiteral("roof@localhost"));
    info.capabilities.insert(QStringLiteral("IModule"),
                             codec::WireValue(codec::WireDict {
                                 { QStringLiteral("label"), codec::WireValue(QStringLiteral("Roof")) },
                                 { QStringLiteral("version"), codec::WireValue(QStringLiteral("1.2.3")) },
                             }));

    ModuleListModel model;
    model.upsert(info);

    const QVariantList capabilities = model.data(model.index(0), ModuleListModel::CapabilitiesRole).toList();
    QCOMPARE(capabilities.size(), 1);

    const QVariantMap entry = capabilities.at(0).toMap();
    QCOMPARE(entry.value(QStringLiteral("ifaceName")).toString(), QStringLiteral("IModule"));

    const QVariantList fields = entry.value(QStringLiteral("value")).toList();
    QCOMPARE(fields.size(), 2);
    QCOMPARE(fields.at(0).toMap().value(QStringLiteral("key")).toString(), QStringLiteral("label"));
    QCOMPARE(fields.at(0).toMap().value(QStringLiteral("value")).toString(), QStringLiteral("Roof"));
    QCOMPARE(fields.at(1).toMap().value(QStringLiteral("key")).toString(), QStringLiteral("version"));
    QCOMPARE(fields.at(1).toMap().value(QStringLiteral("value")).toString(), QStringLiteral("1.2.3"));
}

void TestModuleListModel::capabilitiesRoleIsEmptyWithNoCapabilities()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QVERIFY(model.data(model.index(0), ModuleListModel::CapabilitiesRole).toList().isEmpty());
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

void TestModuleListModel::modeGroupsComeFromIModeCapabilities()
{
    ModuleInfo info = makeModule(QStringLiteral("mode@localhost"));
    info.capabilities.insert(
        QStringLiteral("IMode"),
        codec::WireValue(codec::WireDict {
            { QStringLiteral("modes"),
              codec::WireValue(codec::WireDict {
                  { QStringLiteral("Size"),
                    codec::WireValue(codec::WireList {
                        codec::WireValue(QStringLiteral("XS")),
                        codec::WireValue(QStringLiteral("S")),
                        codec::WireValue(QStringLiteral("M")),
                    }) },
                  { QStringLiteral("Speed"),
                    codec::WireValue(codec::WireList {
                        codec::WireValue(QStringLiteral("Slow")),
                        codec::WireValue(QStringLiteral("Fast")),
                    }) },
              }) },
        }));

    ModuleListModel model;
    model.upsert(info);

    const QVariantList groups = model.data(model.index(0), ModuleListModel::ModeGroupsRole).toList();
    QCOMPARE(groups.size(), 2);

    const QVariantMap size = groups.at(0).toMap();
    QCOMPARE(size.value(QStringLiteral("group")).toString(), QStringLiteral("Size"));
    QCOMPARE(size.value(QStringLiteral("modes")).toStringList(),
             QStringList({ QStringLiteral("XS"), QStringLiteral("S"), QStringLiteral("M") }));

    const QVariantMap speed = groups.at(1).toMap();
    QCOMPARE(speed.value(QStringLiteral("group")).toString(), QStringLiteral("Speed"));
    QCOMPARE(speed.value(QStringLiteral("modes")).toStringList(),
             QStringList({ QStringLiteral("Slow"), QStringLiteral("Fast") }));
}

void TestModuleListModel::modeGroupsIsEmptyWithoutIModeCapabilities()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("mode@localhost")));

    QVERIFY(model.data(model.index(0), ModuleListModel::ModeGroupsRole).toList().isEmpty());
}

void TestModuleListModel::binningOptionsComeFromIBinningCapabilities()
{
    ModuleInfo info = makeModule(QStringLiteral("camera@localhost"));
    info.capabilities.insert(
        QStringLiteral("IBinning"),
        codec::WireValue(codec::WireDict {
            { QStringLiteral("binnings"),
              codec::WireValue(codec::WireList {
                  codec::WireValue(codec::WireDict {
                      { QStringLiteral("x"), codec::WireValue(qint64(1)) },
                      { QStringLiteral("y"), codec::WireValue(qint64(1)) },
                  }),
                  codec::WireValue(codec::WireDict {
                      { QStringLiteral("x"), codec::WireValue(qint64(2)) },
                      { QStringLiteral("y"), codec::WireValue(qint64(2)) },
                  }),
                  codec::WireValue(codec::WireDict {
                      { QStringLiteral("x"), codec::WireValue(qint64(3)) },
                      { QStringLiteral("y"), codec::WireValue(qint64(3)) },
                  }),
              }) },
        }));

    ModuleListModel model;
    model.upsert(info);

    const QVariantList options = model.data(model.index(0), ModuleListModel::BinningOptionsRole).toList();
    QCOMPARE(options, QVariantList({ QStringLiteral("1x1"), QStringLiteral("2x2"), QStringLiteral("3x3") }));
}

void TestModuleListModel::binningOptionsIsEmptyWithoutIBinningCapabilities()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("camera@localhost")));

    QVERIFY(model.data(model.index(0), ModuleListModel::BinningOptionsRole).toList().isEmpty());
}

void TestModuleListModel::windowExtentComesFromIWindowCapabilities()
{
    ModuleInfo info = makeModule(QStringLiteral("camera@localhost"));
    info.capabilities.insert(
        QStringLiteral("IWindow"),
        codec::WireValue(codec::WireDict {
            { QStringLiteral("full_frame_x"), codec::WireValue(qint64(0)) },
            { QStringLiteral("full_frame_y"), codec::WireValue(qint64(0)) },
            { QStringLiteral("full_frame_width"), codec::WireValue(qint64(512)) },
            { QStringLiteral("full_frame_height"), codec::WireValue(qint64(512)) },
        }));

    ModuleListModel model;
    model.upsert(info);

    const QVariantMap extent = model.data(model.index(0), ModuleListModel::WindowExtentRole).toMap();
    QCOMPARE(extent.value(QStringLiteral("fullFrameX")).toLongLong(), 0);
    QCOMPARE(extent.value(QStringLiteral("fullFrameY")).toLongLong(), 0);
    QCOMPARE(extent.value(QStringLiteral("fullFrameWidth")).toLongLong(), 512);
    QCOMPARE(extent.value(QStringLiteral("fullFrameHeight")).toLongLong(), 512);
}

void TestModuleListModel::windowExtentIsEmptyWithoutIWindowCapabilities()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("camera@localhost")));

    QVERIFY(model.data(model.index(0), ModuleListModel::WindowExtentRole).toMap().isEmpty());
}

void TestModuleListModel::imageFormatsComeFromIImageFormatCapabilities()
{
    ModuleInfo info = makeModule(QStringLiteral("camera@localhost"));
    info.capabilities.insert(
        QStringLiteral("IImageFormat"),
        codec::WireValue(codec::WireDict {
            { QStringLiteral("image_formats"),
              codec::WireValue(codec::WireList {
                  codec::WireValue(QStringLiteral("int8")),
                  codec::WireValue(QStringLiteral("int16")),
              }) },
        }));

    ModuleListModel model;
    model.upsert(info);

    const QVariantList formats = model.data(model.index(0), ModuleListModel::ImageFormatsRole).toList();
    QCOMPARE(formats, QVariantList({ QStringLiteral("int8"), QStringLiteral("int16") }));
}

void TestModuleListModel::imageFormatsIsEmptyWithoutIImageFormatCapabilities()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("camera@localhost")));

    QVERIFY(model.data(model.index(0), ModuleListModel::ImageFormatsRole).toList().isEmpty());
}

void TestModuleListModel::commandSchemasExposeFullParamList()
{
    codec::InterfaceSchema schema;
    schema.name = QStringLiteral("IMode");
    codec::CommandSchema cmd;
    cmd.name = QStringLiteral("set_mode");
    cmd.params = {
        codec::FieldSchema { QStringLiteral("group"), codec::WireType::stringType(), QString() },
        codec::FieldSchema { QStringLiteral("mode"), codec::WireType::stringType(), QString() },
    };
    schema.commands.insert(cmd.name, cmd);

    ModuleInfo info = makeModule(QStringLiteral("mode@localhost"));
    info.interfaces.insert(schema.name, schema);

    ModuleListModel model;
    model.upsert(info);

    const QVariantList commands = model.data(model.index(0), ModuleListModel::CommandSchemasRole).toList();
    QCOMPARE(commands.size(), 1);

    const QVariantMap entry = commands.at(0).toMap();
    QCOMPARE(entry.value(QStringLiteral("interface")).toString(), QStringLiteral("IMode"));
    QCOMPARE(entry.value(QStringLiteral("name")).toString(), QStringLiteral("set_mode"));

    const QVariantList params = entry.value(QStringLiteral("params")).toList();
    QCOMPARE(params.size(), 2);

    const QVariantMap group = params.at(0).toMap();
    QCOMPARE(group.value(QStringLiteral("name")).toString(), QStringLiteral("group"));
    QCOMPARE(group.value(QStringLiteral("type")).toString(), QStringLiteral("string"));
    QCOMPARE(group.value(QStringLiteral("unit")).toString(), QString());
    QCOMPARE(group.value(QStringLiteral("optional")).toBool(), false);
}

void TestModuleListModel::commandSchemasMarkOptionalParamsAndUnwrapTheirType()
{
    codec::InterfaceSchema schema;
    schema.name = QStringLiteral("IAutoFocus");
    codec::CommandSchema cmd;
    cmd.name = QStringLiteral("auto_focus");
    cmd.params = {
        codec::FieldSchema { QStringLiteral("count"), codec::WireType::optionalType(codec::WireType::int32Type()),
                              QStringLiteral("s") },
    };
    schema.commands.insert(cmd.name, cmd);

    ModuleInfo info = makeModule(QStringLiteral("autofocus@localhost"));
    info.interfaces.insert(schema.name, schema);

    ModuleListModel model;
    model.upsert(info);

    const QVariantList commands = model.data(model.index(0), ModuleListModel::CommandSchemasRole).toList();
    const QVariantList params = commands.at(0).toMap().value(QStringLiteral("params")).toList();
    QCOMPARE(params.size(), 1);

    const QVariantMap count = params.at(0).toMap();
    QCOMPARE(count.value(QStringLiteral("type")).toString(), QStringLiteral("int32"));
    QCOMPARE(count.value(QStringLiteral("unit")).toString(), QStringLiteral("s"));
    QCOMPARE(count.value(QStringLiteral("optional")).toBool(), true);
}

void TestModuleListModel::commandSchemasIsEmptyWithoutCommands()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("mode@localhost")));

    QVERIFY(model.data(model.index(0), ModuleListModel::CommandSchemasRole).toList().isEmpty());
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

void TestModuleListModel::hasModuleFindsAnExactJidMatch()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QVERIFY(model.hasModule(QStringLiteral("roof@localhost")));
}

void TestModuleListModel::hasModuleIsFalseWhenNoModuleHasThatJid()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QVERIFY(!model.hasModule(QStringLiteral("telescope@localhost")));

    ModuleListModel empty;
    QVERIFY(!empty.hasModule(QStringLiteral("roof@localhost")));
}

void TestModuleListModel::jidForModuleNameMatchesTheJidsLocalPart()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("mode@localhost")));

    QCOMPARE(model.jidForModuleName(QStringLiteral("mode")), QStringLiteral("mode@localhost"));
}

void TestModuleListModel::jidForModuleNameIsEmptyWhenNoModuleMatches()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("mode@localhost")));

    QVERIFY(model.jidForModuleName(QStringLiteral("roof")).isEmpty());
}

void TestModuleListModel::jidForModuleNameDoesNotMatchTheDisplayName()
{
    // Confirmed against pyobs-core's XmppComm source: shell dispatch resolves
    // the typed module name against the JID's local part only, never against
    // the disco#info display name - see jidForModuleName()'s doc comment.
    ModuleInfo info = makeModule(QStringLiteral("mode@localhost"));
    info.name = QStringLiteral("DummyMode");

    ModuleListModel model;
    model.upsert(info);

    QVERIFY(model.jidForModuleName(QStringLiteral("DummyMode")).isEmpty());
    QCOMPARE(model.jidForModuleName(QStringLiteral("mode")), QStringLiteral("mode@localhost"));
}

void TestModuleListModel::jidsListsEveryModuleInRowOrder()
{
    ModuleListModel model;
    model.upsert(makeModule(QStringLiteral("mode@localhost")));
    model.upsert(makeModule(QStringLiteral("roof@localhost")));

    QCOMPARE(model.jids(), QStringList({ QStringLiteral("mode@localhost"), QStringLiteral("roof@localhost") }));
}

void TestModuleListModel::jidsIsEmptyWithNoModules()
{
    ModuleListModel model;
    QVERIFY(model.jids().isEmpty());
}

void TestModuleListModel::allCommandsListsOneEntryPerCommandAcrossModules()
{
    codec::InterfaceSchema modeSchema;
    modeSchema.name = QStringLiteral("IMode");
    codec::CommandSchema setMode;
    setMode.name = QStringLiteral("set_mode");
    setMode.params = {
        codec::FieldSchema { QStringLiteral("mode"), codec::WireType::stringType(), QString() },
        codec::FieldSchema { QStringLiteral("group"), codec::WireType::stringType(), QString() },
    };
    modeSchema.commands.insert(setMode.name, setMode);

    ModuleInfo mode = makeModule(QStringLiteral("mode@localhost"));
    mode.interfaces.insert(modeSchema.name, modeSchema);

    codec::InterfaceSchema roofSchema;
    roofSchema.name = QStringLiteral("IRoof");
    codec::CommandSchema init;
    init.name = QStringLiteral("init");
    roofSchema.commands.insert(init.name, init);

    ModuleInfo roof = makeModule(QStringLiteral("roof@localhost"));
    roof.interfaces.insert(roofSchema.name, roofSchema);

    ModuleListModel model;
    model.upsert(mode);
    model.upsert(roof);

    const QVariantList commands = model.allCommands();
    QCOMPARE(commands.size(), 2);

    const QVariantMap setModeEntry = commands.at(0).toMap();
    QCOMPARE(setModeEntry.value(QStringLiteral("module")).toString(), QStringLiteral("mode"));
    QCOMPARE(setModeEntry.value(QStringLiteral("name")).toString(), QStringLiteral("set_mode"));
    QCOMPARE(setModeEntry.value(QStringLiteral("params")).toList().size(), 2);

    const QVariantMap initEntry = commands.at(1).toMap();
    QCOMPARE(initEntry.value(QStringLiteral("module")).toString(), QStringLiteral("roof"));
    QCOMPARE(initEntry.value(QStringLiteral("name")).toString(), QStringLiteral("init"));
    QVERIFY(initEntry.value(QStringLiteral("params")).toList().isEmpty());
}

void TestModuleListModel::allCommandsDedupesACommandDeclaredByMultipleInterfaces()
{
    codec::InterfaceSchema aSchema;
    aSchema.name = QStringLiteral("AInterface");
    codec::CommandSchema initFromA;
    initFromA.name = QStringLiteral("init");
    initFromA.params = { codec::FieldSchema { QStringLiteral("x"), codec::WireType::int32Type(), QString() } };
    aSchema.commands.insert(initFromA.name, initFromA);

    codec::InterfaceSchema bSchema;
    bSchema.name = QStringLiteral("BInterface");
    codec::CommandSchema initFromB;
    initFromB.name = QStringLiteral("init");
    initFromB.params = { codec::FieldSchema { QStringLiteral("y"), codec::WireType::stringType(), QString() } };
    bSchema.commands.insert(initFromB.name, initFromB);

    ModuleInfo info = makeModule(QStringLiteral("mode@localhost"));
    info.interfaces.insert(aSchema.name, aSchema);
    info.interfaces.insert(bSchema.name, bSchema);

    ModuleListModel model;
    model.upsert(info);

    const QVariantList commands = model.allCommands();
    QCOMPARE(commands.size(), 1);

    // "AInterface" sorts before "BInterface" - same iteration order
    // XmppClient::executeMethod() dispatch uses, so its params win.
    const QVariantList params = commands.at(0).toMap().value(QStringLiteral("params")).toList();
    QCOMPARE(params.size(), 1);
    QCOMPARE(params.at(0).toMap().value(QStringLiteral("name")).toString(), QStringLiteral("x"));
}

void TestModuleListModel::allCommandsIsEmptyWithNoModules()
{
    ModuleListModel model;
    QVERIFY(model.allCommands().isEmpty());
}

QTEST_MAIN(TestModuleListModel)
#include "tst_modulelistmodel.moc"
