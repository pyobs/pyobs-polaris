#include <QTest>

#include "Sexagesimal.h"

using namespace sexagesimal;

class TestSexagesimal : public QObject
{
    Q_OBJECT

private slots:
    void bareDecimalDegreesUnchangedForRaAndDec();
    void bareNegativeDecimalDegrees();
    void colonSeparatedRaAppliesHoursTimesFifteen();
    void colonSeparatedDecDoesNotApplyHoursFactor();
    void negativeSexagesimalDec();
    void explicitPlusSignSexagesimal();
    void secondsAreOptional();
    void spaceSeparatedAndLetterSeparatedAreEquivalent();
    void emptyInputIsRejected();
    void nonNumericInputIsRejected();
    void tooManyComponentsIsRejected();
    void outOfRangeMinutesIsRejected();
    void outOfRangeSecondsIsRejected();
    void qmlAdapterReturnsNanForInvalidInput();
};

void TestSexagesimal::bareDecimalDegreesUnchangedForRaAndDec()
{
    QCOMPARE(parseCoordinate(QStringLiteral("180.5"), true).value(), 180.5);
    QCOMPARE(parseCoordinate(QStringLiteral("45.25"), false).value(), 45.25);
}

void TestSexagesimal::bareNegativeDecimalDegrees()
{
    QCOMPARE(parseCoordinate(QStringLiteral("-45.25"), false).value(), -45.25);
}

void TestSexagesimal::colonSeparatedRaAppliesHoursTimesFifteen()
{
    // 12h00m00s -> 180 degrees, 12h30m00s -> 187.5 degrees.
    QCOMPARE(parseCoordinate(QStringLiteral("12:00:00"), true).value(), 180.0);
    QVERIFY(std::abs(parseCoordinate(QStringLiteral("12:30:00"), true).value() - 187.5) < 1e-9);
}

void TestSexagesimal::colonSeparatedDecDoesNotApplyHoursFactor()
{
    QVERIFY(std::abs(parseCoordinate(QStringLiteral("45:30:00"), false).value() - 45.5) < 1e-9);
}

void TestSexagesimal::negativeSexagesimalDec()
{
    QVERIFY(std::abs(parseCoordinate(QStringLiteral("-45:30:00"), false).value() - (-45.5)) < 1e-9);
}

void TestSexagesimal::explicitPlusSignSexagesimal()
{
    QVERIFY(std::abs(parseCoordinate(QStringLiteral("+45:30:00"), false).value() - 45.5) < 1e-9);
}

void TestSexagesimal::secondsAreOptional()
{
    QVERIFY(std::abs(parseCoordinate(QStringLiteral("45:30"), false).value() - 45.5) < 1e-9);
}

void TestSexagesimal::spaceSeparatedAndLetterSeparatedAreEquivalent()
{
    const double colonForm = parseCoordinate(QStringLiteral("12:34:56.7"), true).value();
    const double spaceForm = parseCoordinate(QStringLiteral("12 34 56.7"), true).value();
    const double letterForm = parseCoordinate(QStringLiteral("12h34m56.7s"), true).value();

    QCOMPARE(spaceForm, colonForm);
    QCOMPARE(letterForm, colonForm);
}

void TestSexagesimal::emptyInputIsRejected()
{
    QVERIFY(!parseCoordinate(QStringLiteral(""), true).has_value());
    QVERIFY(!parseCoordinate(QStringLiteral("   "), true).has_value());
}

void TestSexagesimal::nonNumericInputIsRejected()
{
    QVERIFY(!parseCoordinate(QStringLiteral("abc"), true).has_value());
}

void TestSexagesimal::tooManyComponentsIsRejected()
{
    QVERIFY(!parseCoordinate(QStringLiteral("12:34:56:78"), true).has_value());
}

void TestSexagesimal::outOfRangeMinutesIsRejected()
{
    QVERIFY(!parseCoordinate(QStringLiteral("12:70:00"), true).has_value());
}

void TestSexagesimal::outOfRangeSecondsIsRejected()
{
    QVERIFY(!parseCoordinate(QStringLiteral("12:30:70"), true).has_value());
}

void TestSexagesimal::qmlAdapterReturnsNanForInvalidInput()
{
    Sexagesimal adapter;
    QVERIFY(std::isnan(adapter.parseRa(QStringLiteral("not a coordinate"))));
    QCOMPARE(adapter.parseRa(QStringLiteral("12:00:00")), 180.0);
}

QTEST_MAIN(TestSexagesimal)
#include "tst_sexagesimal.moc"
