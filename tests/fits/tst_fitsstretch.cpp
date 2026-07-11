#include <QTest>
#include <limits>

#include "FitsStretch.h"

using namespace fits;

class TestFitsStretch : public QObject
{
    Q_OBJECT

private slots:
    void percentileHundredUsesLiteralExtremes();
    void percentileClipsSymmetricTails();
    void nonFiniteValuesAreIgnored();
    void nonPositiveValuesAreIgnored();
    void emptyOrAllNonFiniteReturnsDefault();
    void renderMapsBlackAndWhite();
    void renderFlipsFitsRowOrder();
    void renderHandlesFlatImage();
    void renderReturnsNullOnSizeMismatch();
    void renderSqrtBrightensMidtonesRelativeToLinear();
    void renderSquaredDarkensMidtonesRelativeToLinear();
    void renderReversedColormapInvertsGray();
    void renderHotColormapEndpointsAreBlackAndWhite();
    void renderJetColormapIsBlueAtBlackAndDarkRedAtWhite();
    void applyTrimSecZeroesOutsideRectangle();
    void applyTrimSecIgnoresMissingOrMalformedHeader();
    void applyTrimSecHandlesQuotedRawHeaderValue();

private:
    static QVector<double> minimal4x4();
};

QVector<double> TestFitsStretch::minimal4x4()
{
    // 4x4, values 0..15 row-major (FITS row order, row 0 = bottom).
    QVector<double> pixels;
    for (int i = 0; i < 16; ++i) {
        pixels.append(static_cast<double>(i));
    }
    return pixels;
}

void TestFitsStretch::percentileHundredUsesLiteralExtremes()
{
    const QVector<double> pixels = {5.0, 1.0, 9.0, 3.0};
    const StretchLimits limits = computeStretch(pixels, StretchMode::Percentile, 100.0);
    QCOMPARE(limits.black, 1.0);
    QCOMPARE(limits.white, 9.0);
}

void TestFitsStretch::percentileClipsSymmetricTails()
{
    // Values 1..1000 inclusive (1000 of them - deliberately starting at
    // 1, not 0, since 0 itself is now excluded by the non-positive
    // filter, see nonPositiveValuesAreIgnored()). percentile=98 discards
    // 2% total, 1% per tail: clipFraction = (100-98)/100/2 = 0.01, so
    // lowIdx = 0.01 * 999 = 9 (rounded down), highIdx = 0.99 * 999 = 989.
    QVector<double> pixels;
    for (int i = 1; i <= 1000; ++i) {
        pixels.append(static_cast<double>(i));
    }
    const StretchLimits limits = computeStretch(pixels, StretchMode::Percentile, 98.0);
    QCOMPARE(limits.black, 10.0);
    QCOMPARE(limits.white, 990.0);
}

void TestFitsStretch::nonFiniteValuesAreIgnored()
{
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double inf = std::numeric_limits<double>::infinity();
    const QVector<double> pixels = {nan, 2.0, inf, 8.0, -inf};
    const StretchLimits limits = computeStretch(pixels, StretchMode::Percentile, 100.0);
    QCOMPARE(limits.black, 2.0);
    QCOMPARE(limits.white, 8.0);
}

void TestFitsStretch::nonPositiveValuesAreIgnored()
{
    // Zero and negative pixels are excluded from cut computation
    // entirely (see computeStretch()'s own header comment for why this
    // matches qfitswidget, and pairs with applyTrimSec()'s zero-fill) -
    // 0.0 and -3.0 here must not become the black level just because
    // they're the smallest finite values present.
    const QVector<double> pixels = {0.0, -3.0, 2.0, 8.0};
    const StretchLimits limits = computeStretch(pixels, StretchMode::Percentile, 100.0);
    QCOMPARE(limits.black, 2.0);
    QCOMPARE(limits.white, 8.0);
}

