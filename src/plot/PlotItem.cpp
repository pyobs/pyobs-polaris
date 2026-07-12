#include "PlotItem.h"

#include <QDateTime>
#include <QPainter>
#include <QPen>
#include <QPolygonF>
#include <algorithm>
#include <cmath>
#include <limits>

namespace plot {

namespace {

// Left margin is computed per-paint from the actual y-tick label text
// (see paint()) rather than a fixed constant like the others: a fixed
// width let long tick labels (e.g. small offset values with many decimal
// digits) overlap the rotated y-axis title text sharing that same zone -
// found live on AcquisitionView.qml's narrower side-by-side offset plot.
// kYLabelWidth reserves room for the rotated title, kYLabelGap/
// kTickLabelGap are breathing room on either side of the tick labels.
constexpr int kYLabelWidth = 14;
constexpr int kYLabelGap = 4;
constexpr int kTickLabelGap = 6;
constexpr int kMarginBottom = 40;
constexpr int kMarginTop = 12;
constexpr int kMarginRight = 15;
constexpr int kTickCount = 5;
constexpr double kMarkerRadius = 3.5;
constexpr double kEndpointMarkerRadius = 5.0;

const QColor kGridColor(90, 90, 90);
const QColor kAxisColor(140, 140, 140);
const QColor kTickLabelColor(160, 160, 160);
const QColor kAxisLabelColor(180, 180, 180);
const QColor kMarkerColor(100, 160, 255);
const QColor kReferenceColor(90, 200, 120);
const QColor kOriginColor(110, 110, 110);
const QColor kStartMarkerColor(220, 90, 90);
const QColor kLatestMarkerColor(90, 200, 120);

// Enough precision for focus/metric/offset-scale values without
// ballooning into float noise digits.
QString formatTick(double value)
{
    return QString::number(value, 'g', 4);
}

// matplotlib's DateFormatter("%H:%M:%S") equivalent for xTicksAsTime -
// `value` is seconds-since-epoch, matching what CameraView.qml's history
// buffer stores (Date.now() / 1000).
QString formatTimeTick(double value)
{
    return QDateTime::fromSecsSinceEpoch(static_cast<qint64>(value)).toString(QStringLiteral("HH:mm:ss"));
}

// A small, distinguishable default palette for series that don't specify
// their own color (or specify an invalid one) - reusing
// WireValueFormat.js's "value" amber as the first entry would tie a C++
// file to a QML-side constant across the codec boundary for no benefit,
// so this is its own independent set, chosen only to read distinctly
// against this widget's dark background.
const QVector<QColor> kDefaultSeriesColors = {
    QColor(100, 160, 255), QColor(240, 160, 80), QColor(120, 200, 120),
    QColor(220, 100, 100), QColor(180, 130, 220), QColor(220, 200, 80),
};

// Pads a [lo, hi] data range with headroom so points/lines never sit flush
// on the plot's edge, and guards the degenerate zero-range case (one
// point, or all-identical values) with a fixed fallback span instead of
// dividing by zero when it's later used to normalize into pixel space.
// `degenerateFallback`, if non-negative, overrides the default "10% of
// abs(lo), or 1.0" guess for that degenerate case - needed for
// xTicksAsTime's epoch-seconds x-axis (see paint()'s own call site):
// "10% of an epoch timestamp" is on the order of years, wildly wrong for
// a single-instant time-series plot (e.g. a sensor whose state has only
// ever been pushed once), unlike every other axis this function pads,
// where the plotted values themselves are already a sensible magnitude
// to take 10% of.
void pad(double &lo, double &hi, double degenerateFallback = -1.0)
{
    const double span = hi - lo;
    if (span <= 0.0) {
        const double fallback = degenerateFallback >= 0.0
            ? degenerateFallback : (std::abs(lo) > 1e-9 ? std::abs(lo) * 0.1 : 1.0);
        lo -= fallback;
        hi += fallback;
    } else {
        lo -= span * 0.08;
        hi += span * 0.08;
    }
}

// A 5-point star centered at `center`, points radiating from `outerRadius`
// with a `outerRadius * 0.4`-deep waist - matches the "latest" marker in
// pyobs-gui's own acquisitionwidget.py/autoguidingwidget.py (matplotlib's
// marker="*").
QPolygonF starPolygon(const QPointF &center, double outerRadius)
{
    constexpr double kInnerRatio = 0.4;
    QPolygonF star;
    for (int i = 0; i < 10; ++i) {
        const double radius = (i % 2 == 0) ? outerRadius : outerRadius * kInnerRatio;
        const double angle = -M_PI / 2.0 + i * M_PI / 5.0;
        star << QPointF(center.x() + radius * std::cos(angle), center.y() + radius * std::sin(angle));
    }
    return star;
}

}

PlotItem::PlotItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void PlotItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    update();
}

