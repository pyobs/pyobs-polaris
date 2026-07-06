#include <QDomDocument>
#include <QTest>

#include "SchemaParse.h"

using namespace codec;

namespace {

// Namespace processing must be on: parseInterfaceSchema/parseEventSchema
// read element.namespaceURI(), which QDom only populates when asked to.
QDomElement parseElement(const QString &xml)
{
    QDomDocument doc;
    doc.setContent(xml, QDomDocument::ParseOption::UseNamespaceProcessing);
    return doc.documentElement();
}

}

class TestSchemaParse : public QObject
{
    Q_OBJECT

private slots:
    void wireTypeScalars();
    void wireTypeEnum();
    void wireTypeStruct();
    void wireTypeArray();
    void wireTypeOptional();
    void wireTypeNested();
    void wireTypeUnknownFallsBackToAny();

    void versionedFeatureValid();
    void versionedFeatureWrongKind();
    void versionedFeatureMissingVersion();
    void versionedFeatureNonNumericVersion();

    void interfaceSchema();
    void eventSchema();
};

void TestSchemaParse::wireTypeScalars()
{
    QCOMPARE(parseWireType("bool").kind(), WireType::Kind::Bool);
    QCOMPARE(parseWireType("int32").kind(), WireType::Kind::Int32);
    QCOMPARE(parseWireType("float64").kind(), WireType::Kind::Float64);
    QCOMPARE(parseWireType("string").kind(), WireType::Kind::String);
    QCOMPARE(parseWireType("void").kind(), WireType::Kind::Void);
    QCOMPARE(parseWireType("datetime").kind(), WireType::Kind::DateTime);
}

void TestSchemaParse::wireTypeEnum()
{
    const WireType t = parseWireType("enum(MotionStatus)");
    QCOMPARE(t.kind(), WireType::Kind::Enum);
    QCOMPARE(t.name(), QStringLiteral("MotionStatus"));
}

void TestSchemaParse::wireTypeStruct()
{
    const WireType t = parseWireType("struct<DeviceMotionStatus>");
    QCOMPARE(t.kind(), WireType::Kind::Struct);
    QCOMPARE(t.name(), QStringLiteral("DeviceMotionStatus"));
}

void TestSchemaParse::wireTypeArray()
{
    const WireType t = parseWireType("array<string>");
    QCOMPARE(t.kind(), WireType::Kind::Array);
    QCOMPARE(t.item().kind(), WireType::Kind::String);
}

void TestSchemaParse::wireTypeOptional()
{
    const WireType t = parseWireType("optional<string>");
    QCOMPARE(t.kind(), WireType::Kind::Optional);
    QCOMPARE(t.inner().kind(), WireType::Kind::String);
}

void TestSchemaParse::wireTypeNested()
{
    // Real fixture from a live ITelescope/IMotion state field (see
    // DEVELOPMENT.md Phase 2's live-verification notes).
    const WireType t = parseWireType("array<struct<DeviceMotionStatus>>");
    QCOMPARE(t.kind(), WireType::Kind::Array);
    QCOMPARE(t.item().kind(), WireType::Kind::Struct);
    QCOMPARE(t.item().name(), QStringLiteral("DeviceMotionStatus"));
}

void TestSchemaParse::wireTypeUnknownFallsBackToAny()
{
    QCOMPARE(parseWireType("something-unrecognized").kind(), WireType::Kind::Any);
}

void TestSchemaParse::versionedFeatureValid()
{
    const auto ref = parseVersionedFeature(FeatureKind::Interface, QStringLiteral("urn:pyobs:interface:ICamera:1"));
    QVERIFY(ref.has_value());
    QCOMPARE(ref->name, QStringLiteral("ICamera"));
    QCOMPARE(ref->version, 1);
}

void TestSchemaParse::versionedFeatureWrongKind()
{
    const auto ref = parseVersionedFeature(FeatureKind::Event, QStringLiteral("urn:pyobs:interface:ICamera:1"));
    QVERIFY(!ref.has_value());
}

