#include "ModuleListModel.h"

namespace comm {

ModuleListModel::ModuleListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ModuleListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_modules.size();
}

QVariant ModuleListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_modules.size()) {
        return {};
    }
    const ModuleInfo &info = m_modules.at(index.row());
    switch (role) {
    case JidRole:
        return info.jid;
    case NameRole:
        return info.name;
    default:
        return {};
    }
}

QHash<int, QByteArray> ModuleListModel::roleNames() const
{
    return {
        { JidRole, "jid" },
        { NameRole, "name" },
    };
}

void ModuleListModel::upsert(const ModuleInfo &info)
{
    for (int i = 0; i < m_modules.size(); ++i) {
        if (m_modules.at(i).jid == info.jid) {
            m_modules[i] = info;
            const QModelIndex idx = index(i);
            Q_EMIT dataChanged(idx, idx);
            return;
        }
    }

    const int row = m_modules.size();
    beginInsertRows(QModelIndex(), row, row);
    m_modules.push_back(info);
    endInsertRows();
}

void ModuleListModel::remove(const QString &bareJid)
{
    for (int i = 0; i < m_modules.size(); ++i) {
        if (m_modules.at(i).jid == bareJid) {
            beginRemoveRows(QModelIndex(), i, i);
            m_modules.removeAt(i);
            endRemoveRows();
            return;
        }
    }
}

void ModuleListModel::clear()
{
    if (m_modules.isEmpty()) {
        return;
    }
    beginResetModel();
    m_modules.clear();
    endResetModel();
}

}