void TestFitsStretch::emptyOrAllNonFiniteReturnsDefault()
{
    const StretchLimits empty = computeStretch({}, StretchMode::Percentile, 100.0);
    QCOMPARE(empty.black, 0.0);
    QCOMPARE(empty.white, 1.0);

    const double nan = std::numeric_limits<double>::quiet_NaN();
    const StretchLimits allNan = computeStretch({nan, nan}, StretchMode::Percentile);
    QCOMPARE(allNan.black, 0.0);
    QCOMPARE(allNan.white, 1.0);
}

void TestFitsStretch::renderMapsBlackAndWhite()
{
    const QVector<double> pixels = {0.0, 5.0, 10.0, 2.5};
    const QImage image = render(pixels, 2, 2, {0.0, 10.0});
    QVERIFY(!image.isNull());
    QCOMPARE(image.format(), QImage::Format_RGB32);
    // Row 0 (FITS bottom) ends up at QImage row 1 (bottom-to-top flip) -
    // see renderFlipsFitsRowOrder() for a more targeted check of that
    // specifically; here just confirm the value mapping is linear
    // (default args: Linear curve, Gray colormap).
    bool sawZero = false;
    bool sawFull = false;
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            const int v = qGray(image.pixel(x, y));
            if (v == 0) {
                sawZero = true;
            }
            if (v == 255) {
                sawFull = true;
            }
        }
    }
    QVERIFY(sawZero);
    QVERIFY(sawFull);
}

void TestFitsStretch::renderFlipsFitsRowOrder()
{
    // 1x2 image: FITS row 0 (bottom) = 0.0 (black), FITS row 1 (top) =
    // 10.0 (white) - QImage row 0 (top) must show the FITS *top* row,
    // i.e. white.
    const QVector<double> pixels = {0.0, 10.0};
    const QImage image = render(pixels, 1, 2, {0.0, 10.0});
    QVERIFY(!image.isNull());
    QCOMPARE(qGray(image.pixel(0, 0)), 255);
    QCOMPARE(qGray(image.pixel(0, 1)), 0);
}

void TestFitsStretch::renderHandlesFlatImage()
{
    const QVector<double> pixels = {4.0, 4.0, 4.0, 4.0};
    const QImage image = render(pixels, 2, 2, {4.0, 4.0});
    QVERIFY(!image.isNull());
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            QCOMPARE(qGray(image.pixel(x, y)), 128);
        }
    }
}

void TestFitsStretch::renderReturnsNullOnSizeMismatch()
{
    const QVector<double> pixels = {1.0, 2.0, 3.0};
    QVERIFY(render(pixels, 2, 2, {0.0, 1.0}).isNull());
}

void TestFitsStretch::renderSqrtBrightensMidtonesRelativeToLinear()
{
    // A 25%-of-range pixel: sqrt(0.25) = 0.5, twice as bright as the
    // linear mapping's own 0.25 - the whole point of a sqrt stretch.
    const QVector<double> pixels = {2.5};
    const QImage linearImage = render(pixels, 1, 1, {0.0, 10.0}, ToneCurve::Linear);
    const QImage sqrtImage = render(pixels, 1, 1, {0.0, 10.0}, ToneCurve::Sqrt);
    QVERIFY(qGray(sqrtImage.pixel(0, 0)) > qGray(linearImage.pixel(0, 0)));
}

void TestFitsStretch::renderSquaredDarkensMidtonesRelativeToLinear()
{
    const QVector<double> pixels = {2.5};
    const QImage linearImage = render(pixels, 1, 1, {0.0, 10.0}, ToneCurve::Linear);
    const QImage squaredImage = render(pixels, 1, 1, {0.0, 10.0}, ToneCurve::Squared);
    QVERIFY(qGray(squaredImage.pixel(0, 0)) < qGray(linearImage.pixel(0, 0)));
}

