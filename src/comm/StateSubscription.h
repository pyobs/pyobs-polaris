#pragma once

#include <QObject>
#include <QVariant>
#include <qqmlintegration.h>

namespace comm {

class StateSubscriptionManager;

// RAII handle for one ref-counted PubSub state subscription - mirrors
// useXmpp.ts's subscribeState()'s `{ value, unsubscribe }` return shape,
// but via C++ object lifetime instead of a caller-remembered cleanup call:
// destroying this object (e.g. a KeyValueCard's QML Component going away)
// releases the ref automatically. unsubscribe() is also exposed explicitly
// for deterministic control (tests, or QML's Component.onDestruction).
class StateSubscription : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Created via XmppClient::subscribeState()")
    Q_PROPERTY(QVariant value READ value NOTIFY valueChanged)

public:
    ~StateSubscription() override;

    QVariant value() const { return m_value; }

    Q_INVOKABLE void unsubscribe();

Q_SIGNALS:
    void valueChanged();

private:
    friend class StateSubscriptionManager;

    StateSubscription(StateSubscriptionManager *manager, QString node, QObject *parent);

    void notifyValueChanged(const QVariant &value);

    StateSubscriptionManager *m_manager;
    QString m_node;
    QVariant m_value;
    bool m_unsubscribed = false;
};

}
