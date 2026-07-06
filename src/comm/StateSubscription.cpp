#include "StateSubscription.h"

#include "StateSubscriptionManager.h"

namespace comm {

StateSubscription::StateSubscription(StateSubscriptionManager *manager, QString node, QObject *parent)
    : QObject(parent)
    , m_manager(manager)
    , m_node(std::move(node))
{
}

StateSubscription::~StateSubscription()
{
    unsubscribe();
}

void StateSubscription::unsubscribe()
{
    if (m_unsubscribed) {
        return;
    }
    m_unsubscribed = true;
    m_manager->release(m_node, this);
}

void StateSubscription::notifyValueChanged(const QVariant &value)
{
    m_value = value;
    Q_EMIT valueChanged();
}

}
