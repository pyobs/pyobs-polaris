#include <QString>
#include <QTest>
#include <QXmlStreamWriter>

#include "Encode.h"

using namespace codec;

namespace {

// Wraps valueToXml's output in a synthetic <root> so the fragment is
// well-formed on its own, and returns the raw serialized XML for a direct
// string comparison - QXmlStreamWriter's compact (non-autoformatting)
// output is predictable enough that this is simpler than round-tripping
// through QDomDocument just to check a few tags.
QString encode(const WireValue &value, const WireType &type)
{
    QString xml;
    QXmlStreamWriter writer(&xml);
    writer.writeStartElement(QStringLiteral("root"));
    valueToXml(writer, value, type);
    writer.writeEndElement();
    return xml;
}

}

class TestEncode : public QObject
{
    Q_OBJECT

private slots:
    void nullValue();
    void boolValue();
    void int32Value();
    void float64Value();
    void stringValue();
    void enumValue();
    void dateTimeValue();
    void arrayValue();
    void optionalWithValue();
    void optionalWithNull();
    void structThrows();
    void anyThrows();
    void voidThrows();
};

void TestEncode::nullValue()
{
    QCOMPARE(encode(WireValue(), WireType::stringType()), QStringLiteral("<root><nil/></root>"));
}

void TestEncode::boolValue()
{
    QCOMPARE(encode(WireValue(true), WireType::boolType()), QStringLiteral("<root><boolean>true</boolean></root>"));
    QCOMPARE(encode(WireValue(false), WireType::boolType()), QStringLiteral("<root><boolean>false</boolean></root>"));
}

void TestEncode::int32Value()
{
    QCOMPARE(encode(WireValue(qint64(42)), WireType::int32Type()), QStringLiteral("<root><int>42</int></root>"));
    QCOMPARE(encode(WireValue(qint64(-7)), WireType::int32Type()), QStringLiteral("<root><int>-7</int></root>"));
}

void TestEncode::float64Value()
{
    QCOMPARE(encode(WireValue(3.5), WireType::float64Type()), QStringLiteral("<root><double>3.5</double></root>"));
}

void TestEncode::stringValue()
{
    QCOMPARE(encode(WireValue(QStringLiteral("hello")), WireType::stringType()),
             QStringLiteral("<root><string>hello</string></root>"));
}

void TestEncode::enumValue()
{
    QCOMPARE(encode(WireValue(QStringLiteral("idle")), WireType::enumType(QStringLiteral("MotionStatus"))),
             QStringLiteral("<root><string>idle</string></root>"));
}

void TestEncode::dateTimeValue()
{
    QCOMPARE(encode(WireValue(QStringLiteral("2026-07-06 12:00:00")), WireType::dateTimeType()),
             QStringLiteral("<root><string>2026-07-06 12:00:00</string></root>"));
}

void TestEncode::arrayValue()
{
    WireList list;
    list.push_back(WireValue(qint64(1)));
    list.push_back(WireValue(qint64(2)));
    QCOMPARE(encode(WireValue(list), WireType::arrayType(WireType::int32Type())),
             QStringLiteral("<root><items><item><int>1</int></item><item><int>2</int></item></items></root>"));
}

void TestEncode::optionalWithValue()
{
    QCOMPARE(encode(WireValue(QStringLiteral("hello")), WireType::optionalType(WireType::stringType())),
             QStringLiteral("<root><string>hello</string></root>"));
}

void TestEncode::optionalWithNull()
{
    QCOMPARE(encode(WireValue(), WireType::optionalType(WireType::stringType())),
             QStringLiteral("<root><nil/></root>"));
}

void TestEncode::structThrows()
{
    QVERIFY_THROWS_EXCEPTION(std::runtime_error,
                              encode(WireValue(QStringLiteral("x")), WireType::structType(QStringLiteral("Foo"))));
}

void TestEncode::anyThrows()
{
    QVERIFY_THROWS_EXCEPTION(std::runtime_error, encode(WireValue(qint64(1)), WireType::anyType()));
}

void TestEncode::voidThrows()
{
    QVERIFY_THROWS_EXCEPTION(std::runtime_error, encode(WireValue(qint64(1)), WireType::voidType()));
}

QTEST_MAIN(TestEncode)
#include "tst_encode.moc"
