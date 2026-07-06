#include <QDomDocument>
#include <QSignalSpy>
#include <QTest>

#include <QXmppClient.h>
#include <QXmppPubSubManager.h>

#include "StateSubscription.h"
#include "StateSubscriptionManager.h"

using namespace comm;

namespace {

// Synthesizes the <message> stanza ejabberd sends for a PubSub item
// notification, matching handlePubSubEvent()'s expected shape
// (event/items/item/payload).
QDomElement stateNotification(const QString &node, const QString &payloadXml)
{
    QDomDocument doc;
    const QString xml = QStringLiteral(
                             "<message from='pubsub.localhost' to='me@localhost'>"
                             "<event xmlns='http://jabber.org/protocol/pubsub#event'>"
                             "<items node='%1'><item>%2</item></items>"
                             "</event>"
                             "</message>")
                             .arg(node, payloadXml);
    doc.setContent(xml, QDomDocument::ParseOption::UseNamespaceProcessing);
    return doc.documentElement();
}

}

// The bug this specifically guards against: it's invisible with a single
// watcher, and only shows up once two widgets watch the same state (see
// DEVELOPMENT.md Phase 4) - unsubscribing the first must not silently kill
// live updates for the second.
class TestStateSubscription : public QObject
{
    Q_OBJECT

private slots:
    void doubleSubscribeSingleUnsubscribe();
};

void TestStateSubscription::doubleSubscribeSingleUnsubscribe()
{
    QXmppClient client(QXmppClient::NoExtensions);
    client.addNewExtension<QXmppPubSubManager>(); // subscribe()/release() call through this
    auto *manager = client.addNewExtension<StateSubscriptionManager>();

    QObject owner;
    StateSubscription *watcherA = manager->subscribe(QStringLiteral("telescope@localhost"),
                                                       QStringLiteral("IMotion"), 1, &owner);
    StateSubscription *watcherB = manager->subscribe(QStringLiteral("telescope@localhost"),
                                                       QStringLiteral("IMotion"), 1, &owner);
    QVERIFY(watcherA != watcherB);

    const QString node = QStringLiteral("pyobs:state:telescope:IMotion:1");
    QSignalSpy spyA(watcherA, &StateSubscription::valueChanged);
    QSignalSpy spyB(watcherB, &StateSubscription::valueChanged);

    // A live push arrives - both watchers of the same node see it.
    QVERIFY(manager->handlePubSubEvent(stateNotification(node, "<int>42</int>"), QStringLiteral("pubsub.localhost"), node));
    QCOMPARE(spyA.count(), 1);
    QCOMPARE(spyB.count(), 1);
    QCOMPARE(watcherA->value().toLongLong(), 42);
    QCOMPARE(watcherB->value().toLongLong(), 42);

    // Unsubscribing A must not affect B: this is the actual ref-counting
    // guarantee under test.
    watcherA->unsubscribe();

    QVERIFY(manager->handlePubSubEvent(stateNotification(node, "<int>99</int>"), QStringLiteral("pubsub.localhost"), node));
    QCOMPARE(spyA.count(), 1); // unchanged - A no longer watches
    QCOMPARE(spyB.count(), 2); // B still does
    QCOMPARE(watcherA->value().toLongLong(), 42); // frozen at its last value
    QCOMPARE(watcherB->value().toLongLong(), 99);

    // Now the last watcher unsubscribes too - the node is fully released.
    watcherB->unsubscribe();

    manager->handlePubSubEvent(stateNotification(node, "<int>7</int>"), QStringLiteral("pubsub.localhost"), node);
    QCOMPARE(spyA.count(), 1);
    QCOMPARE(spyB.count(), 2); // neither watcher reacts anymore
}

QTEST_MAIN(TestStateSubscription)
#include "tst_statesubscription.moc"
