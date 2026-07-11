#include "FitsImageItem.h"

#include <QPainter>

namespace fits {

namespace {

QString toneCurveToString(ToneCurve curve)
{
    switch (curve) {
    case ToneCurve::Log:
        return QStringLiteral("log");
    case ToneCurve::Sqrt:
        return QStringLiteral("sqrt");
    case ToneCurve::Squared:
        return QStringLiteral("squared");
    case ToneCurve::Asinh:
        return QStringLiteral("asinh");
    case ToneCurve::Linear:
    default:
        return QStringLiteral("linear");
    }
}

ToneCurve toneCurveFromString(const QString &s)
{
    if (s == QStringLiteral("log")) {
        return ToneCurve::Log;
    }
    if (s == QStringLiteral("sqrt")) {
        return ToneCurve::Sqrt;
    }
    if (s == QStringLiteral("squared")) {
        return ToneCurve::Squared;
    }
    if (s == QStringLiteral("asinh")) {
        return ToneCurve::Asinh;
    }
    return ToneCurve::Linear;
}

QString colormapToString(Colormap cmap)
{
    switch (cmap) {
    case Colormap::Viridis:
        return QStringLiteral("viridis");
    case Colormap::Hot:
        return QStringLiteral("hot");
    case Colormap::Cool:
        return QStringLiteral("cool");
    case Colormap::Jet:
        return QStringLiteral("jet");
    case Colormap::Gray:
    default:
        return QStringLiteral("gray");
    }
}

Colormap colormapFromString(const QString &s)
{
    if (s == QStringLiteral("viridis")) {
        return Colormap::Viridis;
    }
    if (s == QStringLiteral("hot")) {
        return Colormap::Hot;
    }
    if (s == QStringLiteral("cool")) {
        return Colormap::Cool;
    }
    if (s == QStringLiteral("jet")) {
        return Colormap::Jet;
    }
    return Colormap::Gray;
}

} // namespace

FitsImageItem::FitsImageItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

QString FitsImageItem::stretchMode() const
{
    return m_stretchMode == StretchMode::Custom ? QStringLiteral("custom") : QStringLiteral("percentile");
}

void FitsImageItem::setPercentilePreset(double percentile)
{
    m_stretchMode = StretchMode::Percentile;
    m_percentile = percentile;
    Q_EMIT stretchModeChanged();
    rebuildRender();
}

void FitsImageItem::enterCustomMode()
{
    if (m_stretchMode == StretchMode::Custom) {
        return;
    }
    m_stretchMode = StretchMode::Custom;
    Q_EMIT stretchModeChanged();
}

void FitsImageItem::setManualLimits(double black, double white)
{
    const bool modeChanged = m_stretchMode != StretchMode::Custom;
    m_stretchMode = StretchMode::Custom;
    m_limits = {black, white};
    if (modeChanged) {
        Q_EMIT stretchModeChanged();
    }
    if (!m_image) {
        return;
    }
    m_rendered = render(effectivePixels(), m_image->width(), m_image->height(), m_limits, m_toneCurve, m_colormap,
                         m_reversedColormap);
    Q_EMIT imageChanged();
    update();
}

QString FitsImageItem::toneCurve() const
{
    return toneCurveToString(m_toneCurve);
}

void FitsImageItem::setToneCurve(const QString &curve)
{
    const ToneCurve next = toneCurveFromString(curve);
    if (next == m_toneCurve) {
        return;
    }
    m_toneCurve = next;
    Q_EMIT toneCurveChanged();
    rebuildRender();
}

QString FitsImageItem::colormap() const
{
    return colormapToString(m_colormap);
}

void FitsImageItem::setColormap(const QString &name)
{
    const Colormap next = colormapFromString(name);
    if (next == m_colormap) {
        return;
    }
    m_colormap = next;
    Q_EMIT colormapChanged();
    rebuildRender();
}

void FitsImageItem::setReversedColormap(bool reversed)
{
    if (reversed == m_reversedColormap) {
        return;
    }
    m_reversedColormap = reversed;
    Q_EMIT reversedColormapChanged();
    rebuildRender();
}

void FitsImageItem::setTrimSecEnabled(bool enabled)
{
    if (enabled == m_trimSecEnabled) {
        return;
    }
    m_trimSecEnabled = enabled;
    Q_EMIT trimSecEnabledChanged();
    rebuildRender();
}

bool FitsImageItem::loadFitsBytes(const QByteArray &data)
{
    QString error;
    std::optional<FitsImage> decoded = FitsImage::decode(data, &error);
    if (!decoded.has_value()) {
        m_lastError = error;
        Q_EMIT lastErrorChanged();
        return false;
    }

    m_image = std::move(decoded);
    m_lastError.clear();
    Q_EMIT lastErrorChanged();
    rebuildRender();
    return true;
}

QVector<double> FitsImageItem::effectivePixels() const
{
    if (!m_image) {
        return {};
    }
    if (!m_trimSecEnabled) {
        return m_image->pixels();
    }
    return applyTrimSec(m_image->pixels(), m_image->width(), m_image->height(),
                         m_image->headerValue(QStringLiteral("TRIMSEC")));
}

void FitsImageItem::rebuildRender()
{
    if (!m_image) {
        return;
    }

    const QVector<double> pixels = effectivePixels();
    if (m_stretchMode != StretchMode::Custom) {
        m_limits = computeStretch(pixels, m_stretchMode, m_percentile);
    }
    m_rendered = render(pixels, m_image->width(), m_image->height(), m_limits, m_toneCurve, m_colormap,
                         m_reversedColormap);
    setImplicitWidth(m_image->width());
    setImplicitHeight(m_image->height());
    Q_EMIT imageChanged();
    update();
}

void FitsImageItem::paint(QPainter *painter)
{
    if (m_rendered.isNull()) {
        return;
    }
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter->drawImage(boundingRect(), m_rendered);
}

void FitsImageItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    update();
}

} // namespace fits
