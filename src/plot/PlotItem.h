#pragma once

#include <QColor>
#include <QPointF>
#include <QQuickPaintedItem>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVector>
#include <limits>
#include <qqmlintegration.h>

namespace plot {

// Minimal hand-rolled scatter/line plot - see TODO.md's "no external
// plotting library" decision (QtCharts/QtGraphs are GPL-or-commercial
// only, QCustomPlot the same, Qwt is QWidgets-based) and DEVELOPMENT.md's
// QQuickPaintedItem-over-Canvas rationale. Grew from AutoFocusView.qml's
// single scatter-plus-reference-line need to also cover
// AcquisitionView.qml's two plot shapes (a line-plus-markers series, and
// an equal-aspect 2D trajectory with start/latest markers and an origin
// crosshair) - extend further rather than fork a second plot item when
// AutoGuidingView needs its own variation (TODO.md).
class PlotItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

    // Raw decoded value of an array<struct<...>> WireValue field (e.g.
    // AutoFocusState.points, AcquisitionState.attempts) - a QVariantList
    // of records, each record itself a QVariantList of
    // {"key":..,"value":..} entries in wire/declaration order (see
    // codec::toQVariant / WireValue.h). Parsed entirely in C++
    // (setPoints()): a record's field at `xFieldIndex` is plotted as x,
    // `yFieldIndex` as y - not looked up by name, since wire order is
    // exactly what this project's codec preserves dict/dataclass fields
    // for everywhere else (e.g. IAutoFocus's AutoFocusPoint{focus, value}
    // needs no extra configuration beyond the 0/1 defaults;
    // AcquisitionAttempt{attempt, distance, offset_applied, offset_frame,
    // offset_lon, offset_lat} needs xFieldIndex=4/yFieldIndex=5 for its
    // offset-trajectory plot). A record missing either field, or whose
    // selected field is null (e.g. AcquisitionAttempt's optional
    // offset_lon/offset_lat before an offset frame is known), is skipped
    // entirely rather than plotted as zero.
    Q_PROPERTY(QVariant points READ points WRITE setPoints NOTIFY pointsChanged)
    Q_PROPERTY(int xFieldIndex READ xFieldIndex WRITE setXFieldIndex NOTIFY xFieldIndexChanged)
    Q_PROPERTY(int yFieldIndex READ yFieldIndex WRITE setYFieldIndex NOTIFY yFieldIndexChanged)
    // Multiplies each selected field's raw wire value before plotting -
    // e.g. AcquisitionAttempt's offset_lon/offset_lat arrive in degrees,
    // but AcquisitionView.qml plots them in arcsec (xScale/yScale: 3600),
    // matching autoguidingwidget.py's own convention. Applied in C++
    // (reparsePoints()), not via a QML-side per-point transform, for the
    // same reason the whole points/{x,y}FieldIndex design avoids ever
    // reshaping a C++-crossed array in QML/JS - see the class comment.
    Q_PROPERTY(double xScale READ xScale WRITE setXScale NOTIFY xScaleChanged)
    Q_PROPERTY(double yScale READ yScale WRITE setYScale NOTIFY yScaleChanged)
    Q_PROPERTY(QString xLabel READ xLabel WRITE setXLabel NOTIFY xLabelChanged)
    Q_PROPERTY(QString yLabel READ yLabel WRITE setYLabel NOTIFY yLabelChanged)
    // Connects consecutive points with a line, in `points` order - off by
    // default (AutoFocusView.qml's curve is an unordered-by-x scatter),
    // on for AcquisitionView.qml's progression-over-attempts/samples
    // plots.
    Q_PROPERTY(bool showLine READ showLine WRITE setShowLine NOTIFY showLineChanged)
    // matplotlib's ax.set_aspect("equal", adjustable="datalim") - one
    // units-per-pixel scale shared by both axes (the larger of the two
    // natural ones), so a 2D offset/trajectory plot isn't visually
    // distorted. Off by default (only meaningful for genuinely 2D data
    // like an offset plot, not e.g. a focus-vs-metric curve).
    Q_PROPERTY(bool equalAspect READ equalAspect WRITE setEqualAspect NOTIFY equalAspectChanged)
    // Thin, unlabeled gray lines at x=0 and y=0 - matplotlib's
    // axhline(0)/axvline(0) origin marker in the acquisition/guiding
    // offset plots. Deliberately a separate concept from
    // referenceX/referenceLabel below: that's one highlighted, labeled,
    // legend-worthy line (AutoFocusView.qml's fitted-focus result); this
    // is just an origin crosshair with no semantic result attached to it.
    Q_PROPERTY(bool originCrosshair READ originCrosshair WRITE setOriginCrosshair NOTIFY originCrosshairChanged)
    // Highlights points.first()/points.last() with a distinct marker
    // (red square / green star, matching pyobs-gui's own
    // acquisitionwidget.py/autoguidingwidget.py styling) drawn on top of
    // the regular series. Independently togglable since not every caller
    // wants both - AcquisitionView.qml's trajectory has a meaningful
    // fixed "start" (the first attempt), AutoGuidingView.qml's rolling
    // history (TODO.md) doesn't.
    Q_PROPERTY(bool showStartMarker READ showStartMarker WRITE setShowStartMarker NOTIFY showStartMarkerChanged)
    Q_PROPERTY(bool showLatestMarker READ showLatestMarker WRITE setShowLatestMarker NOTIFY showLatestMarkerChanged)
    // matplotlib's xaxis.set_major_locator(MaxNLocator(integer=True)) -
    // rounds x-axis tick positions to the nearest integer and skips
    // repeats, for axes that only ever hold whole numbers (e.g.
    // AcquisitionView.qml's "Attempt" axis).
    Q_PROPERTY(bool xTicksAsIntegers READ xTicksAsIntegers WRITE setXTicksAsIntegers NOTIFY xTicksAsIntegersChanged)
    // NaN (the default) means "no reference line" - QML's own NaN
    // literal, not a separate bool, matches how a not-yet-arrived
    // FocusFoundEvent is naturally "no result" without extra plumbing.
    Q_PROPERTY(double referenceX READ referenceX WRITE setReferenceX NOTIFY referenceXChanged)
    Q_PROPERTY(QString referenceLabel READ referenceLabel WRITE setReferenceLabel NOTIFY referenceLabelChanged)

