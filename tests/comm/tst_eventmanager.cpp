#include <QDateTime>
#include <QDomDocument>
#include <QTest>

#include <QXmppClient.h>

#include "EventLogModel.h"
#include "EventManager.h"

using namespace comm;

namespace {

QDomElement eventNotification(const QString &node, const QString &jsonPayload)
{
    QDomDocument doc;
    const QString xml = QStringLiteral(
                             "<message from='roof@localhost' to='me@localhost'>"
                             "<event xmlns='http://jabber.org/protocol/pubsub#event'>"
                             "<items node='%1'><item>"
                             "<event xmlns='pyobs:event'>%2</event>"
                             "</item></items>"
                             "</event>"
                             "</message>")
                             .arg(node, jsonPayload.toHtmlEscaped());
    doc.setContent(xml, QDomDocument::ParseOption::UseNamespaceProcessing);
    return doc.documentElement();
}

}

class TestEventManager : public QObject
{
    Q_OBJECT

private slots:
    void logModelCapsAtMaxEvents();
    void decodesAndAppendsAnEvent();
    void ignoresNonEventNodes();
    void entriesOfTypeFiltersAndShapesCorrectly();
    void ignoresStaleEvents();
};

void TestEventManager::logModelCapsAtMaxEvents()
{
    EventLogModel log;
    for (int i = 0; i < 505; ++i) {
        PyobsEvent event;
        event.type = QStringLiteral("TestEvent");
        event.uuid = QString::number(i);
        log.append(event);
    }

    // Cap is 500 (matches useXmpp.ts's MAX_EVENTS); oldest 5 dropped, so
    // the surviving first entry should be uuid "5", not "0".
    QCOMPARE(log.rowCount(), 500);
    QCOMPARE(log.data(log.index(0), EventLogModel::UuidRole).toString(), QStringLiteral("5"));
    QCOMPARE(log.data(log.index(499), EventLogModel::UuidRole).toString(), QStringLiteral("504"));
}

void TestEventManager::decodesAndAppendsAnEvent()
{
    QXmppClient client(QXmppClient::NoExtensions);
    EventLogModel log;
    auto *manager = client.addNewExtension<EventManager>(&log);

    const QString node = QStringLiteral("urn:pyobs:event:LogEvent:1");
    // Fresh timestamp, not a fixed old one - handlePubSubEvent now discards
    // anything older than 30 seconds (see ignoresStaleEvents()), matching
    // xmppcomm.py's own _handle_event().
    const double now = static_cast<double>(QDateTime::currentSecsSinceEpoch());
    const QString json = QStringLiteral(
        R"({"type":"LogEvent","timestamp":%1,"uuid":"abc-123","data":{"level":"INFO","message":"hello"}})")
        .arg(now, 0, 'f');

    QVERIFY(manager->handlePubSubEvent(eventNotification(node, json), QStringLiteral("roof@localhost"), node));

    QCOMPARE(log.rowCount(), 1);
    const QModelIndex idx = log.index(0);
    QCOMPARE(log.data(idx, EventLogModel::TypeRole).toString(), QStringLiteral("LogEvent"));
    QCOMPARE(log.data(idx, EventLogModel::ModuleRole).toString(), QStringLiteral("roof"));
    QCOMPARE(log.data(idx, EventLogModel::TimestampRole).toDouble(), now);
    QCOMPARE(log.data(idx, EventLogModel::UuidRole).toString(), QStringLiteral("abc-123"));
    const QVariantMap data = log.data(idx, EventLogModel::DataRole).toMap();
    QCOMPARE(data.value(QStringLiteral("level")).toString(), QStringLiteral("INFO"));
    QCOMPARE(data.value(QStringLiteral("message")).toString(), QStringLiteral("hello"));
}

void TestEventManager::ignoresNonEventNodes()
{
    QXmppClient client(QXmppClient::NoExtensions);
    EventLogModel log;
    auto *manager = client.addNewExtension<EventManager>(&log);

    // A state notification (Phase 4's node prefix), not an event - must be
    // ignored here, not conflated with the event path.
    const QString node = QStringLiteral("pyobs:state:roof:IMotion:1");
    QVERIFY(!manager->handlePubSubEvent(eventNotification(node, QStringLiteral("{}")), QStringLiteral("roof@localhost"), node));
    QCOMPARE(log.rowCount(), 0);
}

void TestEventManager::entriesOfTypeFiltersAndShapesCorrectly()
{
    EventLogModel log;

    PyobsEvent logEvent;
    logEvent.type = QStringLiteral("LogEvent");
    logEvent.module = QStringLiteral("roof");
    logEvent.timestamp = 111.0;
    logEvent.uuid = QStringLiteral("log-1");
    QJsonObject data;
    data.insert(QStringLiteral("level"), QStringLiteral("INFO"));
    data.insert(QStringLiteral("message"), QStringLiteral("hello"));
    logEvent.data = data;
    log.append(logEvent);

    PyobsEvent otherEvent;
    otherEvent.type = QStringLiteral("MotionStatusChangedEvent");
    otherEvent.module = QStringLiteral("roof");
    log.append(otherEvent);

    const QVariantList entries = log.entriesOfType(QStringLiteral("LogEvent"));
    QCOMPARE(entries.size(), 1);
    const QVariantMap entry = entries.first().toMap();
    QCOMPARE(entry.value(QStringLiteral("type")).toString(), QStringLiteral("LogEvent"));
    QCOMPARE(entry.value(QStringLiteral("module")).toString(), QStringLiteral("roof"));
    QCOMPARE(entry.value(QStringLiteral("timestamp")).toDouble(), 111.0);
    QCOMPARE(entry.value(QStringLiteral("uuid")).toString(), QStringLiteral("log-1"));
    const QVariantMap entryData = entry.value(QStringLiteral("data")).toMap();
    QCOMPARE(entryData.value(QStringLiteral("level")).toString(), QStringLiteral("INFO"));
    QCOMPARE(entryData.value(QStringLiteral("message")).toString(), QStringLiteral("hello"));

    QVERIFY(log.entriesOfType(QStringLiteral("NoSuchEvent")).isEmpty());
}

void TestEventManager::ignoresStaleEvents()
{
    QXmppClient client(QXmppClient::NoExtensions);
    EventLogModel log;
    auto *manager = client.addNewExtension<EventManager>(&log);

    // Discovered live (see DEVELOPMENT.md): subscribing to a PEP node makes
    // ejabberd immediately replay its last published item as a catch-up
    // delivery, "from" the shared pubsub component rather than the real
    // publisher - matches xmppcomm.py's own _handle_event() 30-second
    // staleness guard ("avoid resent events after a reconnect") exactly.
    const QString node = QStringLiteral("urn:pyobs:event:LogEvent:1");
    const double old = static_cast<double>(QDateTime::currentSecsSinceEpoch() - 31);
    const QString json = QStringLiteral(
        R"({"type":"LogEvent","timestamp":%1,"uuid":"stale-1","data":{}})")
        .arg(old, 0, 'f');

    // Still "handled" (it's a real pyobs event node) - just not logged.
    QVERIFY(manager->handlePubSubEvent(eventNotification(node, json), QStringLiteral("pubsub.localhost"), node));
    QCOMPARE(log.rowCount(), 0);
}

QTEST_MAIN(TestEventManager)
#include "tst_eventmanager.moc"
