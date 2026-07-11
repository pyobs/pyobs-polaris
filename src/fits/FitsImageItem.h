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
// stretchMode/toneCurve/colormap are plain QStrings, not Q_ENUM ints -
// matches this project's existing convention for QML-facing enum-like
// state (see comm::XmppClient::status's own
// "disconnected|connecting|..." strings) over introducing new
// Q_ENUM-registered types. stretchMode is "percentile"|"custom" -
// "percentile" always comes with a `percentile` value (100.0 reproduces
// the old separate "Min/Max" mode exactly, see FitsStretch.h);
// "custom" means the last values passed to setManualLimits() (or, if
// never called since entering custom mode via enterCustomMode() alone,
// whatever limits were last computed) - see that method's own comment
// for why switching modes that way deliberately freezes rather than
// resets them.
class FitsImageItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString stretchMode READ stretchMode NOTIFY stretchModeChanged)
    Q_PROPERTY(double percentile READ percentile NOTIFY stretchModeChanged)
    Q_PROPERTY(QString toneCurve READ toneCurve WRITE setToneCurve NOTIFY toneCurveChanged)
    Q_PROPERTY(QString colormap READ colormap WRITE setColormap NOTIFY colormapChanged)
    Q_PROPERTY(
        bool reversedColormap READ reversedColormap WRITE setReversedColormap NOTIFY reversedColormapChanged)
    Q_PROPERTY(bool trimSecEnabled READ trimSecEnabled WRITE setTrimSecEnabled NOTIFY trimSecEnabledChanged)
    Q_PROPERTY(bool hasImage READ hasImage NOTIFY imageChanged)
    Q_PROPERTY(double blackLevel READ blackLevel NOTIFY imageChanged)
    Q_PROPERTY(double whiteLevel READ whiteLevel NOTIFY imageChanged)
    Q_PROPERTY(int imageWidth READ imageWidth NOTIFY imageChanged)
    Q_PROPERTY(int imageHeight READ imageHeight NOTIFY imageChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit FitsImageItem(QQuickItem *parent = nullptr);

    QString stretchMode() const;
    double percentile() const { return m_percentile; }

    // Switches to percentile mode with this exact percentage - matches
    // qfitswidget's comboCuts presets (100.0/99.9/99.0/95.0%; 100.0
    // exactly reproduces the old separate "Min/Max" mode, see
    // FitsStretch.h's own comment on why that's not kept as its own
    // enumerator here).
    Q_INVOKABLE void setPercentilePreset(double percentile);

    // Switches to custom mode without changing the current limits -
    // the QML "Custom" combo entry's own handler, as opposed to
    // setManualLimits() (which both switches mode *and* sets exact
    // levels, the Lo/Hi spin boxes' handler). Matches qfitswidget: just
    // selecting "Custom" leaves spinLoCut/spinHiCut at whatever was
    // last computed, only enables them for editing.
    Q_INVOKABLE void enterCustomMode();

    // Renders immediately with these exact levels, bypassing
    // computeStretch() entirely - see setPercentilePreset()/
    // enterCustomMode() for the other two ways to change stretchMode.
    // Persists across subsequent loadFitsBytes() calls (a new image
    // reuses the same manual levels, not a freshly computed one) until
    // switched back to percentile mode - matches qfitswidget's own
    // "Custom" cuts preset behavior.
    Q_INVOKABLE void setManualLimits(double black, double white);

    QString toneCurve() const;
    void setToneCurve(const QString &curve);

    QString colormap() const;
    void setColormap(const QString &name);

    bool reversedColormap() const { return m_reversedColormap; }
    void setReversedColormap(bool reversed);

    // Default true - matches qfitswidget's checkTrimSec.checked default
    // in fitswidget.ui.
    bool trimSecEnabled() const { return m_trimSecEnabled; }
    void setTrimSecEnabled(bool enabled);

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
    void toneCurveChanged();
    void colormapChanged();
    void reversedColormapChanged();
    void trimSecEnabledChanged();
    void imageChanged();
    void lastErrorChanged();

private:
    void rebuildRender();
    // m_image's pixels with TRIMSEC applied, if trimSecEnabled() and the
    // decoded image actually has that header - both stretch computation
    // and rendering use this, not m_image->pixels() directly, matching
    // qfitswidget's own _trim_image() (percentile/min-max is computed
    // from the *trimmed* data, not the full frame).
    QVector<double> effectivePixels() const;

    StretchMode m_stretchMode = StretchMode::Percentile;
    double m_percentile = 99.9;
    ToneCurve m_toneCurve = ToneCurve::Linear;
    Colormap m_colormap = Colormap::Gray;
    bool m_reversedColormap = false;
    bool m_trimSecEnabled = true;
    std::optional<FitsImage> m_image;
    StretchLimits m_limits;
    QImage m_rendered;
    QString m_lastError;
};

} // namespace fits
