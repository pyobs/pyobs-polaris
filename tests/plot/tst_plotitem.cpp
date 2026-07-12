#include <QColor>
#include <QTest>
#include <QVariantList>
#include <QVariantMap>

#include "PlotItem.h"

using namespace plot;

namespace {

// Builds one {"key":..,"value":..}-entry-list record, matching
// codec::toQVariant's dataclass-shaped output - see PlotItem.h's own doc
// comment on why parsing happens against exactly this shape.
QVariant field(const QString &key, const QVariant &value)
{
    QVariantMap entry;
    entry.insert(QStringLiteral("key"), key);
    entry.insert(QStringLiteral("value"), value);
    return entry;
}

QVariant record(std::initializer_list<QVariant> fields)
{
    return QVariantList(fields);
}

}

class TestPlotItem : public QObject
{
    Q_OBJECT

private slots:
    void defaultFieldIndices();
    void customFieldIndices();
    void skipsRecordsWithNullSelectedField();
    void skipsShortRecords();
    void emptyOrInvalidPointsIsEmpty();
    void seriesParsesLabelColorAndPoints();
    void seriesAssignsDefaultColorWhenNoneGiven();
    void seriesSkipsPointsWithMissingXOrY();
    void emptyOrInvalidSeriesIsEmpty();
};

void TestPlotItem::defaultFieldIndices()
{
    // AutoFocusPoint-shaped: {focus, value} - the default 0/1 indices
    // need no configuration for this, matching AutoFocusView.qml.
    PlotItem item;
    QCOMPARE(item.xFieldIndex(), 0);
    QCOMPARE(item.yFieldIndex(), 1);

    QVariantList points;
    points << record({ field(QStringLiteral("focus"), 9.8), field(QStringLiteral("value"), 3.2) });
    points << record({ field(QStringLiteral("focus"), 10.0), field(QStringLiteral("value"), 3.0) });
    item.setPoints(points);

    QCOMPARE(item.pointCount(), 2);
    QCOMPARE(item.pointAt(0), QPointF(9.8, 3.2));
    QCOMPARE(item.pointAt(1), QPointF(10.0, 3.0));
}

void TestPlotItem::customFieldIndices()
{
    // AcquisitionAttempt-shaped: {attempt, distance, offset_applied,
    // offset_frame, offset_lon, offset_lat} - the offset-trajectory plot
    // needs indices 4/5, not the default 0/1.
    PlotItem item;
    item.setXFieldIndex(4);
    item.setYFieldIndex(5);
    QCOMPARE(item.xFieldIndex(), 4);
    QCOMPARE(item.yFieldIndex(), 5);

    QVariantList points;
    points << record({
        field(QStringLiteral("attempt"), 1),
        field(QStringLiteral("distance"), 60.0),
        field(QStringLiteral("offset_applied"), true),
        field(QStringLiteral("offset_frame"), QStringLiteral("radec")),
        field(QStringLiteral("offset_lon"), 0.01),
        field(QStringLiteral("offset_lat"), -0.02),
    });
    item.setPoints(points);

    QCOMPARE(item.pointCount(), 1);
    QCOMPARE(item.pointAt(0), QPointF(0.01, -0.02));
}

void TestPlotItem::skipsRecordsWithNullSelectedField()
{
    // AcquisitionAttempt's offset_lon/offset_lat are optional<float64> -
    // a null WireValue bridges to an invalid QVariant (see
    // codec::toQVariant), which setPoints() must skip rather than plot
    // as (0, 0).
    PlotItem item;
    item.setXFieldIndex(4);
    item.setYFieldIndex(5);

    QVariantList points;
    points << record({
        field(QStringLiteral("attempt"), 1),
        field(QStringLiteral("distance"), 60.0),
        field(QStringLiteral("offset_applied"), false),
        field(QStringLiteral("offset_frame"), QVariant()),
        field(QStringLiteral("offset_lon"), QVariant()),
        field(QStringLiteral("offset_lat"), QVariant()),
    });
    points << record({
        field(QStringLiteral("attempt"), 2),
        field(QStringLiteral("distance"), 20.0),
        field(QStringLiteral("offset_applied"), true),
        field(QStringLiteral("offset_frame"), QStringLiteral("radec")),
        field(QStringLiteral("offset_lon"), 0.005),
        field(QStringLiteral("offset_lat"), -0.01),
    });
    item.setPoints(points);

    // Only the second record (real offset values) should survive.
    QCOMPARE(item.pointCount(), 1);
    QCOMPARE(item.pointAt(0), QPointF(0.005, -0.01));
}

