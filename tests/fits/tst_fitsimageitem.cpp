#include <QSignalSpy>
#include <QTest>
#include <QtEndian>

#include "FitsImageItem.h"

using namespace fits;

namespace {

QByteArray card(const QByteArray &keyword, const QByteArray &value, const QByteArray &comment = {})
{
    QByteArray line = keyword.leftJustified(8, ' ').left(8);
    if (!value.isEmpty()) {
        line += "= ";
        line += value;
        if (!comment.isEmpty()) {
            line += " / ";
            line += comment;
        }
    }
    return line.leftJustified(80, ' ').left(80);
}

QByteArray padTo2880(const QByteArray &block)
{
    QByteArray padded = block;
    const int remainder = padded.size() % 2880;
    if (remainder != 0) {
        padded += QByteArray(2880 - remainder, ' ');
    }
    return padded;
}

// Same minimal 2x2 BITPIX=16 fixture as tst_fitsimage.cpp - duplicated
// rather than shared, matching this project's existing per-test-binary
// fixture-building convention (no shared test helper library, see
// tests/CMakeLists.txt's own header comment).
QByteArray minimalFits2x2()
{
    QByteArray header;
    header += card("SIMPLE", "T");
    header += card("BITPIX", "16");
    header += card("NAXIS", "2");
    header += card("NAXIS1", "2");
    header += card("NAXIS2", "2");
    header += card("END", {});
    header = padTo2880(header);

    QByteArray data;
    const qint16 values[4] = {1, 2, 3, 4};
    for (qint16 v : values) {
        const quint16 big = qToBigEndian<quint16>(static_cast<quint16>(v));
        data.append(reinterpret_cast<const char *>(&big), sizeof(big));
    }
    return header + padTo2880(data);
}

} // namespace

class TestFitsImageItem : public QObject
{
    Q_OBJECT

private slots:
    void startsWithNoImage();
    void loadFitsBytesSucceedsAndUpdatesProperties();
    void loadFitsBytesFailureKeepsPreviousImageAndSetsError();
    void changingStretchModeRecomputesLevels();
    void defaultStretchModeIsPercentile();
};

void TestFitsImageItem::startsWithNoImage()
{
    FitsImageItem item;
    QCOMPARE(item.hasImage(), false);
    QCOMPARE(item.imageWidth(), 0);
    QCOMPARE(item.imageHeight(), 0);
    QVERIFY(item.lastError().isEmpty());
}

void TestFitsImageItem::loadFitsBytesSucceedsAndUpdatesProperties()
{
    FitsImageItem item;
    // minmax, not the percentile default - percentile clipping on a
    // 4-pixel image legitimately truncates the top value (see
    // tst_fitsstretch.cpp for percentile math itself); this test is
    // about property wiring on load, not stretch-mode arithmetic.
    item.setStretchMode(QStringLiteral("minmax"));
    QSignalSpy imageChangedSpy(&item, &FitsImageItem::imageChanged);

    QVERIFY(item.loadFitsBytes(minimalFits2x2()));

    QCOMPARE(item.hasImage(), true);
    QCOMPARE(item.imageWidth(), 2);
    QCOMPARE(item.imageHeight(), 2);
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 4.0);
    QVERIFY(item.lastError().isEmpty());
    QVERIFY(imageChangedSpy.count() >= 1);
}

void TestFitsImageItem::loadFitsBytesFailureKeepsPreviousImageAndSetsError()
{
    FitsImageItem item;
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));

    QVERIFY(!item.loadFitsBytes(QByteArrayLiteral("not a fits file")));

    QVERIFY(!item.lastError().isEmpty());
    // The previously-successful image must still be showing - a single
    // bad fetch shouldn't blank the last good frame.
    QCOMPARE(item.hasImage(), true);
    QCOMPARE(item.imageWidth(), 2);
    QCOMPARE(item.blackLevel(), 1.0);
}

void TestFitsImageItem::changingStretchModeRecomputesLevels()
{
    FitsImageItem item;
    item.setStretchMode(QStringLiteral("minmax"));
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 4.0);

    QSignalSpy imageChangedSpy(&item, &FitsImageItem::imageChanged);
    item.setStretchMode(QStringLiteral("percentile"));
    QCOMPARE(item.stretchMode(), QStringLiteral("percentile"));
    QVERIFY(imageChangedSpy.count() >= 1);
}

void TestFitsImageItem::defaultStretchModeIsPercentile()
{
    FitsImageItem item;
    QCOMPARE(item.stretchMode(), QStringLiteral("percentile"));
}

QTEST_MAIN(TestFitsImageItem)
#include "tst_fitsimageitem.moc"