void PlotItem::setPoints(const QVariant &points)
{
    m_pointsRaw = points;
    reparsePoints();
    Q_EMIT pointsChanged();
}

void PlotItem::setXFieldIndex(int index)
{
    if (m_xFieldIndex == index) {
        return;
    }
    m_xFieldIndex = index;
    reparsePoints();
    Q_EMIT xFieldIndexChanged();
}

void PlotItem::setYFieldIndex(int index)
{
    if (m_yFieldIndex == index) {
        return;
    }
    m_yFieldIndex = index;
    reparsePoints();
    Q_EMIT yFieldIndexChanged();
}

void PlotItem::setXScale(double scale)
{
    if (m_xScale == scale) {
        return;
    }
    m_xScale = scale;
    reparsePoints();
    Q_EMIT xScaleChanged();
}

void PlotItem::setYScale(double scale)
{
    if (m_yScale == scale) {
        return;
    }
    m_yScale = scale;
    reparsePoints();
    Q_EMIT yScaleChanged();
}

void PlotItem::reparsePoints()
{
    m_points.clear();
    // Each record is itself a {"key":..,"value":..}-entry list (see the
    // header comment) - parsed here in C++ via QVariant::toList()/toMap(),
    // never via QML/JS array methods, deliberately: see the class comment.
    const int maxIndex = std::max(m_xFieldIndex, m_yFieldIndex);
    for (const QVariant &recordVariant : m_pointsRaw.toList()) {
        const QVariantList fields = recordVariant.toList();
        if (fields.size() <= maxIndex) {
            continue;
        }
        const QVariant xField = fields.at(m_xFieldIndex).toMap().value(QStringLiteral("value"));
        const QVariant yField = fields.at(m_yFieldIndex).toMap().value(QStringLiteral("value"));
        if (!xField.isValid() || !yField.isValid()) {
            // e.g. AcquisitionAttempt's optional offset_lon/offset_lat
            // before an offset frame is known - skip rather than plot a
            // misleading (0, 0).
            continue;
        }
        m_points.push_back(QPointF(xField.toDouble() * m_xScale, yField.toDouble() * m_yScale));
    }
    update();
}

void PlotItem::setXLabel(const QString &label)
{
    if (m_xLabel == label) {
        return;
    }
    m_xLabel = label;
    update();
    Q_EMIT xLabelChanged();
}

void PlotItem::setYLabel(const QString &label)
{
    if (m_yLabel == label) {
        return;
    }
    m_yLabel = label;
    update();
    Q_EMIT yLabelChanged();
}

void PlotItem::setShowLine(bool show)
{
    if (m_showLine == show) {
        return;
    }
    m_showLine = show;
    update();
    Q_EMIT showLineChanged();
}

void PlotItem::setEqualAspect(bool equal)
{
    if (m_equalAspect == equal) {
        return;
    }
    m_equalAspect = equal;
    update();
    Q_EMIT equalAspectChanged();
}

void PlotItem::setOriginCrosshair(bool show)
{
    if (m_originCrosshair == show) {
        return;
    }
    m_originCrosshair = show;
    update();
    Q_EMIT originCrosshairChanged();
}

void PlotItem::setShowStartMarker(bool show)
{
    if (m_showStartMarker == show) {
        return;
    }
    m_showStartMarker = show;
    update();
    Q_EMIT showStartMarkerChanged();
}

void PlotItem::setShowLatestMarker(bool show)
{
    if (m_showLatestMarker == show) {
        return;
    }
    m_showLatestMarker = show;
    update();
    Q_EMIT showLatestMarkerChanged();
}

