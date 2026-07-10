#include "FitsImageItem.h"

#include <QPainter>

namespace fits {

FitsImageItem::FitsImageItem(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

QString FitsImageItem::stretchMode() const
{
    return m_stretchMode == StretchMode::MinMax ? QStringLiteral("minmax") : QStringLiteral("percentile");
}

void FitsImageItem::setStretchMode(const QString &mode)
{
    const StretchMode next = mode == QStringLiteral("minmax") ? StretchMode::MinMax : StretchMode::Percentile;
    if (next == m_stretchMode) {
        return;
    }
    m_stretchMode = next;
    Q_EMIT stretchModeChanged();
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

void FitsImageItem::rebuildRender()
{
    if (!m_image) {
        return;
    }

    m_limits = computeStretch(m_image->pixels(), m_stretchMode);
    m_rendered = renderGrayscale(m_image->pixels(), m_image->width(), m_image->height(), m_limits);
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
