#include <QTest>
#include <QVariant>

#include "VariantBridge.h"

using namespace codec;

class TestVariantBridge : public QObject
{
    Q_OBJECT

private slots:
    void fromQVariant_bool();
    void fromQVariant_int32();
    void fromQVariant_float64();
    void fromQVariant_string();
    void fromQVariant_enum();
    void fromQVariant_dateTime();
    void fromQVariant_optionalWithValue();
    void fromQVariant_optionalWithNull();
    void fromQVariant_invalidIsNull();
    void fromQVariant_unsupportedKindIsNull();
};

void TestVariantBridge::fromQVariant_bool()
{
    const WireValue value = fromQVariant(QVariant(true), WireType::boolType());
    QVERIFY(value.isBool());
    QCOMPARE(value.toBool(), true);
}

void TestVariantBridge::fromQVariant_int32()
{
    const WireValue value = fromQVariant(QVariant(5), WireType::int32Type());
    QVERIFY(value.isInt());
    QCOMPARE(value.toInt(), qint64(5));
}

void TestVariantBridge::fromQVariant_float64()
{
    // The whole reason this function exists: a QVariant holding an int
    // (e.g. a QML SpinBox's integer-typed value) targeting a float64 param
    // must come out the other side as a double-backed WireValue, not an
    // int-backed one - codec::valueToXml() would throw on the mismatch
    // otherwise (see VariantBridge.h's doc comment).
    const WireValue value = fromQVariant(QVariant(3), WireType::float64Type());
    QVERIFY(value.isDouble());
    QCOMPARE(value.toDouble(), 3.0);
}

void TestVariantBridge::fromQVariant_string()
{
    const WireValue value = fromQVariant(QVariant(QStringLiteral("hello")), WireType::stringType());
    QVERIFY(value.isString());
    QCOMPARE(value.toString(), QStringLiteral("hello"));
}

void TestVariantBridge::fromQVariant_enum()
{
    const WireValue value = fromQVariant(QVariant(QStringLiteral("idle")), WireType::enumType(QStringLiteral("MotionStatus")));
    QVERIFY(value.isString());
    QCOMPARE(value.toString(), QStringLiteral("idle"));
}

void TestVariantBridge::fromQVariant_dateTime()
{
    const WireValue value = fromQVariant(QVariant(QStringLiteral("2026-07-06 12:00:00")), WireType::dateTimeType());
    QVERIFY(value.isString());
    QCOMPARE(value.toString(), QStringLiteral("2026-07-06 12:00:00"));
}

void TestVariantBridge::fromQVariant_optionalWithValue()
{
    const WireValue value = fromQVariant(QVariant(2.5), WireType::optionalType(WireType::float64Type()));
    QVERIFY(value.isDouble());
    QCOMPARE(value.toDouble(), 2.5);
}

void TestVariantBridge::fromQVariant_optionalWithNull()
{
    const WireValue value = fromQVariant(QVariant(), WireType::optionalType(WireType::float64Type()));
    QVERIFY(value.isNull());
}

void TestVariantBridge::fromQVariant_invalidIsNull()
{
    const WireValue value = fromQVariant(QVariant(), WireType::stringType());
    QVERIFY(value.isNull());
}

void TestVariantBridge::fromQVariant_unsupportedKindIsNull()
{
    const WireValue value = fromQVariant(QVariant(QStringLiteral("x")), WireType::structType(QStringLiteral("Foo")));
    QVERIFY(value.isNull());
}

QTEST_MAIN(TestVariantBridge)
#include "tst_variantbridge.moc"