void PlotItem::setXTicksAsIntegers(bool integers)
{
    if (m_xTicksAsIntegers == integers) {
        return;
    }
    m_xTicksAsIntegers = integers;
    update();
    Q_EMIT xTicksAsIntegersChanged();
}

void PlotItem::setReferenceX(double x)
{
    if (m_referenceX == x || (std::isnan(m_referenceX) && std::isnan(x))) {
        return;
    }
    m_referenceX = x;
    update();
    Q_EMIT referenceXChanged();
}

void PlotItem::setReferenceLabel(const QString &label)
{
    if (m_referenceLabel == label) {
        return;
    }
    m_referenceLabel = label;
    update();
    Q_EMIT referenceLabelChanged();
}

void PlotItem::setSeries(const QVariantList &series)
{
    m_seriesRaw = series;
    reparseSeries();
    Q_EMIT seriesChanged();
}

void PlotItem::reparseSeries()
{
    m_series.clear();
    int colorIndex = 0;
    for (const QVariant &entryVariant : m_seriesRaw) {
        const QVariantMap entry = entryVariant.toMap();
        Series series;
        series.label = entry.value(QStringLiteral("label")).toString();
        const QColor explicitColor(entry.value(QStringLiteral("color")).toString());
        series.color = explicitColor.isValid() ? explicitColor
                                                 : kDefaultSeriesColors.at(colorIndex % kDefaultSeriesColors.size());
        ++colorIndex;
        for (const QVariant &pointVariant : entry.value(QStringLiteral("points")).toList()) {
            const QVariantMap point = pointVariant.toMap();
            const QVariant x = point.value(QStringLiteral("x"));
            const QVariant y = point.value(QStringLiteral("y"));
            if (!x.isValid() || !y.isValid()) {
                continue;
            }
            series.points.push_back(QPointF(x.toDouble(), y.toDouble()));
        }
        m_series.push_back(series);
    }
    update();
}

void PlotItem::setXTicksAsTime(bool asTime)
{
    if (m_xTicksAsTime == asTime) {
        return;
    }
    m_xTicksAsTime = asTime;
    update();
    Q_EMIT xTicksAsTimeChanged();
}

