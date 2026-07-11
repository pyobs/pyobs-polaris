#include "FitsStretch.h"

#include <algorithm>
#include <cmath>

namespace fits {

namespace {

// Operates on the already-normalized [0,1] value - see ToneCurve's own
// comment for why that's deliberately not the raw pixel value the way
// qfitswidget's FuncNorm works. The constants (k=1000 for Log, a=10 for
// Asinh) are chosen purely for a visually reasonable compression curve
// over a [0,1] domain, not derived from anything in qfitswidget (whose
// own curve shape depends on the raw vmin/vmax range, not a fixed
// constant) - there's no "correct" value to match, just a reasonable
// default a user can't otherwise tune here.
double applyToneCurve(double t, ToneCurve curve)
{
    switch (curve) {
    case ToneCurve::Sqrt:
        return std::sqrt(t);
    case ToneCurve::Squared:
        return t * t;
    case ToneCurve::Log: {
        constexpr double k = 1000.0;
        return std::log1p(k * t) / std::log1p(k);
    }
    case ToneCurve::Asinh: {
        constexpr double a = 10.0;
        return std::asinh(a * t) / std::asinh(a);
    }
    case ToneCurve::Linear:
    default:
        return t;
    }
}

struct ControlPoint {
    double position;
    int r;
    int g;
    int b;
};

// Piecewise-linear interpolation through `points` (sorted by position,
// first at 0.0 and last at 1.0) - the standard cheap way to approximate
// a colormap without a full per-entry lookup table.
QRgb interpolate(double t, const ControlPoint *points, int count)
{
    int i = 0;
    while (i < count - 2 && t > points[i + 1].position) {
        ++i;
    }
    const ControlPoint &a = points[i];
    const ControlPoint &b = points[i + 1];
    const double span = b.position - a.position;
    const double f = span > 0.0 ? (t - a.position) / span : 0.0;
    const int r = static_cast<int>(std::lround(a.r + f * (b.r - a.r)));
    const int g = static_cast<int>(std::lround(a.g + f * (b.g - a.g)));
    const int b_ = static_cast<int>(std::lround(a.b + f * (b.b - a.b)));
    return qRgb(r, g, b_);
}

QRgb colormapColor(double t, Colormap colormap)
{
    switch (colormap) {
    case Colormap::Gray: {
        const int v = static_cast<int>(std::lround(t * 255.0));
        return qRgb(v, v, v);
    }
    case Colormap::Hot: {
        static constexpr ControlPoint points[] = {
            {0.0, 0, 0, 0},
            {1.0 / 3.0, 255, 0, 0},
            {2.0 / 3.0, 255, 255, 0},
            {1.0, 255, 255, 255},
        };
        return interpolate(t, points, 4);
    }
    case Colormap::Cool: {
        static constexpr ControlPoint points[] = {
            {0.0, 0, 255, 255},
            {1.0, 255, 0, 255},
        };
        return interpolate(t, points, 2);
    }
    case Colormap::Jet: {
        static constexpr ControlPoint points[] = {
            {0.0, 0, 0, 143},
            {0.125, 0, 0, 255},
            {0.375, 0, 255, 255},
            {0.625, 255, 255, 0},
            {0.875, 255, 0, 0},
            {1.0, 128, 0, 0},
        };
        return interpolate(t, points, 6);
    }
    case Colormap::Viridis:
    default: {
        static constexpr ControlPoint points[] = {
            {0.0, 68, 1, 84},
            {0.25, 59, 82, 139},
            {0.5, 33, 145, 140},
            {0.75, 94, 201, 98},
            {1.0, 253, 231, 37},
        };
        return interpolate(t, points, 5);
    }
    }
}

} // namespace

StretchLimits computeStretch(const QVector<double> &pixels, StretchMode mode, double percentile)
{
    QVector<double> finite;
    finite.reserve(pixels.size());
    for (double v : pixels) {
        // See this function's own header comment for why non-positive
        // values are excluded too, not just non-finite ones.
        if (std::isfinite(v) && v > 0.0) {
            finite.append(v);
        }
    }
    if (finite.isEmpty()) {
        return {};
    }

    if (mode == StretchMode::Custom) {
        // Never actually reached - FitsImageItem only calls this for
        // Percentile, Custom's limits are set directly via
        // setManualLimits(). Kept as an explicit branch so a future
        // caller mistake fails safe with the harmless default rather
        // than silently computing a percentile clip nobody asked for.
        return {};
    }

    const double clipFraction = std::clamp((100.0 - percentile) / 100.0 / 2.0, 0.0, 0.5);
    const auto lowIdx = static_cast<qsizetype>(clipFraction * (finite.size() - 1));
    const auto highIdx = static_cast<qsizetype>((1.0 - clipFraction) * (finite.size() - 1));

    // nth_element twice on the same buffer: each call only guarantees
    // the target index's value is correct (elements around it are
    // merely partitioned, not fully sorted), which is exactly what
    // finding two independent percentile points needs - the second
    // call re-partitions from whatever order the first left behind
    // and is still correct for its own index. At percentile=100,
    // clipFraction is 0 and lowIdx/highIdx land exactly on the literal
    // min/max.
    StretchLimits limits;
    std::nth_element(finite.begin(), finite.begin() + lowIdx, finite.end());
    limits.black = finite[lowIdx];
    std::nth_element(finite.begin(), finite.begin() + highIdx, finite.end());
    limits.white = finite[highIdx];

    if (limits.black > limits.white) {
        std::swap(limits.black, limits.white);
    }
    return limits;
}

QVector<double> applyTrimSec(const QVector<double> &pixels, int width, int height, const QString &trimsec)
{
    if (pixels.size() != static_cast<qsizetype>(width) * height) {
        return pixels;
    }

    QString trimmed = trimsec.trimmed();
    // FitsImage::headerValue() hands back the raw on-disk value (see its
    // own comment) - for a FITS string-type keyword like TRIMSEC that
    // means still-quoted, e.g. `'[1:512,1:512]'`, not `[1:512,1:512]`.
    // Strip one layer of surrounding single quotes before the `[`/`]`
    // check, tolerating either form so a caller doesn't have to know
    // which one they have.
    if (trimmed.startsWith(QLatin1Char('\'')) && trimmed.endsWith(QLatin1Char('\'')) && trimmed.size() >= 2) {
        trimmed = trimmed.mid(1, trimmed.size() - 2).trimmed();
    }
    if (!trimmed.startsWith(QLatin1Char('[')) || !trimmed.endsWith(QLatin1Char(']'))) {
        return pixels;
    }
    trimmed = trimmed.mid(1, trimmed.size() - 2);

    const QStringList parts = trimmed.split(QLatin1Char(','));
    if (parts.size() != 2) {
        return pixels;
    }
    const QStringList xRange = parts[0].split(QLatin1Char(':'));
    const QStringList yRange = parts[1].split(QLatin1Char(':'));
    if (xRange.size() != 2 || yRange.size() != 2) {
        return pixels;
    }

    bool xOk0 = false, xOk1 = false, yOk0 = false, yOk1 = false;
    const int x0 = xRange[0].toInt(&xOk0) - 1;
    const int x1 = xRange[1].toInt(&xOk1);
    const int y0 = yRange[0].toInt(&yOk0) - 1;
    const int y1 = yRange[1].toInt(&yOk1);
    if (!xOk0 || !xOk1 || !yOk0 || !yOk1) {
        return pixels;
    }

    QVector<double> result = pixels;
    for (int y = 0; y < height; ++y) {
        const bool rowInside = y >= y0 && y < y1;
        double *row = result.data() + static_cast<qsizetype>(y) * width;
        for (int x = 0; x < width; ++x) {
            if (!rowInside || x < x0 || x >= x1) {
                row[x] = 0.0;
            }
        }
    }
    return result;
}

QImage render(const QVector<double> &pixels, int width, int height, const StretchLimits &limits, ToneCurve curve,
              Colormap colormap, bool reversedColormap)
{
    if (width <= 0 || height <= 0 || pixels.size() != static_cast<qsizetype>(width) * height) {
        return {};
    }

    QImage image(width, height, QImage::Format_RGB32);
    const double range = limits.white - limits.black;

    for (int y = 0; y < height; ++y) {
        auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
        const int srcRow = height - 1 - y; // FITS row 0 = bottom -> flip to top-down QImage
        const double *srcData = pixels.constData() + static_cast<qsizetype>(srcRow) * width;
        for (int x = 0; x < width; ++x) {
            double t = range > 0.0 ? (srcData[x] - limits.black) / range : 0.5;
            t = std::clamp(t, 0.0, 1.0);
            t = applyToneCurve(t, curve);
            if (reversedColormap) {
                t = 1.0 - t;
            }
            row[x] = colormapColor(t, colormap);
        }
    }
    return image;
}

} // namespace fits
