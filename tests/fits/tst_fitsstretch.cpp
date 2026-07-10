#include <QTest>
#include <limits>

#include "FitsStretch.h"

using namespace fits;

class TestFitsStretch : public QObject
{
    Q_OBJECT

private slots:
    void minMaxUsesLiteralExtremes();
    void percentileClipsSymmetricTails();
    void nonFiniteValuesAreIgnored();
    void emptyOrAllNonFiniteReturnsDefault();
    void renderGrayscaleMapsBlackAndWhite();
    void renderGrayscaleFlipsFitsRowOrder();
    void renderGrayscaleHandlesFlatImage();
    void renderGrayscaleReturnsNullOnSizeMismatch();
};

void TestFitsStretch::minMaxUsesLiteralExtremes()
{
    const QVector<double> pixels = {5.0, 1.0, 9.0, 3.0};
    const StretchLimits limits = computeStretch(pixels, StretchMode::MinMax);
    QCOMPARE(limits.black, 1.0);
    QCOMPARE(limits.white, 9.0);
}

void TestFitsStretch::percentileClipsSymmetricTails()
{
    // Values 0..1000 inclusive (1001 of them). percentile=98 discards 2%
    // total, 1% per tail: clipFraction = (100-98)/100/2 = 0.01, so
    // lowIdx = 0.01 * 1000 = 10, highIdx = 0.99 * 1000 = 990.
    QVector<double> pixels;
    for (int i = 0; i <= 1000; ++i) {
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
    const StretchLimits limits = computeStretch(pixels, StretchMode::MinMax);
    QCOMPARE(limits.black, 2.0);
    QCOMPARE(limits.white, 8.0);
}

void TestFitsStretch::emptyOrAllNonFiniteReturnsDefault()
{
    const StretchLimits empty = computeStretch({}, StretchMode::MinMax);
    QCOMPARE(empty.black, 0.0);
    QCOMPARE(empty.white, 1.0);

    const double nan = std::numeric_limits<double>::quiet_NaN();
    const StretchLimits allNan = computeStretch({nan, nan}, StretchMode::Percentile);
    QCOMPARE(allNan.black, 0.0);
    QCOMPARE(allNan.white, 1.0);
}

void TestFitsStretch::renderGrayscaleMapsBlackAndWhite()
{
    const QVector<double> pixels = {0.0, 5.0, 10.0, 2.5};
    const QImage image = renderGrayscale(pixels, 2, 2, {0.0, 10.0});
    QVERIFY(!image.isNull());
    QCOMPARE(image.format(), QImage::Format_Grayscale8);
    // Row 0 (FITS bottom) ends up at QImage row 1 (bottom-to-top flip) -
    // see renderGrayscaleFlipsFitsRowOrder() for a more targeted check of
    // that specifically; here just confirm the value mapping is linear.
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

void TestFitsStretch::renderGrayscaleFlipsFitsRowOrder()
{
    // 1x2 image: FITS row 0 (bottom) = 0.0 (black), FITS row 1 (top) =
    // 10.0 (white) - QImage row 0 (top) must show the FITS *top* row,
    // i.e. white.
    const QVector<double> pixels = {0.0, 10.0};
    const QImage image = renderGrayscale(pixels, 1, 2, {0.0, 10.0});
    QVERIFY(!image.isNull());
    QCOMPARE(qGray(image.pixel(0, 0)), 255);
    QCOMPARE(qGray(image.pixel(0, 1)), 0);
}

void TestFitsStretch::renderGrayscaleHandlesFlatImage()
{
    const QVector<double> pixels = {4.0, 4.0, 4.0, 4.0};
    const QImage image = renderGrayscale(pixels, 2, 2, {4.0, 4.0});
    QVERIFY(!image.isNull());
    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            QCOMPARE(qGray(image.pixel(x, y)), 128);
        }
    }
}

void TestFitsStretch::renderGrayscaleReturnsNullOnSizeMismatch()
{
    const QVector<double> pixels = {1.0, 2.0, 3.0};
    QVERIFY(renderGrayscale(pixels, 2, 2, {0.0, 1.0}).isNull());
}

QTEST_MAIN(TestFitsStretch)
#include "tst_fitsstretch.moc"