void PlotItem::paint(QPainter *painter)
{
    painter->setRenderHint(QPainter::Antialiasing, true);

    // Data bounds, including the reference line (if any) so it's never
    // clipped outside the visible x-range. Computed before plotArea
    // (below) since the left margin needs to know the actual y-tick
    // label text to size itself against.
    double xMin = 0.0;
    double xMax = 0.0;
    double yMin = 0.0;
    double yMax = 0.0;
    bool boundsInitialized = false;
    auto includePoint = [&](const QPointF &p) {
        if (!boundsInitialized) {
            xMin = xMax = p.x();
            yMin = yMax = p.y();
            boundsInitialized = true;
            return;
        }
        xMin = std::min(xMin, p.x());
        xMax = std::max(xMax, p.x());
        yMin = std::min(yMin, p.y());
        yMax = std::max(yMax, p.y());
    };
    for (const QPointF &p : m_points) {
        includePoint(p);
    }
    for (const Series &series : m_series) {
        for (const QPointF &p : series.points) {
            includePoint(p);
        }
    }
    if (!std::isnan(m_referenceX)) {
        xMin = std::min(xMin, m_referenceX);
        xMax = std::max(xMax, m_referenceX);
    }
    pad(xMin, xMax, m_xTicksAsTime ? 60.0 : -1.0);
    pad(yMin, yMax);

    QFont tickFont(painter->font().family(), 8);
    painter->setFont(tickFont);
    const QFontMetrics tickMetrics(tickFont);
    int maxYTickWidth = 0;
    for (int i = 0; i <= kTickCount; ++i) {
        const double fy = yMax - (yMax - yMin) * i / kTickCount;
        maxYTickWidth = std::max(maxYTickWidth, tickMetrics.horizontalAdvance(formatTick(fy)));
    }
    const int marginLeft = kYLabelWidth + kYLabelGap + maxYTickWidth + kTickLabelGap;

    const QRectF bounds(0, 0, width(), height());
    const QRectF plotArea(bounds.left() + marginLeft, bounds.top() + kMarginTop,
                          bounds.width() - marginLeft - kMarginRight,
                          bounds.height() - kMarginTop - kMarginBottom);
    if (plotArea.width() <= 0 || plotArea.height() <= 0) {
        return;
    }

    if (m_equalAspect) {
        // matplotlib's set_aspect("equal", adjustable="datalim"): one
        // units-per-pixel scale shared by both axes (the larger of the
        // two natural ones), recentered on the original data window, so
        // circles/angles in the data aren't visually distorted.
        const double unitsPerPixel = std::max((xMax - xMin) / plotArea.width(), (yMax - yMin) / plotArea.height());
        const double xCenter = (xMin + xMax) / 2.0;
        const double yCenter = (yMin + yMax) / 2.0;
        xMin = xCenter - unitsPerPixel * plotArea.width() / 2.0;
        xMax = xCenter + unitsPerPixel * plotArea.width() / 2.0;
        yMin = yCenter - unitsPerPixel * plotArea.height() / 2.0;
        yMax = yCenter + unitsPerPixel * plotArea.height() / 2.0;
    }

    auto toPixel = [&](const QPointF &p) {
        const double px = plotArea.left() + (p.x() - xMin) / (xMax - xMin) * plotArea.width();
        const double py = plotArea.bottom() - (p.y() - yMin) / (yMax - yMin) * plotArea.height();
        return QPointF(px, py);
    };

    int lastIntXTick = std::numeric_limits<int>::min();
    for (int i = 0; i <= kTickCount; ++i) {
        double fx = xMin + (xMax - xMin) * i / kTickCount;
        if (m_xTicksAsIntegers) {
            fx = std::round(fx);
            const int intTick = static_cast<int>(fx);
            if (intTick == lastIntXTick) {
                continue;
            }
            lastIntXTick = intTick;
        }
        const double px = toPixel(QPointF(fx, yMin)).x();
        painter->setPen(QPen(kGridColor, 1, Qt::DotLine));
        painter->drawLine(QPointF(px, plotArea.top()), QPointF(px, plotArea.bottom()));
        painter->setPen(kTickLabelColor);
        painter->drawText(QRectF(px - 30, plotArea.bottom() + 4, 60, 16), Qt::AlignHCenter | Qt::AlignTop,
                          m_xTicksAsTime ? formatTimeTick(fx) : formatTick(fx));

        const double fy = yMax - (yMax - yMin) * i / kTickCount;
        const double py = plotArea.top() + plotArea.height() * i / kTickCount;
        painter->setPen(QPen(kGridColor, 1, Qt::DotLine));
        painter->drawLine(QPointF(plotArea.left(), py), QPointF(plotArea.right(), py));
        painter->setPen(kTickLabelColor);
        painter->drawText(QRectF(kYLabelWidth + kYLabelGap, py - 8, maxYTickWidth, 16), Qt::AlignRight | Qt::AlignVCenter,
                          formatTick(fy));
    }

    painter->setPen(QPen(kAxisColor, 1));
    painter->setBrush(Qt::NoBrush);
    painter->drawRect(plotArea);

    if (m_originCrosshair) {
        painter->setPen(QPen(kOriginColor, 1));
        if (xMin <= 0.0 && 0.0 <= xMax) {
            const double px = toPixel(QPointF(0.0, yMin)).x();
            painter->drawLine(QPointF(px, plotArea.top()), QPointF(px, plotArea.bottom()));
        }
        if (yMin <= 0.0 && 0.0 <= yMax) {
            const double py = toPixel(QPointF(xMin, 0.0)).y();
            painter->drawLine(QPointF(plotArea.left(), py), QPointF(plotArea.right(), py));
        }
    }

    if (!std::isnan(m_referenceX)) {
        const double px = toPixel(QPointF(m_referenceX, yMin)).x();
        painter->setPen(QPen(kReferenceColor, 1.5, Qt::DashLine));
        painter->drawLine(QPointF(px, plotArea.top()), QPointF(px, plotArea.bottom()));
        if (!m_referenceLabel.isEmpty()) {
            painter->setPen(kReferenceColor);
            painter->drawText(QRectF(px + 4, plotArea.top() + 2, 120, 16), Qt::AlignLeft | Qt::AlignTop,
                              m_referenceLabel);
        }
    }

    if (m_showLine && m_points.size() > 1) {
        QPolygonF line;
        for (const QPointF &p : m_points) {
            line << toPixel(p);
        }
        painter->setPen(QPen(kMarkerColor, 1.5));
        painter->drawPolyline(line);
    }

    painter->setPen(Qt::NoPen);
    painter->setBrush(kMarkerColor);
    for (const QPointF &p : m_points) {
        painter->drawEllipse(toPixel(p), kMarkerRadius, kMarkerRadius);
    }

    if (m_showStartMarker && !m_points.isEmpty()) {
        const QPointF center = toPixel(m_points.first());
        painter->setPen(Qt::NoPen);
        painter->setBrush(kStartMarkerColor);
        painter->drawRect(QRectF(center.x() - kEndpointMarkerRadius, center.y() - kEndpointMarkerRadius,
                                 kEndpointMarkerRadius * 2, kEndpointMarkerRadius * 2));
    }
    if (m_showLatestMarker && !m_points.isEmpty()) {
        painter->setPen(Qt::NoPen);
        painter->setBrush(kLatestMarkerColor);
        painter->drawPolygon(starPolygon(toPixel(m_points.last()), kEndpointMarkerRadius * 1.4));
    }

    // Multi-series mode (see `series`'s own doc comment) - each series is
    // just a plain colored polyline, no point markers: matches pyobs-gui's
    // matplotlib ax.plot() default styling for the temperatures history
    // plot this was added for, and keeps a many-point growing history
    // readable instead of cluttered with hundreds of dots.
    for (const Series &series : m_series) {
        if (series.points.size() < 2) {
            continue;
        }
        QPolygonF line;
        for (const QPointF &p : series.points) {
            line << toPixel(p);
        }
        painter->setPen(QPen(series.color, 1.5));
        painter->drawPolyline(line);
    }

    if (m_series.size() > 1) {
        QFont legendFont(painter->font().family(), 8);
        painter->setFont(legendFont);
        const QFontMetrics legendMetrics(legendFont);
        constexpr double kSwatchSize = 10.0;
        constexpr double kRowHeight = 14.0;
        constexpr double kPadding = 6.0;
        int maxLabelWidth = 0;
        for (const Series &series : m_series) {
            maxLabelWidth = std::max(maxLabelWidth, legendMetrics.horizontalAdvance(series.label));
        }
        const double legendWidth = kSwatchSize + 6.0 + maxLabelWidth + kPadding * 2;
        const double legendHeight = m_series.size() * kRowHeight + kPadding * 2;
        const QRectF legendRect(plotArea.right() - legendWidth - 4, plotArea.top() + 4, legendWidth, legendHeight);
        painter->setPen(QPen(kAxisColor, 1));
        painter->setBrush(QColor(30, 30, 30, 200));
        painter->drawRect(legendRect);
        for (int i = 0; i < m_series.size(); ++i) {
            const double rowTop = legendRect.top() + kPadding + i * kRowHeight;
            painter->setPen(Qt::NoPen);
            painter->setBrush(m_series.at(i).color);
            painter->drawRect(QRectF(legendRect.left() + kPadding, rowTop + 2, kSwatchSize, kSwatchSize - 4));
            painter->setPen(kTickLabelColor);
            painter->drawText(QRectF(legendRect.left() + kPadding + kSwatchSize + 6, rowTop, maxLabelWidth, kRowHeight),
                              Qt::AlignLeft | Qt::AlignVCenter, m_series.at(i).label);
        }
    }

    painter->setPen(kAxisLabelColor);
    QFont labelFont(painter->font().family(), 9);
    painter->setFont(labelFont);
    painter->drawText(QRectF(plotArea.left(), bounds.bottom() - 18, plotArea.width(), 16),
                      Qt::AlignHCenter | Qt::AlignTop, m_xLabel);

    painter->save();
    painter->translate(kYLabelWidth / 2.0, plotArea.center().y());
    painter->rotate(-90);
    painter->drawText(QRectF(-plotArea.height() / 2, -8, plotArea.height(), 16), Qt::AlignHCenter | Qt::AlignTop,
                      m_yLabel);
    painter->restore();
}

}
