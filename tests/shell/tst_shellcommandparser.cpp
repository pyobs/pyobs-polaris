#include <QTest>

#include "ShellCommandParser.h"

using namespace shell;

class TestShellCommandParser : public QObject
{
    Q_OBJECT

private slots:
    void parsesCommandWithNoParams();
    void parsesNumberParams();
    void parsesNegativeNumberParams();
    void parsesDoubleQuotedStringParams();
    void parsesSingleQuotedStringParams();
    void parsesMixedParamTypes();
    void rejectsEmptyInput();
    void rejectsMissingDot();
    void rejectsMissingParens();
    void rejectsTrailingComma();
    void rejectsTrailingGarbageAfterClose();
    void rejectsDoubleNegation();
    void rejectsUnaryMinusBeforeString();
    void rejectsUnterminatedString();
    void rejectsMalformedNumber();
};

void TestShellCommandParser::parsesCommandWithNoParams()
{
    const auto result = ShellCommandParser::parse(QStringLiteral("roof.init()"));
    QVERIFY(result.has_value());
    QCOMPARE(result->module, QStringLiteral("roof"));
    QCOMPARE(result->command, QStringLiteral("init"));
    QVERIFY(result->params.isEmpty());
}

void TestShellCommandParser::parsesNumberParams()
{
    const auto result = ShellCommandParser::parse(QStringLiteral("telescope.move_altaz(45, 180.5)"));
    QVERIFY(result.has_value());
    QCOMPARE(result->params.size(), 2);
    QCOMPARE(result->params.at(0).toDouble(), 45.0);
    QCOMPARE(result->params.at(1).toDouble(), 180.5);
}

void TestShellCommandParser::parsesNegativeNumberParams()
{
    const auto result = ShellCommandParser::parse(QStringLiteral("telescope.move_altaz(-12.5, 180)"));
    QVERIFY(result.has_value());
    QCOMPARE(result->params.size(), 2);
    QCOMPARE(result->params.at(0).toDouble(), -12.5);
    QCOMPARE(result->params.at(1).toDouble(), 180.0);
}

void TestShellCommandParser::parsesDoubleQuotedStringParams()
{
    const auto result = ShellCommandParser::parse(QStringLiteral("mode.set_mode(\"Size\", \"Fast\")"));
    QVERIFY(result.has_value());
    QCOMPARE(result->params.size(), 2);
    QCOMPARE(result->params.at(0).toString(), QStringLiteral("Size"));
    QCOMPARE(result->params.at(1).toString(), QStringLiteral("Fast"));
}

void TestShellCommandParser::parsesSingleQuotedStringParams()
{
    // Deliberate fix vs. the Python original - see ShellCommandParser.h's
    // doc comment: single-quoted strings there keep their quotes attached.
    const auto result = ShellCommandParser::parse(QStringLiteral("mode.set_mode('Size', 'Fast')"));
    QVERIFY(result.has_value());
    QCOMPARE(result->params.size(), 2);
    QCOMPARE(result->params.at(0).toString(), QStringLiteral("Size"));
    QCOMPARE(result->params.at(1).toString(), QStringLiteral("Fast"));
}

void TestShellCommandParser::parsesMixedParamTypes()
{
    const auto result = ShellCommandParser::parse(QStringLiteral("mode.set_mode(\"Size\", -3, 4.2)"));
    QVERIFY(result.has_value());
    QCOMPARE(result->params.size(), 3);
    QCOMPARE(result->params.at(0).toString(), QStringLiteral("Size"));
    QCOMPARE(result->params.at(1).toDouble(), -3.0);
    QCOMPARE(result->params.at(2).toDouble(), 4.2);
}

void TestShellCommandParser::rejectsEmptyInput()
{
    QVERIFY(!ShellCommandParser::parse(QString()).has_value());
}

void TestShellCommandParser::rejectsMissingDot()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("roof init()")).has_value());
}

void TestShellCommandParser::rejectsMissingParens()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("roof.init")).has_value());
}

void TestShellCommandParser::rejectsTrailingComma()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("mode.set_mode(\"Size\",)")).has_value());
}

void TestShellCommandParser::rejectsTrailingGarbageAfterClose()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("roof.init() extra")).has_value());
}

void TestShellCommandParser::rejectsDoubleNegation()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("telescope.move_altaz(--12.5, 180)")).has_value());
}

void TestShellCommandParser::rejectsUnaryMinusBeforeString()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("mode.set_mode(-\"Fast\")")).has_value());
}

void TestShellCommandParser::rejectsUnterminatedString()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("mode.set_mode(\"Fast)")).has_value());
}

void TestShellCommandParser::rejectsMalformedNumber()
{
    QVERIFY(!ShellCommandParser::parse(QStringLiteral("telescope.move_altaz(1., 180)")).has_value());
}

QTEST_MAIN(TestShellCommandParser)
#include "tst_shellcommandparser.moc"
