#pragma once

#include <QPointF>
#include <QQuickPaintedItem>
#include <QVariant>
#include <QVector>
#include <limits>
#include <qqmlintegration.h>

namespace plot {

// Minimal hand-rolled scatter plot - see TODO.md's "no external plotting
// library" decision (QtCharts/QtGraphs are GPL-or-commercial only,
// QCustomPlot the same, Qwt is QWidgets-based) and DEVELOPMENT.md's
// QQuickPaintedItem-over-Canvas rationale. Deliberately only what
// AutoFocusView.qml's focus-curve plot needs today: one scatter series,
// axes/gridlines/tick labels, and one optional vertical reference line
// (the fitted-focus result). Extend rather than speculatively generalize
// when the acquisition/guiding plots (TODO.md) need more - a connecting
// line, a second series, equal-aspect 2D scaling.
class PlotItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

    // Raw decoded value of an array<struct<...>> WireValue field (e.g.
    // StateSubscription::field("points")) - a QVariantList of records,
    // each record itself a QVariantList of {"key":..,"value":..} entries
    // in wire/declaration order (see codec::toQVariant / WireValue.h).
    // Parsed entirely in C++ (setPoints()): a record's *first* field is
    // plotted as x, the *second* as y - not looked up by name, since wire
    // order is exactly what this project's codec preserves dict/dataclass
    // fields for everywhere else (e.g. IAutoFocus's AutoFocusPoint{focus,
    // value} needs no extra configuration here as a result). Undefined/
    // invalid/empty all mean "no data yet".
    Q_PROPERTY(QVariant points READ points WRITE setPoints NOTIFY pointsChanged)
    Q_PROPERTY(QString xLabel READ xLabel WRITE setXLabel NOTIFY xLabelChanged)
    Q_PROPERTY(QString yLabel READ yLabel WRITE setYLabel NOTIFY yLabelChanged)
    // NaN (the default) means "no reference line" - QML's own NaN
    // literal, not a separate bool, matches how a not-yet-arrived
    // FocusFoundEvent is naturally "no result" without extra plumbing.
    Q_PROPERTY(double referenceX READ referenceX WRITE setReferenceX NOTIFY referenceXChanged)
    Q_PROPERTY(QString referenceLabel READ referenceLabel WRITE setReferenceLabel NOTIFY referenceLabelChanged)

public:
    explicit PlotItem(QQuickItem *parent = nullptr);

    QVariant points() const { return m_pointsRaw; }
    void setPoints(const QVariant &points);

    QString xLabel() const { return m_xLabel; }
    void setXLabel(const QString &label);

    QString yLabel() const { return m_yLabel; }
    void setYLabel(const QString &label);

    double referenceX() const { return m_referenceX; }
    void setReferenceX(double x);

    QString referenceLabel() const { return m_referenceLabel; }
    void setReferenceLabel(const QString &label);

    void paint(QPainter *painter) override;

protected:
    // paint() reads width()/height() directly (for the plot-area margins),
    // so a resize needs an explicit repaint - QQuickPaintedItem doesn't
    // trigger one on its own just because the item's geometry changed.
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

Q_SIGNALS:
    void pointsChanged();
    void xLabelChanged();
    void yLabelChanged();
    void referenceXChanged();
    void referenceLabelChanged();

private:
    QVariant m_pointsRaw;
    QVector<QPointF> m_points;
    QString m_xLabel;
    QString m_yLabel;
    double m_referenceX = std::numeric_limits<double>::quiet_NaN();
    QString m_referenceLabel;
};

}