void TestSchemaParse::versionedFeatureMissingVersion()
{
    const auto ref = parseVersionedFeature(FeatureKind::Interface, QStringLiteral("urn:pyobs:interface:ICamera"));
    QVERIFY(!ref.has_value());
}

void TestSchemaParse::versionedFeatureNonNumericVersion()
{
    const auto ref = parseVersionedFeature(FeatureKind::Interface, QStringLiteral("urn:pyobs:interface:ICamera:x"));
    QVERIFY(!ref.has_value());
}

void TestSchemaParse::interfaceSchema()
{
    // Trimmed-down real shape (see DEVELOPMENT.md Phase 2's live-verification
    // notes against a real ITelescope/IMotion disco#info response).
    const InterfaceSchema schema = parseInterfaceSchema(parseElement(
        "<interface xmlns='urn:pyobs:interface:IMotion:1' name='IMotion'>"
        "<types>"
        "<enum name='MotionStatus'><value>idle</value><value>slewing</value><value>tracking</value></enum>"
        "</types>"
        "<command name='init'/>"
        "<command name='stop_motion'><parameter name='device' type='optional&lt;string&gt;'/></command>"
        "<state node='state/IMotion/1'>"
        "<field name='status' type='enum(MotionStatus)'/>"
        "<field name='time' type='datetime'/>"
        "</state>"
        "</interface>"));

    QCOMPARE(schema.name, QStringLiteral("IMotion"));
    QCOMPARE(schema.version, 1);

    QCOMPARE(schema.enums.size(), 1);
    QCOMPARE(schema.enums.value(QStringLiteral("MotionStatus")),
             QVector<QString>({ QStringLiteral("idle"), QStringLiteral("slewing"), QStringLiteral("tracking") }));

    QCOMPARE(schema.commands.size(), 2);
    QVERIFY(schema.commands.contains(QStringLiteral("init")));
    QCOMPARE(schema.commands.value(QStringLiteral("init")).params.size(), 0);
    const CommandSchema &stopMotion = schema.commands.value(QStringLiteral("stop_motion"));
    QCOMPARE(stopMotion.params.size(), 1);
    QCOMPARE(stopMotion.params[0].name, QStringLiteral("device"));
    QCOMPARE(stopMotion.params[0].type.kind(), WireType::Kind::Optional);
    QCOMPARE(stopMotion.params[0].type.inner().kind(), WireType::Kind::String);

    QVERIFY(schema.state.has_value());
    QCOMPARE(schema.state->node, QStringLiteral("state/IMotion/1"));
    QCOMPARE(schema.state->fields.size(), 2);
    QCOMPARE(schema.state->fields[0].name, QStringLiteral("status"));
    QCOMPARE(schema.state->fields[0].type.kind(), WireType::Kind::Enum);
    QCOMPARE(schema.state->fields[0].type.name(), QStringLiteral("MotionStatus"));
}

void TestSchemaParse::eventSchema()
{
    const EventSchema schema = parseEventSchema(parseElement(
        "<event xmlns='urn:pyobs:event:LogEvent:1' name='LogEvent'>"
        "<field name='level' type='string'/>"
        "<field name='line' type='int32'/>"
        "</event>"));

    QCOMPARE(schema.name, QStringLiteral("LogEvent"));
    QCOMPARE(schema.version, 1);
    QCOMPARE(schema.enums.size(), 0);
    QCOMPARE(schema.fields.size(), 2);
    QCOMPARE(schema.fields[0].name, QStringLiteral("level"));
    QCOMPARE(schema.fields[0].type.kind(), WireType::Kind::String);
    QCOMPARE(schema.fields[1].name, QStringLiteral("line"));
    QCOMPARE(schema.fields[1].type.kind(), WireType::Kind::Int32);
}

QTEST_MAIN(TestSchemaParse)
#include "tst_schema.moc"
