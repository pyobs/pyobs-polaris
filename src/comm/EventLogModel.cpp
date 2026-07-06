#include "EventLogModel.h"

namespace comm {

EventLogModel::EventLogModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int EventLogModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_events.size();
}

QVariant EventLogModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_events.size()) {
        return {};
    }
    const PyobsEvent &event = m_events.at(index.row());
    switch (role) {
    case TypeRole:
        return event.type;
    case ModuleRole:
        return event.module;
    case TimestampRole:
        return event.timestamp;
    case UuidRole:
        return event.uuid;
    case DataRole:
        return event.data.toVariantMap();
    default:
        return {};
    }
}

QHash<int, QByteArray> EventLogModel::roleNames() const
{
    return {
        { TypeRole, "type" },
        { ModuleRole, "module" },
        { TimestampRole, "timestamp" },
        { UuidRole, "uuid" },
        { DataRole, "data" },
    };
}

void EventLogModel::append(const PyobsEvent &event)
{
    const int overflow = m_events.size() + 1 - kMaxEvents;
    if (overflow > 0) {
        beginRemoveRows(QModelIndex(), 0, overflow - 1);
        m_events.remove(0, overflow);
        endRemoveRows();
    }

    const int row = m_events.size();
    beginInsertRows(QModelIndex(), row, row);
    m_events.push_back(event);
    endInsertRows();
}

QVariantList EventLogModel::entriesOfType(const QString &type) const
{
    QVariantList result;
    for (const PyobsEvent &event : m_events) {
        if (event.type != type) {
            continue;
        }
        QVariantMap entry;
        entry.insert(QStringLiteral("type"), event.type);
        entry.insert(QStringLiteral("module"), event.module);
        entry.insert(QStringLiteral("timestamp"), event.timestamp);
        entry.insert(QStringLiteral("uuid"), event.uuid);
        entry.insert(QStringLiteral("data"), event.data.toVariantMap());
        result.append(entry);
    }
    return result;
}

void EventLogModel::clear()
{
    if (m_events.isEmpty()) {
        return;
    }
    beginResetModel();
    m_events.clear();
    endResetModel();
}

}
