#include <QTest>
#include <QtEndian>

#include <cstdlib>

#include <fitsio.h>

#include "FitsImage.h"

using namespace fits;

namespace {

// One 80-byte FITS header card, hand-built rather than going through
// cfitsio's own writer for the "happy path" tests below - deliberately
// independent of the code under test (and of cfitsio's write API), so a
// decode bug can't be masked by a matching encode bug. See FLEN_* in
// fitsio.h for the field-length constants this mirrors.
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

// A minimal single-HDU, BITPIX=16, 2x2 image FITS file - values chosen
// to include a negative one (exercises two's-complement decoding, not
// just the trivial all-positive case).
QByteArray minimalFits2x2()
{
    QByteArray header;
    header += card("SIMPLE", "T", "conforms to FITS standard");
    header += card("BITPIX", "16", "array data type");
    header += card("NAXIS", "2", "number of array dimensions");
    header += card("NAXIS1", "2");
    header += card("NAXIS2", "2");
    header += card("OBJECT", "'TESTOBJ '", "test target name");
    header += card("END", {});
    header = padTo2880(header);

    QByteArray data;
    const qint16 values[4] = {1, 2, 3, -4};
    for (qint16 v : values) {
        const quint16 big = qToBigEndian<quint16>(static_cast<quint16>(v));
        data.append(reinterpret_cast<const char *>(&big), sizeof(big));
    }
    data = padTo2880(data);

    return header + data;
}

// A dataless primary HDU (NAXIS=0) followed by a 2x1 image extension -
// exercises FitsImage::decode()'s "skip to the first real image HDU"
// fallback, built via cfitsio's own write API (fits_create_img/
// fits_write_img) rather than hand-rolled bytes, since precisely
// hand-rolling a second-HDU byte layout (XTENSION card, PCOUNT/GCOUNT,
// exact block alignment) is exactly the kind of detail worth leaving to
// a library rather than risking a self-consistent-but-wrong fixture.
// Orthogonal to the code under test either way: this exercises cfitsio's
// write path, FitsImage::decode() only ever calls its read path.
QByteArray dataslessPrimaryWithExtension()
{
    fitsfile *fptr = nullptr;
    int status = 0;
    void *buffptr = nullptr;
    size_t buffsize = 2880;
    buffptr = malloc(buffsize);
    fits_create_memfile(&fptr, &buffptr, &buffsize, 2880, realloc, &status);

    long naxesEmpty[1] = {0};
    fits_create_img(fptr, SHORT_IMG, 0, naxesEmpty, &status);

    long naxesExt[2] = {2, 1};
    fits_create_img(fptr, SHORT_IMG, 2, naxesExt, &status);
    qint16 pixels[2] = {42, 43};
    fits_write_img(fptr, TSHORT, 1, 2, pixels, &status);

    fits_close_file(fptr, &status);

    QByteArray result(static_cast<const char *>(buffptr), static_cast<int>(buffsize));
    free(buffptr);
    return result;
}

} // namespace

class TestFitsImage : public QObject
{
    Q_OBJECT

private slots:
    void decodesDimensionsAndPixels();
    void decodesHeaderCards();
    void headerValueIsCaseInsensitiveAndEmptyWhenMissing();
    void decodeFailsOnGarbageData();
    void decodeSkipsDatalessPrimaryHdu();
};

void TestFitsImage::decodesDimensionsAndPixels()
{
    QString error;
    const std::optional<FitsImage> image = FitsImage::decode(minimalFits2x2(), &error);
    QVERIFY2(image.has_value(), qPrintable(error));

    QCOMPARE(image->width(), 2);
    QCOMPARE(image->height(), 2);
    QCOMPARE(image->pixels().size(), 4);
    QCOMPARE(image->pixels().at(0), 1.0);
    QCOMPARE(image->pixels().at(1), 2.0);
    QCOMPARE(image->pixels().at(2), 3.0);
    QCOMPARE(image->pixels().at(3), -4.0);
}

void TestFitsImage::decodesHeaderCards()
{
    const std::optional<FitsImage> image = FitsImage::decode(minimalFits2x2());
    QVERIFY(image.has_value());

    QCOMPARE(image->headerValue("BITPIX"), QStringLiteral("16"));
    QCOMPARE(image->headerValue("NAXIS1"), QStringLiteral("2"));
    QVERIFY(image->headerValue("OBJECT").contains(QStringLiteral("TESTOBJ")));

    bool foundObject = false;
    for (const HeaderCard &c : image->headerCards()) {
        if (c.keyword == QStringLiteral("OBJECT")) {
            foundObject = true;
            QCOMPARE(c.comment, QStringLiteral("test target name"));
        }
    }
    QVERIFY(foundObject);
}

void TestFitsImage::headerValueIsCaseInsensitiveAndEmptyWhenMissing()
{
    const std::optional<FitsImage> image = FitsImage::decode(minimalFits2x2());
    QVERIFY(image.has_value());

    QCOMPARE(image->headerValue("bitpix"), QStringLiteral("16"));
    QVERIFY(image->headerValue("NO-SUCH-KEYWORD").isEmpty());
}

void TestFitsImage::decodeFailsOnGarbageData()
{
    QString error;
    const std::optional<FitsImage> image = FitsImage::decode(QByteArrayLiteral("not a fits file"), &error);
    QVERIFY(!image.has_value());
    QVERIFY(!error.isEmpty());
}

void TestFitsImage::decodeSkipsDatalessPrimaryHdu()
{
    QString error;
    const std::optional<FitsImage> image = FitsImage::decode(dataslessPrimaryWithExtension(), &error);
    QVERIFY2(image.has_value(), qPrintable(error));

    QCOMPARE(image->width(), 2);
    QCOMPARE(image->height(), 1);
    QCOMPARE(image->pixels().size(), 2);
    QCOMPARE(image->pixels().at(0), 42.0);
    QCOMPARE(image->pixels().at(1), 43.0);
}

QTEST_MAIN(TestFitsImage)
#include "tst_fitsimage.moc"
