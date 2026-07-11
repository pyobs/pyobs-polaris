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

// 4x4 BITPIX=16 fixture with a TRIMSEC header keeping only the inner
// 2x2 (columns/rows 2..3, 1-based) - for exercising
// FitsImageItem::trimSecEnabled() end to end (see
// tst_fitsstretch.cpp's applyTrimSecZeroesOutsideRectangle() for the
// pure-function version of the same math).
QByteArray fits4x4WithTrimSec()
{
    QByteArray header;
    header += card("SIMPLE", "T");
    header += card("BITPIX", "16");
    header += card("NAXIS", "2");
    header += card("NAXIS1", "4");
    header += card("NAXIS2", "4");
    header += card("TRIMSEC", "'[2:3,2:3]'");
    header += card("END", {});
    header = padTo2880(header);

    QByteArray data;
    for (qint16 v = 0; v < 16; ++v) {
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
    void changingPercentileRecomputesLevels();
    void defaultStretchModeIsPercentileAt99Point9();
    void setManualLimitsSwitchesToCustomAndUsesExactLevels();
    void manualLimitsPersistAcrossNewImage();
    void switchingAwayFromCustomRecomputesLevels();
    void enterCustomModeFreezesCurrentLevelsWithoutRecomputing();
    void toneCurveDefaultsToLinearAndCanBeChanged();
    void colormapDefaultsToGrayAndCanBeChanged();
    void reversedColormapDefaultsToFalse();
    void trimSecDefaultsToEnabledAndAffectsLevels();
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
    // 100% percentile, not the 99.9% default - percentile clipping on a
    // 4-pixel image legitimately truncates the top value (see
    // tst_fitsstretch.cpp for percentile math itself); this test is
    // about property wiring on load, not stretch-mode arithmetic.
    // percentile=100 is exactly the literal min/max.
    item.setPercentilePreset(100.0);
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
}

void TestFitsImageItem::changingPercentileRecomputesLevels()
{
    FitsImageItem item;
    item.setPercentilePreset(100.0);
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 4.0);

    QSignalSpy imageChangedSpy(&item, &FitsImageItem::imageChanged);
    item.setPercentilePreset(95.0);
    QCOMPARE(item.stretchMode(), QStringLiteral("percentile"));
    QCOMPARE(item.percentile(), 95.0);
    QVERIFY(imageChangedSpy.count() >= 1);
}

void TestFitsImageItem::defaultStretchModeIsPercentileAt99Point9()
{
    FitsImageItem item;
    QCOMPARE(item.stretchMode(), QStringLiteral("percentile"));
    QCOMPARE(item.percentile(), 99.9);
}

void TestFitsImageItem::setManualLimitsSwitchesToCustomAndUsesExactLevels()
{
    FitsImageItem item;
    item.setPercentilePreset(100.0);
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 4.0);

    QSignalSpy stretchModeChangedSpy(&item, &FitsImageItem::stretchModeChanged);
    item.setManualLimits(0.0, 10.0);

    QCOMPARE(item.stretchMode(), QStringLiteral("custom"));
    QCOMPARE(item.blackLevel(), 0.0);
    QCOMPARE(item.whiteLevel(), 10.0);
    QCOMPARE(stretchModeChangedSpy.count(), 1);
}

void TestFitsImageItem::manualLimitsPersistAcrossNewImage()
{
    FitsImageItem item;
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));
    item.setManualLimits(-5.0, 5.0);

    // A second load (e.g. a fresh exposure) must not silently recompute
    // levels out from under a manually-set custom cut - that's exactly
    // what stretchMode "custom" is for, see FitsImageItem.h's comment.
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));

    QCOMPARE(item.stretchMode(), QStringLiteral("custom"));
    QCOMPARE(item.blackLevel(), -5.0);
    QCOMPARE(item.whiteLevel(), 5.0);
}

void TestFitsImageItem::switchingAwayFromCustomRecomputesLevels()
{
    FitsImageItem item;
    item.setPercentilePreset(100.0);
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));
    item.setManualLimits(-100.0, 100.0);
    QCOMPARE(item.blackLevel(), -100.0);

    item.setPercentilePreset(100.0);

    QCOMPARE(item.stretchMode(), QStringLiteral("percentile"));
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 4.0);
}

void TestFitsImageItem::enterCustomModeFreezesCurrentLevelsWithoutRecomputing()
{
    // Selecting "Custom" from the combo alone (no Lo/Hi edit yet) must
    // leave the currently-shown levels exactly as they were - matches
    // qfitswidget's own comboCuts "Custom" entry, which doesn't reset
    // spinLoCut/spinHiCut.
    FitsImageItem item;
    item.setPercentilePreset(100.0);
    QVERIFY(item.loadFitsBytes(minimalFits2x2()));
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 4.0);

    item.enterCustomMode();

    QCOMPARE(item.stretchMode(), QStringLiteral("custom"));
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 4.0);
}

void TestFitsImageItem::toneCurveDefaultsToLinearAndCanBeChanged()
{
    FitsImageItem item;
    QCOMPARE(item.toneCurve(), QStringLiteral("linear"));

    QSignalSpy toneCurveChangedSpy(&item, &FitsImageItem::toneCurveChanged);
    item.setToneCurve(QStringLiteral("sqrt"));
    QCOMPARE(item.toneCurve(), QStringLiteral("sqrt"));
    QCOMPARE(toneCurveChangedSpy.count(), 1);

    // Setting the same value again must not re-signal.
    item.setToneCurve(QStringLiteral("sqrt"));
    QCOMPARE(toneCurveChangedSpy.count(), 1);
}

void TestFitsImageItem::colormapDefaultsToGrayAndCanBeChanged()
{
    FitsImageItem item;
    QCOMPARE(item.colormap(), QStringLiteral("gray"));

    QSignalSpy colormapChangedSpy(&item, &FitsImageItem::colormapChanged);
    item.setColormap(QStringLiteral("viridis"));
    QCOMPARE(item.colormap(), QStringLiteral("viridis"));
    QCOMPARE(colormapChangedSpy.count(), 1);
}

void TestFitsImageItem::reversedColormapDefaultsToFalse()
{
    FitsImageItem item;
    QCOMPARE(item.reversedColormap(), false);

    QSignalSpy reversedChangedSpy(&item, &FitsImageItem::reversedColormapChanged);
    item.setReversedColormap(true);
    QCOMPARE(item.reversedColormap(), true);
    QCOMPARE(reversedChangedSpy.count(), 1);
}

void TestFitsImageItem::trimSecDefaultsToEnabledAndAffectsLevels()
{
    FitsImageItem item;
    QCOMPARE(item.trimSecEnabled(), true);

    item.setPercentilePreset(100.0);
    QVERIFY(item.loadFitsBytes(fits4x4WithTrimSec()));

    // TRIMSEC keeps only values 5,6,9,10 (the inner 2x2 of 0..15, see
    // tst_fitsstretch.cpp's own trimsec math) - min/max of *those*, not
    // the full frame's 0/15.
    QCOMPARE(item.blackLevel(), 5.0);
    QCOMPARE(item.whiteLevel(), 10.0);

    item.setTrimSecEnabled(false);
    // Full frame is 0..15 - but computeStretch() excludes non-positive
    // pixels (see its own comment), so the one legitimate 0-valued pixel
    // is skipped too: black is 1.0, not 0.0.
    QCOMPARE(item.blackLevel(), 1.0);
    QCOMPARE(item.whiteLevel(), 15.0);
}

QTEST_MAIN(TestFitsImageItem)
#include "tst_fitsimageitem.moc"
