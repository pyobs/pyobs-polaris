#pragma once

#include "FitsImage.h"
#include "FitsStretch.h"

#include <QQuickPaintedItem>
#include <QString>
#include <optional>
#include <qqmlintegration.h>

namespace fits {

// QML-facing FITS image display: decode + stretch + render, all driven
// by loadFitsBytes(). Follows plot::PlotItem's precedent (this project's
// only other custom-painted QML item) - a QQuickPaintedItem painting a
// pre-built QImage, not a live-recomputed-every-frame render. Zoom/pan
// are deliberately NOT implemented here: QML already has idiomatic tools
// for that (Flickable for pan, resizing this item's width/height for
// zoom - see CameraView.qml), so this item just paints itself at
// whatever size it's given, smoothly scaled - reimplementing flick
// physics in C++ would duplicate what Flickable already does for free.
//
// stretchMode is a plain QString ("minmax"/"percentile"), not a Q_ENUM
// int - matches this project's existing convention for QML-facing
// enum-like state (see comm::XmppClient::status's own
// "disconnected|connecting|..." strings) over introducing a new
// Q_ENUM-registered type for two values.
class FitsImageItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString stretchMode READ stretchMode WRITE setStretchMode NOTIFY stretchModeChanged)
    Q_PROPERTY(bool hasImage READ hasImage NOTIFY imageChanged)
    Q_PROPERTY(double blackLevel READ blackLevel NOTIFY imageChanged)
    Q_PROPERTY(double whiteLevel READ whiteLevel NOTIFY imageChanged)
    Q_PROPERTY(int imageWidth READ imageWidth NOTIFY imageChanged)
    Q_PROPERTY(int imageHeight READ imageHeight NOTIFY imageChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit FitsImageItem(QQuickItem *parent = nullptr);

    QString stretchMode() const;
    void setStretchMode(const QString &mode);

    bool hasImage() const { return m_image.has_value(); }
    double blackLevel() const { return m_limits.black; }
    double whiteLevel() const { return m_limits.white; }
    int imageWidth() const { return m_image ? m_image->width() : 0; }
    int imageHeight() const { return m_image ? m_image->height() : 0; }
    QString lastError() const { return m_lastError; }

    // Decodes `data` via fits::FitsImage::decode() and, on success,
    // recomputes the stretch/cached render and repaints. Returns whether
    // decode succeeded; lastError holds the message either way (cleared
    // on success). A failure leaves any previously-displayed image in
    // place rather than blanking it - a single bad/truncated fetch
    // shouldn't erase the last good frame.
    Q_INVOKABLE bool loadFitsBytes(const QByteArray &data);

    void paint(QPainter *painter) override;

protected:
    // paint() draws into boundingRect() (item size), so a resize needs
    // an explicit repaint - QQuickPaintedItem doesn't trigger one on its
    // own just because the item's geometry changed. Same reasoning as
    // PlotItem::geometryChange().
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

Q_SIGNALS:
    void stretchModeChanged();
    void imageChanged();
    void lastErrorChanged();

private:
    void rebuildRender();

    StretchMode m_stretchMode = StretchMode::Percentile;
    std::optional<FitsImage> m_image;
    StretchLimits m_limits;
    QImage m_rendered;
    QString m_lastError;
};

} // namespace fits
