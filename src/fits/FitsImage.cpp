#include "FitsImage.h"

#include <fitsio.h>

namespace fits {

namespace {

QString cfitsioErrorMessage(int status)
{
    char text[FLEN_ERRMSG] = {0};
    fits_get_errstatus(status, text);
    return QString::fromLatin1(text);
}

} // namespace

QString FitsImage::headerValue(const QString &keyword) const
{
    for (const HeaderCard &card : m_headerCards) {
        if (card.keyword.compare(keyword, Qt::CaseInsensitive) == 0) {
            return card.value;
        }
    }
    return {};
}

std::optional<FitsImage> FitsImage::decode(const QByteArray &data, QString *errorMessage)
{
    auto fail = [&](const QString &message) -> std::optional<FitsImage> {
        if (errorMessage) {
            *errorMessage = message;
        }
        return std::nullopt;
    };

    // READONLY: cfitsio's mem_realloc callback is only ever invoked to
    // grow the buffer for a write, so passing nullptr here is safe -
    // it's simply never called. buffptr points directly into `data`'s
    // own storage (no copy) - safe since decode() is synchronous and
    // `data` outlives every cfitsio call below.
    fitsfile *fptr = nullptr;
    int status = 0;
    void *buffptr = const_cast<char *>(data.constData());
    size_t buffsize = static_cast<size_t>(data.size());
    if (fits_open_memfile(&fptr, "", READONLY, &buffptr, &buffsize, 0, nullptr, &status)) {
        return fail(cfitsioErrorMessage(status));
    }

    // Find the first HDU that's actually a 2D image with real data - see
    // this class's own header comment on why a dataless primary HDU is
    // skipped rather than assumed away.
    int numHdus = 0;
    fits_get_num_hdus(fptr, &numHdus, &status);

    bool found = false;
    int naxis = 0;
    long naxes[2] = {0, 0};
    for (int hdu = 1; hdu <= numHdus && !found; ++hdu) {
        int hduType = 0;
        status = 0;
        if (fits_movabs_hdu(fptr, hdu, &hduType, &status)) {
            break;
        }
        if (hduType != IMAGE_HDU) {
            continue;
        }
        int imgtype = 0;
        status = 0;
        if (fits_get_img_param(fptr, 2, &imgtype, &naxis, naxes, &status)) {
            continue;
        }
        if (naxis == 2 && naxes[0] > 0 && naxes[1] > 0) {
            found = true;
        }
    }
    if (!found) {
        status = 0;
        fits_close_file(fptr, &status);
        return fail(QStringLiteral("No 2D image HDU found"));
    }

    FitsImage image;
    image.m_width = static_cast<int>(naxes[0]);
    image.m_height = static_cast<int>(naxes[1]);

    const long numPixels = naxes[0] * naxes[1];
    image.m_pixels.resize(numPixels);
    int anynul = 0;
    status = 0;
    if (fits_read_img(fptr, TDOUBLE, 1, numPixels, nullptr, image.m_pixels.data(), &anynul, &status)) {
        const QString message = cfitsioErrorMessage(status);
        status = 0;
        fits_close_file(fptr, &status);
        return fail(message);
    }

    int numExisting = 0;
    int numMore = 0;
    status = 0;
    fits_get_hdrspace(fptr, &numExisting, &numMore, &status);
    image.m_headerCards.reserve(numExisting);
    for (int i = 1; i <= numExisting; ++i) {
        char keyword[FLEN_KEYWORD] = {0};
        char value[FLEN_VALUE] = {0};
        char comment[FLEN_COMMENT] = {0};
        status = 0;
        if (fits_read_keyn(fptr, i, keyword, value, comment, &status)) {
            continue;
        }
        image.m_headerCards.append(
            {QString::fromLatin1(keyword).trimmed(), QString::fromLatin1(value).trimmed(),
             QString::fromLatin1(comment).trimmed()});
    }

    status = 0;
    fits_close_file(fptr, &status);
    return image;
}

} // namespace fits