void TestFitsStretch::renderReversedColormapInvertsGray()
{
    const QVector<double> pixels = {0.0, 10.0};
    const QImage normal = render(pixels, 2, 1, {0.0, 10.0}, ToneCurve::Linear, Colormap::Gray, false);
    const QImage reversed = render(pixels, 2, 1, {0.0, 10.0}, ToneCurve::Linear, Colormap::Gray, true);
    QCOMPARE(qGray(normal.pixel(0, 0)), 0);
    QCOMPARE(qGray(reversed.pixel(0, 0)), 255);
    QCOMPARE(qGray(normal.pixel(1, 0)), 255);
    QCOMPARE(qGray(reversed.pixel(1, 0)), 0);
}

void TestFitsStretch::renderHotColormapEndpointsAreBlackAndWhite()
{
    const QVector<double> pixels = {0.0, 10.0};
    const QImage image = render(pixels, 2, 1, {0.0, 10.0}, ToneCurve::Linear, Colormap::Hot);
    QCOMPARE(image.pixel(0, 0), qRgb(0, 0, 0));
    QCOMPARE(image.pixel(1, 0), qRgb(255, 255, 255));
}

void TestFitsStretch::renderJetColormapIsBlueAtBlackAndDarkRedAtWhite()
{
    const QVector<double> pixels = {0.0, 10.0};
    const QImage image = render(pixels, 2, 1, {0.0, 10.0}, ToneCurve::Linear, Colormap::Jet);
    QCOMPARE(image.pixel(0, 0), qRgb(0, 0, 143));
    QCOMPARE(image.pixel(1, 0), qRgb(128, 0, 0));
}

void TestFitsStretch::applyTrimSecZeroesOutsideRectangle()
{
    // TRIMSEC "[2:3,2:3]" (1-based inclusive) on a 4x4 image keeps only
    // the inner 2x2 (columns/rows 2..3, i.e. 0-based indices 1..2).
    const QVector<double> pixels = minimal4x4();
    const QVector<double> trimmed = applyTrimSec(pixels, 4, 4, QStringLiteral("[2:3,2:3]"));

    QCOMPARE(trimmed.size(), pixels.size());
    for (int y = 0; y < 4; ++y) {
        for (int x = 0; x < 4; ++x) {
            const double value = trimmed[y * 4 + x];
            const bool inside = x >= 1 && x <= 2 && y >= 1 && y <= 2;
            if (inside) {
                QCOMPARE(value, pixels[y * 4 + x]);
            } else {
                QCOMPARE(value, 0.0);
            }
        }
    }
}

void TestFitsStretch::applyTrimSecIgnoresMissingOrMalformedHeader()
{
    const QVector<double> pixels = minimal4x4();
    QCOMPARE(applyTrimSec(pixels, 4, 4, QString()), pixels);
    QCOMPARE(applyTrimSec(pixels, 4, 4, QStringLiteral("not a trimsec")), pixels);
    QCOMPARE(applyTrimSec(pixels, 4, 4, QStringLiteral("[1:2]")), pixels);
}

void TestFitsStretch::applyTrimSecHandlesQuotedRawHeaderValue()
{
    // fits::FitsImage::headerValue() hands back the raw on-disk value for
    // a FITS string keyword - still single-quoted, e.g.
    // `'[2:3,2:3]'`, not `[2:3,2:3]` - applyTrimSec() must tolerate that
    // form directly, not just the already-unquoted one every other test
    // here uses.
    const QVector<double> pixels = minimal4x4();
    const QVector<double> quoted = applyTrimSec(pixels, 4, 4, QStringLiteral("'[2:3,2:3]'"));
    const QVector<double> unquoted = applyTrimSec(pixels, 4, 4, QStringLiteral("[2:3,2:3]"));
    QCOMPARE(quoted, unquoted);
    QVERIFY(quoted != pixels);
}

QTEST_MAIN(TestFitsStretch)
#include "tst_fitsstretch.moc"