void TestPlotItem::skipsShortRecords()
{
    PlotItem item;
    item.setXFieldIndex(4);
    item.setYFieldIndex(5);

    QVariantList points;
    // Only 2 fields - shorter than yFieldIndex=5 requires.
    points << record({ field(QStringLiteral("attempt"), 1), field(QStringLiteral("distance"), 60.0) });
    item.setPoints(points);

    QCOMPARE(item.pointCount(), 0);
}

void TestPlotItem::emptyOrInvalidPointsIsEmpty()
{
    PlotItem item;
    item.setPoints(QVariant());
    QCOMPARE(item.pointCount(), 0);

    item.setPoints(QVariantList {});
    QCOMPARE(item.pointCount(), 0);
}

void TestPlotItem::seriesParsesLabelColorAndPoints()
{
    QVariantMap ccdPoint1;
    ccdPoint1.insert(QStringLiteral("x"), 1.0);
    ccdPoint1.insert(QStringLiteral("y"), -10.0);
    QVariantMap ccdPoint2;
    ccdPoint2.insert(QStringLiteral("x"), 2.0);
    ccdPoint2.insert(QStringLiteral("y"), -11.5);

    QVariantMap ccdSeries;
    ccdSeries.insert(QStringLiteral("label"), QStringLiteral("CCD"));
    ccdSeries.insert(QStringLiteral("color"), QStringLiteral("#ff0000"));
    ccdSeries.insert(QStringLiteral("points"), QVariantList { ccdPoint1, ccdPoint2 });

    PlotItem item;
    item.setSeries(QVariantList { ccdSeries });

    QCOMPARE(item.seriesCount(), 1);
    QCOMPARE(item.seriesLabel(0), QStringLiteral("CCD"));
    QCOMPARE(item.seriesColor(0), QColor(QStringLiteral("#ff0000")));
    QCOMPARE(item.seriesPointCount(0), 2);
    QCOMPARE(item.seriesPointAt(0, 0), QPointF(1.0, -10.0));
    QCOMPARE(item.seriesPointAt(0, 1), QPointF(2.0, -11.5));
}

void TestPlotItem::seriesAssignsDefaultColorWhenNoneGiven()
{
    QVariantMap series;
    series.insert(QStringLiteral("label"), QStringLiteral("Back"));
    series.insert(QStringLiteral("points"), QVariantList {});

    PlotItem item;
    item.setSeries(QVariantList { series });

    QCOMPARE(item.seriesCount(), 1);
    QVERIFY(item.seriesColor(0).isValid());
}

void TestPlotItem::seriesSkipsPointsWithMissingXOrY()
{
    QVariantMap validPoint;
    validPoint.insert(QStringLiteral("x"), 1.0);
    validPoint.insert(QStringLiteral("y"), 2.0);
    QVariantMap missingY;
    missingY.insert(QStringLiteral("x"), 3.0);

    QVariantMap series;
    series.insert(QStringLiteral("label"), QStringLiteral("CCD"));
    series.insert(QStringLiteral("points"), QVariantList { validPoint, missingY });

    PlotItem item;
    item.setSeries(QVariantList { series });

    QCOMPARE(item.seriesPointCount(0), 1);
    QCOMPARE(item.seriesPointAt(0, 0), QPointF(1.0, 2.0));
}

void TestPlotItem::emptyOrInvalidSeriesIsEmpty()
{
    PlotItem item;
    QCOMPARE(item.seriesCount(), 0);

    item.setSeries(QVariantList {});
    QCOMPARE(item.seriesCount(), 0);
}

QTEST_MAIN(TestPlotItem)
#include "tst_plotitem.moc"
