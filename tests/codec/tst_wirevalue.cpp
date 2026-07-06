#include <QDomDocument>
#include <QTest>

#include "Decode.h"

using namespace codec;

namespace {

QDomElement parseElement(const QString &xml)
{
    QDomDocument doc;
    doc.setContent(xml);
    return doc.documentElement();
}

}

class TestWireValueDecode : public QObject
{
    Q_OBJECT

private slots:
    void nil();
    void boolean();
    void integer();
    void floatingPoint();
    void string();
    void itemsList();
    void tupleIsSameAsItems();
    void dict();
    void nestedListInsideDict();
    void dataclassRoot();
};

void TestWireValueDecode::nil()
{
    QVERIFY(xmlToValue(parseElement("<nil/>")).isNull());
}

void TestWireValueDecode::boolean()
{
    QVERIFY(xmlToValue(parseElement("<boolean>true</boolean>")).toBool());
    QVERIFY(!xmlToValue(parseElement("<boolean>false</boolean>")).toBool());
}

void TestWireValueDecode::integer()
{
    QCOMPARE(xmlToValue(parseElement("<int>42</int>")).toInt(), 42);
    QCOMPARE(xmlToValue(parseElement("<int>-7</int>")).toInt(), -7);
}

void TestWireValueDecode::floatingPoint()
{
    QCOMPARE(xmlToValue(parseElement("<double>3.5</double>")).toDouble(), 3.5);
}

void TestWireValueDecode::string()
{
    QCOMPARE(xmlToValue(parseElement("<string>hello</string>")).toString(), QStringLiteral("hello"));
}

void TestWireValueDecode::itemsList()
{
    const WireValue v = xmlToValue(parseElement(
        "<items>"
        "<item><int>1</int></item>"
        "<item><int>2</int></item>"
        "<item><nil/></item>"
        "</items>"));
    QVERIFY(v.isList());
    const WireList &list = v.toList();
    QCOMPARE(list.size(), size_t(3));
    QCOMPARE(list[0].toInt(), 1);
    QCOMPARE(list[1].toInt(), 2);
    QVERIFY(list[2].isNull());
}

void TestWireValueDecode::tupleIsSameAsItems()
{
    const WireValue v = xmlToValue(parseElement(
        "<tuple><item><string>a</string></item><item><string>b</string></item></tuple>"));
    QVERIFY(v.isList());
    QCOMPARE(v.toList().size(), size_t(2));
    QCOMPARE(v.toList()[0].toString(), QStringLiteral("a"));
    QCOMPARE(v.toList()[1].toString(), QStringLiteral("b"));
}

void TestWireValueDecode::dict()
{
    const WireValue v = xmlToValue(parseElement(
        "<dict>"
        "<entry><key><string>b</string></key><val><int>2</int></val></entry>"
        "<entry><key><string>a</string></key><val><int>1</int></val></entry>"
        "</dict>"));
    QVERIFY(v.isDict());
    const WireDict &dict = v.toDict();
    QCOMPARE(dict.size(), size_t(2));
    // Wire/declaration order must be preserved, not sorted alphabetically -
    // this is the whole reason WireValue doesn't use QVariantMap.
    QCOMPARE(dict[0].first, QStringLiteral("b"));
    QCOMPARE(dict[0].second.toInt(), 2);
    QCOMPARE(dict[1].first, QStringLiteral("a"));
    QCOMPARE(dict[1].second.toInt(), 1);
}

void TestWireValueDecode::nestedListInsideDict()
{
    const WireValue v = xmlToValue(parseElement(
        "<dict>"
        "<entry><key><string>values</string></key><val>"
        "<items><item><int>1</int></item><item><int>2</int></item></items>"
        "</val></entry>"
        "</dict>"));
    const WireDict &dict = v.toDict();
    QCOMPARE(dict.size(), size_t(1));
    QCOMPARE(dict[0].first, QStringLiteral("values"));
    QVERIFY(dict[0].second.isList());
    QCOMPARE(dict[0].second.toList().size(), size_t(2));
    QCOMPARE(dict[0].second.toList()[0].toInt(), 1);
    QCOMPARE(dict[0].second.toList()[1].toInt(), 2);
}

void TestWireValueDecode::dataclassRoot()
{
    // Synthetic dataclass-shaped fixture (e.g. an ICooling-like state block):
    // a root tag with one child element per field, each wrapping exactly
    // one more self-tagged value - the "default case" of xmlToValue.
    const WireValue v = xmlToValue(parseElement(
        "<CoolingState>"
        "<temperature><double>-20.5</double></temperature>"
        "<enabled><boolean>true</boolean></enabled>"
        "<setpoint><nil/></setpoint>"
        "</CoolingState>"));
    QVERIFY(v.isDict());
    const WireDict &fields = v.toDict();
    QCOMPARE(fields.size(), size_t(3));
    QCOMPARE(fields[0].first, QStringLiteral("temperature"));
    QCOMPARE(fields[0].second.toDouble(), -20.5);
    QCOMPARE(fields[1].first, QStringLiteral("enabled"));
    QVERIFY(fields[1].second.toBool());
    QCOMPARE(fields[2].first, QStringLiteral("setpoint"));
    QVERIFY(fields[2].second.isNull());
}

QTEST_MAIN(TestWireValueDecode)
#include "tst_wirevalue.moc"
