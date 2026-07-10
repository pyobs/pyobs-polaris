#pragma once

#include <QByteArray>
#include <QString>
#include <QVector>

#include <optional>

namespace fits {

// One header card, in file order. Order isn't semantically load-bearing
// the way codec::WireDict's is for state (nothing here looks fields up
// positionally) - kept anyway since it's simply what a raw FITS card
// list naturally is, and free to preserve. `value`/`comment` are the raw
// unparsed strings cfitsio hands back (quotes still present for string
// values, e.g. `'object  '`) - a caller wanting a typed value parses it
// itself; this class doesn't guess a card's intended type.
struct HeaderCard {
    QString keyword;
    QString value;
    QString comment;
};

// Decodes a complete in-memory FITS file (e.g. the bytes
// comm::VfsClient::fetchFile() just fetched) into pixel data + header
// cards, via cfitsio. Deliberately just the decode step - no display
// widget, no VFS wiring, no FitsHeadersWidget (see TODO.md's "ICamera
// follow-up" for why those are separate, later pieces). Pure data class,
// no QML/Qt-object machinery - same "plain, independently testable"
// precedent as coordxform's free functions in CoordinateTransform.h,
// rather than PlotItem's QML-facing-class one; nothing consumes this
// from QML yet, so there's no API to design there until the actual
// display widget does.
//
// 2D single-image only: pyobs-core's own camera modules write one
// science image per file, no multi-extension/table support needed here.
// A dataless primary HDU (NAXIS=0) is skipped in favor of the first
// image HDU that actually holds 2D data - not something this project's
// own DummyCamera-based fixtures produce (confirmed live: DummyCamera
// writes its image directly into the primary HDU, "SCI" is just an
// EXTNAME header card on it, not a real extension), but a real,
// well-known FITS convention some other pipelines do use, so worth
// handling rather than assuming every producer looks like DummyCamera.
class FitsImage
{
public:
    // Returns std::nullopt and sets *errorMessage (if given) on any
    // failure - malformed data, no 2D image HDU found, cfitsio error.
    static std::optional<FitsImage> decode(const QByteArray &data, QString *errorMessage = nullptr);

    int width() const { return m_width; }
    int height() const { return m_height; }

    // Row-major, width()*height() doubles, in FITS file pixel order
    // (first row = bottom of image, per the FITS convention - this
    // class does no flipping, a display widget applies its own
    // convention). Always double regardless of the file's on-disk
    // BITPIX (int8/16/32/64 or float32/64, with BZERO/BSCALE unsigned
    // rescaling already applied) - cfitsio's own fits_read_img()
    // normalizes this for us; a single uniform pixel type is what a
    // future stretch/display widget wants to work with, not eight
    // separate cases mirroring every possible on-disk BITPIX.
    const QVector<double> &pixels() const { return m_pixels; }

    const QVector<HeaderCard> &headerCards() const { return m_headerCards; }

    // Empty string if not present. Raw value as cfitsio returns it (see
    // HeaderCard's own comment) - a numeric header like EXPTIME still
    // comes back as e.g. "0.0", not a double.
    QString headerValue(const QString &keyword) const;

private:
    FitsImage() = default;

    int m_width = 0;
    int m_height = 0;
    QVector<double> m_pixels;
    QVector<HeaderCard> m_headerCards;
};

} // namespace fits
