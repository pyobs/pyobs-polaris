#include "PlotItem.h"

#include <QPainter>
#include <QPen>
#include <algorithm>
#include <cmath>

namespace plot {

namespace {

constexpr int kMarginLeft = 55;
constexpr int kMarginBottom = 40;
constexpr int kMarginTop = 12;
constexpr int kMarginRight = 15;
constexpr int kTickCount = 5;
constexpr double kMarkerRadius = 3.5;

const QColor kGridColor(90, 90, 90);
const QColor kAxisColor(140, 140, 140);
const QColor kTickLabelColor(160, 160, 160);
const QColor kAxisLabelColor(180, 180, 180);
const QColor kMarkerColor(100, 160, 255);
const QColor kReferenceColor(90, 200, 120);

// Enough precision for focus/metric-scale values (mm, arbitrary metric
// units) without ballooning into float noise digits.
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
    m_points.clear();
    // Each record is itself a {"key":..,"value":..}-entry list (see the
    // header comment) - parsed here in C++ via QVariant::toList()/toMap(),
    // never via QML/JS array methods, deliberately: see the class comment.
    for (const QVariant &recordVariant : points.toList()) {
        const QVariantList fields = recordVariant.toList();
        if (fields.size() < 2) {
            continue;
        }
        const double x = fields.at(0).toMap().value(QStringLiteral("value")).toDouble();
        const double y = fields.at(1).toMap().value(QStringLiteral("value")).toDouble();
        m_points.push_back(QPointF(x, y));
    }
    update();
    Q_EMIT pointsChanged();
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

    auto toPixel = [&](const QPointF &p) {
        const double px = plotArea.left() + (p.x() - xMin) / (xMax - xMin) * plotArea.width();
        const double py = plotArea.bottom() - (p.y() - yMin) / (yMax - yMin) * plotArea.height();
        return QPointF(px, py);
    };

    QFont tickFont(painter->font().family(), 8);
    painter->setFont(tickFont);
    for (int i = 0; i <= kTickCount; ++i) {
        const double fx = xMin + (xMax - xMin) * i / kTickCount;
        const double px = plotArea.left() + plotArea.width() * i / kTickCount;
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

    painter->setPen(Qt::NoPen);
    painter->setBrush(kMarkerColor);
    for (const QPointF &p : m_points) {
        painter->drawEllipse(toPixel(p), kMarkerRadius, kMarkerRadius);
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
