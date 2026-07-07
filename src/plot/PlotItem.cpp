#include "PlotItem.h"

#include <QPainter>
#include <QPen>
#include <QPolygonF>
#include <algorithm>
#include <cmath>
#include <limits>

namespace plot {

namespace {

constexpr int kMarginLeft = 55;
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

// Pads a [lo, hi] data range with headroom so points/lines never sit flush
// on the plot's edge, and guards the degenerate zero-range case (one
// point, or all-identical values) with a fixed fallback span instead of
// dividing by zero when it's later used to normalize into pixel space.
void pad(double &lo, double &hi)
{
    const double span = hi - lo;
    if (span <= 0.0) {
        const double fallback = std::abs(lo) > 1e-9 ? std::abs(lo) * 0.1 : 1.0;
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
        m_points.push_back(QPointF(xField.toDouble(), yField.toDouble()));
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

void PlotItem::paint(QPainter *painter)
{
    painter->setRenderHint(QPainter::Antialiasing, true);

    const QRectF bounds(0, 0, width(), height());
    const QRectF plotArea(bounds.left() + kMarginLeft, bounds.top() + kMarginTop,
                          bounds.width() - kMarginLeft - kMarginRight,
                          bounds.height() - kMarginTop - kMarginBottom);
    if (plotArea.width() <= 0 || plotArea.height() <= 0) {
        return;
    }

    // Data bounds, including the reference line (if any) so it's never
    // clipped outside the visible x-range.
    double xMin = m_points.isEmpty() ? 0.0 : m_points.first().x();
    double xMax = xMin;
    double yMin = m_points.isEmpty() ? 0.0 : m_points.first().y();
    double yMax = yMin;
    for (const QPointF &p : m_points) {
        xMin = std::min(xMin, p.x());
        xMax = std::max(xMax, p.x());
        yMin = std::min(yMin, p.y());
        yMax = std::max(yMax, p.y());
    }
    if (!std::isnan(m_referenceX)) {
        xMin = std::min(xMin, m_referenceX);
        xMax = std::max(xMax, m_referenceX);
    }
    pad(xMin, xMax);
    pad(yMin, yMax);

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

    QFont tickFont(painter->font().family(), 8);
    painter->setFont(tickFont);
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
                          formatTick(fx));

        const double fy = yMax - (yMax - yMin) * i / kTickCount;
        const double py = plotArea.top() + plotArea.height() * i / kTickCount;
        painter->setPen(QPen(kGridColor, 1, Qt::DotLine));
        painter->drawLine(QPointF(plotArea.left(), py), QPointF(plotArea.right(), py));
        painter->setPen(kTickLabelColor);
        painter->drawText(QRectF(0, py - 8, kMarginLeft - 8, 16), Qt::AlignRight | Qt::AlignVCenter, formatTick(fy));
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

    painter->setPen(kAxisLabelColor);
    QFont labelFont(painter->font().family(), 9);
    painter->setFont(labelFont);
    painter->drawText(QRectF(plotArea.left(), bounds.bottom() - 18, plotArea.width(), 16),
                      Qt::AlignHCenter | Qt::AlignTop, m_xLabel);

    painter->save();
    painter->translate(12, plotArea.center().y());
    painter->rotate(-90);
    painter->drawText(QRectF(-plotArea.height() / 2, -8, plotArea.height(), 16), Qt::AlignHCenter | Qt::AlignTop,
                      m_yLabel);
    painter->restore();
}

}