    // Multi-series mode, additive to (and independent of) the single
    // implicit series above: CameraView.qml's "Plot temps" window (one
    // line per ITemperatures sensor, e.g. CCD/Back) needs several
    // simultaneously-drawn, independently-colored/labeled lines on one
    // chart, none of which come from a single already-arrived WireValue
    // array field the way `points`/xFieldIndex/yFieldIndex do - each
    // ITemperatures state update is only ever the latest snapshot (see
    // pyobs.interfaces.ITemperatures), so the caller accumulates a
    // growing points history client-side and hands it here already
    // shaped as plain {x, y} pairs, not a WireValue to decode. Each
    // `series` entry: {"label": string, "color": string (e.g.
    // "#f2a660"), "points": [{"x": double, "y": double}, ...]}. A small
    // legend is drawn automatically when this is non-empty. Extending
    // this class rather than forking a second plot item, per the class
    // comment above.
    Q_PROPERTY(QVariantList series READ series WRITE setSeries NOTIFY seriesChanged)
    // matplotlib's DateFormatter equivalent for the x axis - ticks are
    // seconds-since-epoch (matching QDateTime::currentSecsSinceEpoch(),
    // what CameraView.qml's history buffer stores), formatted "HH:mm:ss"
    // instead of PlotItem's usual plain-number formatTick(). Only
    // meaningful together with `series`'s time-series use case - AutoFocus/
    // Acquisition's plots stay on the default numeric formatting.
    Q_PROPERTY(bool xTicksAsTime READ xTicksAsTime WRITE setXTicksAsTime NOTIFY xTicksAsTimeChanged)

public:
    explicit PlotItem(QQuickItem *parent = nullptr);

    QVariant points() const { return m_pointsRaw; }
    void setPoints(const QVariant &points);

    // Parsed-output accessors, not QML-visible - paint() is otherwise the
    // only consumer of m_points, and QQuickPaintedItem gives no way to
    // introspect what it painted, so tests need these to assert
    // setPoints()/field-index/null-skipping actually produced the right
    // values instead of only checking "didn't crash".
    int pointCount() const { return m_points.size(); }
    QPointF pointAt(int index) const { return m_points.value(index); }

