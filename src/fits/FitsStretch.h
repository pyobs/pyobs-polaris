#pragma once

#include <QImage>
#include <QString>
#include <QVector>

namespace fits {

enum class StretchMode {
    // qfitswidget's own comboCuts has no separate "Min/Max" entry -
    // "100.0%" already means exactly that (clipping 0% of pixels from
    // each tail is literally the data's min/max, see computeStretch()).
    // Matching that shape here rather than keeping a redundant mode.
    Percentile,
    // Manual black/white levels, set directly via
    // FitsImageItem::setManualLimits() rather than computed here -
    // computeStretch() is never called with this mode (see its own
    // comment).
    Custom,
};

// Tone curve applied to the already black/white-normalized [0,1] pixel
// value, before the colormap lookup - matches qfitswidget's own
// comboStretch entries (linear/log/sqrt/squared/asinh, see
// applyToneCurve() in the .cpp). Deliberately operates on the normalized
// value rather than the raw pixel value the way qfitswidget's FuncNorm
// does: same qualitative brightness-compression shape, without needing
// qfitswidget's masked-array handling for pixel values <= 0 (log/asinh
// are simply always well-defined on a [0,1] domain).
enum class ToneCurve {
    Linear,
    Log,
    Sqrt,
    Squared,
    Asinh,
};

// A small curated set, not an attempt at matplotlib's ~150-map library
// qfitswidget's own comboColormap offers - vendoring a colormap library
// for that would be a lot of dependency weight for no functional gain
// over a practical subset. Gray matches qfitswidget's own default;
// Viridis/Hot/Cool/Jet are the ones most commonly reached for instead.
enum class Colormap {
    Gray,
    Viridis,
    Hot,
    Cool,
    Jet,
};

// Display black/white levels - pixel values at or below `black` render
// as pure black, at or above `white` as pure white, linear in between
// (before the tone curve, see render()).
struct StretchLimits {
    double black = 0.0;
    double white = 1.0;
};

// Computes display levels from raw pixel data. Non-finite values (e.g. a
// BLANK-masked pixel) and non-positive ones (<= 0) are both excluded
// from the computation - matches qfitswidget's own `_trim_image()`
// (`self.trimmed_data[self.trimmed_data > 0]`), and specifically pairs
// with applyTrimSec()'s zero-fill: without this filter, a trimmed-away
// border would itself pull the black level down to 0 on every trimmed
// image, defeating the point of trimming at all. The tradeoff (also
// excluding any legitimately non-positive science pixel, e.g. a
// background-subtracted frame with noise dipping below zero) is
// qfitswidget's own, not invented here - kept for parity rather than
// "fixed", since a caller asking to match qfitswidget's behavior wants
// this exact behavior, quirks included. Percentile clips `percentile`%
// of the *remaining* pixels symmetrically from both tails (e.g. the
// default 99.9 keeps the middle 99.9%, discarding 0.05% from each end)
// - a common, simple astronomical "cuts" heuristic, and (at
// percentile=100) the literal min/max of the positive-finite pixels.
// Deliberately not
// DS9-style iterative zscale - a materially more involved algorithm, not
// worth the complexity unless a concrete need for it comes up (see
// TODO.md). All-non-finite or empty input, or StretchMode::Custom
// (never actually reached - see that enumerator's own comment) returns
// {0.0, 1.0}, the same harmless default `StretchLimits{}` already has.
StretchLimits computeStretch(const QVector<double> &pixels, StretchMode mode, double percentile = 99.9);

// Zeroes every pixel outside the header's TRIMSEC rectangle ("[x0:x1,
// y0:y1]", FITS 1-based inclusive bounds) - matches qfitswidget's own
// _trimsec(): the out-of-section area is blanked, not cropped away, so
// `pixels`' width*height count (and every caller's assumption about it)
// stays unchanged. Not a full FITS section-syntax parser (no step, no
// reversed ranges) - matches the only shape qfitswidget's own
// _trimsec() itself handles. A missing/malformed TRIMSEC, or a
// pixels/width/height mismatch, returns `pixels` unchanged.
QVector<double> applyTrimSec(const QVector<double> &pixels, int width, int height, const QString &trimsec);

// Renders `pixels` (row-major, width x height, FITS pixel order - row 0
// is the *bottom* of the image per FITS convention) into a top-down
// QImage::Format_RGB32 (row 0 = top, the usual raster/QImage convention)
// - the vertical flip happens here, once, so nothing downstream needs to
// know FITS's row order differs from QImage's. Each pixel is linearly
// normalized into `limits` then `clamp`ed to [0,1] (`limits.black ==
// limits.white`, a perfectly flat image, renders as uniform mid-gray
// rather than dividing by zero), then `curve`-shaped, then colormap-
// looked-up (`reversedColormap` flips the [0,1] value first, matching
// qfitswidget's own checkColormapReverse). Defaults reproduce this
// function's original grayscale-linear-only behavior, so a caller that
// only cares about levels doesn't need to know about tone curves/
// colormaps at all. Returns a null QImage if `pixels.size() != width *
// height`.
QImage render(const QVector<double> &pixels, int width, int height, const StretchLimits &limits,
              ToneCurve curve = ToneCurve::Linear, Colormap colormap = Colormap::Gray,
              bool reversedColormap = false);

} // namespace fits
