#pragma once

#include <QImage>
#include <QVector>

namespace fits {

enum class StretchMode {
    MinMax,
    Percentile,
};

// Display black/white levels - pixel values at or below `black` render
// as pure black, at or above `white` as pure white, linear in between.
struct StretchLimits {
    double black = 0.0;
    double white = 1.0;
};

// Computes display levels from raw pixel data (non-finite values, e.g. a
// BLANK-masked pixel, are ignored rather than propagating into the
// result). MinMax uses the literal data min/max. Percentile clips
// `percentile`% of pixels symmetrically from both tails (e.g. the
// default 99.5 keeps the middle 99.5%, discarding 0.25% from each end) -
// a common, simple astronomical "cuts" heuristic. Deliberately not
// DS9-style iterative zscale - a materially more involved algorithm,
// not worth the complexity unless a concrete need for it comes up (see
// TODO.md). All-non-finite or empty input returns {0.0, 1.0}, the same
// harmless default `StretchLimits{}` already has.
StretchLimits computeStretch(const QVector<double> &pixels, StretchMode mode, double percentile = 99.5);

// Renders `pixels` (row-major, width x height, FITS pixel order - row 0
// is the *bottom* of the image per FITS convention) into a top-down
// QImage::Format_Grayscale8 (row 0 = top, the usual raster/QImage
// convention) - the vertical flip happens here, once, so nothing
// downstream needs to know FITS's row order differs from QImage's.
// `limits.black == limits.white` (a perfectly flat image) renders as
// uniform mid-gray rather than dividing by zero. Returns a null QImage
// if `pixels.size() != width * height`.
QImage renderGrayscale(const QVector<double> &pixels, int width, int height, const StretchLimits &limits);

} // namespace fits