    int xFieldIndex() const { return m_xFieldIndex; }
    void setXFieldIndex(int index);

    int yFieldIndex() const { return m_yFieldIndex; }
    void setYFieldIndex(int index);

    double xScale() const { return m_xScale; }
    void setXScale(double scale);

    double yScale() const { return m_yScale; }
    void setYScale(double scale);

    QString xLabel() const { return m_xLabel; }
    void setXLabel(const QString &label);

    QString yLabel() const { return m_yLabel; }
    void setYLabel(const QString &label);

    bool showLine() const { return m_showLine; }
    void setShowLine(bool show);

    bool equalAspect() const { return m_equalAspect; }
    void setEqualAspect(bool equal);

    bool originCrosshair() const { return m_originCrosshair; }
    void setOriginCrosshair(bool show);

    bool showStartMarker() const { return m_showStartMarker; }
    void setShowStartMarker(bool show);

    bool showLatestMarker() const { return m_showLatestMarker; }
    void setShowLatestMarker(bool show);

    bool xTicksAsIntegers() const { return m_xTicksAsIntegers; }
    void setXTicksAsIntegers(bool integers);

    double referenceX() const { return m_referenceX; }
    void setReferenceX(double x);

    QString referenceLabel() const { return m_referenceLabel; }
    void setReferenceLabel(const QString &label);

    QVariantList series() const { return m_seriesRaw; }
    void setSeries(const QVariantList &series);

    // Parsed-output accessors, same "tests need to see past paint()"
    // reasoning as pointCount()/pointAt() above.
    int seriesCount() const { return m_series.size(); }
    QString seriesLabel(int index) const { return m_series.value(index).label; }
    QColor seriesColor(int index) const { return m_series.value(index).color; }
    int seriesPointCount(int index) const { return m_series.value(index).points.size(); }
    QPointF seriesPointAt(int seriesIndex, int pointIndex) const
    {
        return m_series.value(seriesIndex).points.value(pointIndex);
    }

    bool xTicksAsTime() const { return m_xTicksAsTime; }
    void setXTicksAsTime(bool asTime);

    void paint(QPainter *painter) override;

protected:
    // paint() reads width()/height() directly (for the plot-area margins),
    // so a resize needs an explicit repaint - QQuickPaintedItem doesn't
    // trigger one on its own just because the item's geometry changed.
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

Q_SIGNALS:
    void pointsChanged();
    void xFieldIndexChanged();
    void yFieldIndexChanged();
    void xScaleChanged();
    void yScaleChanged();
    void xLabelChanged();
    void yLabelChanged();
    void showLineChanged();
    void equalAspectChanged();
    void originCrosshairChanged();
    void showStartMarkerChanged();
    void showLatestMarkerChanged();
    void xTicksAsIntegersChanged();
    void referenceXChanged();
    void referenceLabelChanged();
    void seriesChanged();
    void xTicksAsTimeChanged();

private:
    // One named/colored line for multi-series mode (see `series`'s own
    // doc comment above) - already-shaped {x, y} pairs, no field-index
    // parsing (unlike m_points/reparsePoints() below).
    struct Series {
        QString label;
        QColor color;
        QVector<QPointF> points;
    };

    void reparsePoints();
    void reparseSeries();

    QVariant m_pointsRaw;
    QVector<QPointF> m_points;
    int m_xFieldIndex = 0;
    int m_yFieldIndex = 1;
    double m_xScale = 1.0;
    double m_yScale = 1.0;
    QString m_xLabel;
    QString m_yLabel;
    bool m_showLine = false;
    bool m_equalAspect = false;
    bool m_originCrosshair = false;
    bool m_showStartMarker = false;
    bool m_showLatestMarker = false;
    bool m_xTicksAsIntegers = false;
    double m_referenceX = std::numeric_limits<double>::quiet_NaN();
    QString m_referenceLabel;
    QVariantList m_seriesRaw;
    QVector<Series> m_series;
    bool m_xTicksAsTime = false;
};

}
