#include "FitsStretch.h"

#include <algorithm>
#include <cmath>

namespace fits {

StretchLimits computeStretch(const QVector<double> &pixels, StretchMode mode, double percentile)
{
    QVector<double> finite;
    finite.reserve(pixels.size());
    for (double v : pixels) {
        if (std::isfinite(v)) {
            finite.append(v);
        }
    }
    if (finite.isEmpty()) {
        return {};
    }

    StretchLimits limits;
    if (mode == StretchMode::MinMax) {
        const auto [minIt, maxIt] = std::minmax_element(finite.begin(), finite.end());
        limits.black = *minIt;
        limits.white = *maxIt;
    } else {
        const double clipFraction = std::clamp((100.0 - percentile) / 100.0 / 2.0, 0.0, 0.5);
        const auto lowIdx = static_cast<qsizetype>(clipFraction * (finite.size() - 1));
        const auto highIdx = static_cast<qsizetype>((1.0 - clipFraction) * (finite.size() - 1));

        // nth_element twice on the same buffer: each call only guarantees
        // the target index's value is correct (elements around it are
        // merely partitioned, not fully sorted), which is exactly what
        // finding two independent percentile points needs - the second
        // call re-partitions from whatever order the first left behind
        // and is still correct for its own index.
        std::nth_element(finite.begin(), finite.begin() + lowIdx, finite.end());
        limits.black = finite[lowIdx];
        std::nth_element(finite.begin(), finite.begin() + highIdx, finite.end());
        limits.white = finite[highIdx];
    }
    if (limits.black > limits.white) {
        std::swap(limits.black, limits.white);
    }
    return limits;
}

QImage renderGrayscale(const QVector<double> &pixels, int width, int height, const StretchLimits &limits)
{
    if (width <= 0 || height <= 0 || pixels.size() != static_cast<qsizetype>(width) * height) {
        return {};
    }

    QImage image(width, height, QImage::Format_Grayscale8);
    const double range = limits.white - limits.black;

    for (int y = 0; y < height; ++y) {
        uchar *row = image.scanLine(y);
        const int srcRow = height - 1 - y; // FITS row 0 = bottom -> flip to top-down QImage
        const double *srcData = pixels.constData() + static_cast<qsizetype>(srcRow) * width;
        for (int x = 0; x < width; ++x) {
            double normalized = range > 0.0 ? (srcData[x] - limits.black) / range : 0.5;
            normalized = std::clamp(normalized, 0.0, 1.0);
            row[x] = static_cast<uchar>(std::lround(normalized * 255.0));
        }
    }
    return image;
}

} // namespace fits
