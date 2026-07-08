#include "ModuleListModel.h"

#include <QVariantList>
#include <QVariantMap>

namespace comm {

namespace {

// Shared by CommandSchemasRole and allCommands() - both need the same
// {name, type, unit, optional} shape per FieldSchema (see
// CommandSchemasRole's own doc comment for why "type" is unwrapped rather
// than shown as "optional<...>").
QVariantList paramsToVariantList(const QVector<codec::FieldSchema> &params)
{
    QVariantList result;
    for (const codec::FieldSchema &field : params) {
        const bool optional = field.type.kind() == codec::WireType::Kind::Optional;
        QVariantMap param;
        param.insert(QStringLiteral("name"), field.name);
        param.insert(QStringLiteral("type"), codec::wireTypeToString(optional ? field.type.inner() : field.type));
        param.insert(QStringLiteral("unit"), field.unit);
        param.insert(QStringLiteral("optional"), optional);
        result.push_back(param);
    }
    return result;
}

}

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
    case StatefulInterfacesRole: {
        QVariantList result;
        for (auto it = info.interfaces.constBegin(); it != info.interfaces.constEnd(); ++it) {
            if (!it.value().state) {
                continue;
            }
            QVariantMap entry;
            entry.insert(QStringLiteral("name"), it.value().name);
            entry.insert(QStringLiteral("version"), it.value().version);
            result.push_back(entry);
        }
        return result;
    }
    case CommandsRole: {
        QVariantList result;
        for (auto it = info.interfaces.constBegin(); it != info.interfaces.constEnd(); ++it) {
            for (auto cmdIt = it.value().commands.constBegin(); cmdIt != it.value().commands.constEnd(); ++cmdIt) {
                QVariantMap entry;
                entry.insert(QStringLiteral("interface"), it.value().name);
                entry.insert(QStringLiteral("name"), cmdIt.value().name);
                entry.insert(QStringLiteral("paramCount"), cmdIt.value().params.size());
                result.push_back(entry);
            }
        }
        return result;
    }
    case CommandSchemasRole: {
        QVariantList result;
        for (auto it = info.interfaces.constBegin(); it != info.interfaces.constEnd(); ++it) {
            for (auto cmdIt = it.value().commands.constBegin(); cmdIt != it.value().commands.constEnd(); ++cmdIt) {
                QVariantMap entry;
                entry.insert(QStringLiteral("interface"), it.value().name);
                entry.insert(QStringLiteral("name"), cmdIt.value().name);
                entry.insert(QStringLiteral("params"), paramsToVariantList(cmdIt.value().params));
                result.push_back(entry);
            }
        }
        return result;
    }
    case VersionRole: {
        const auto it = info.capabilities.constFind(QStringLiteral("IModule"));
        if (it == info.capabilities.constEnd() || !it.value().isDict()) {
            return QString();
        }
        for (const auto &field : it.value().toDict()) {
            if (field.first == QStringLiteral("version") && field.second.isString()) {
                return field.second.toString();
            }
        }
        return QString();
    }
    case ModeGroupsRole: {
        QVariantList result;
        const auto it = info.capabilities.constFind(QStringLiteral("IMode"));
        if (it == info.capabilities.constEnd() || !it.value().isDict()) {
            return result;
        }
        for (const auto &field : it.value().toDict()) {
            if (field.first != QStringLiteral("modes") || !field.second.isDict()) {
                continue;
            }
            for (const auto &group : field.second.toDict()) {
                QVariantList modes;
                if (group.second.isList()) {
                    for (const codec::WireValue &mode : group.second.toList()) {
                        if (mode.isString()) {
                            modes.push_back(mode.toString());
                        }
                    }
                }
                QVariantMap entry;
                entry.insert(QStringLiteral("group"), group.first);
                entry.insert(QStringLiteral("modes"), modes);
                result.push_back(entry);
            }
        }
        return result;
    }
    case PresenceStateRole:
        return info.presenceState;
    case PresenceErrorRole:
        return info.presenceError;
    default:
        return {};
    }
}

QHash<int, QByteArray> ModuleListModel::roleNames() const
{
    return {
        { JidRole, "jid" },
        { NameRole, "name" },
        { StatefulInterfacesRole, "statefulInterfaces" },
        { CommandsRole, "commands" },
        { CommandSchemasRole, "commandSchemas" },
        { VersionRole, "version" },
        { ModeGroupsRole, "modeGroups" },
        { PresenceStateRole, "presenceState" },
        { PresenceErrorRole, "presenceError" },
    };
}

const ModuleInfo *ModuleListModel::find(const QString &bareJid) const
{
    for (const ModuleInfo &info : m_modules) {
        if (info.jid == bareJid) {
            return &info;
        }
    }
    return nullptr;
}

QString ModuleListModel::jidForModuleName(const QString &moduleName) const
{
    for (const ModuleInfo &info : m_modules) {
        if (info.jid.section(QLatin1Char('@'), 0, 0) == moduleName) {
            return info.jid;
        }
    }
    return QString();
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

bool ModuleListModel::updatePresence(const QString &bareJid, const QString &state, const QString &errorText)
{
    for (int i = 0; i < m_modules.size(); ++i) {
        if (m_modules.at(i).jid == bareJid) {
            m_modules[i].presenceState = state;
            m_modules[i].presenceError = errorText;
            const QModelIndex idx = index(i);
            Q_EMIT dataChanged(idx, idx, { PresenceStateRole, PresenceErrorRole });
            return true;
        }
    }
    return false;
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

bool ModuleListModel::hasInterface(const QString &interfaceName) const
{
    for (const ModuleInfo &info : m_modules) {
        if (info.interfaces.contains(interfaceName)) {
            return true;
        }
    }
    return false;
}

QVariantList ModuleListModel::allCommands() const
{
    QVariantList result;
    for (const ModuleInfo &info : m_modules) {
        const QString moduleName = info.jid.section(QLatin1Char('@'), 0, 0);

        // QMap<QString, CommandSchema>, so insertion order doesn't matter -
        // "first interface wins" falls out of iterating info.interfaces (a
        // QMap sorted by interface name) and skipping a command name
        // already seen, the same order/convention XmppClient::executeMethod()
        // uses to resolve dispatch.
        QMap<QString, codec::CommandSchema> byName;
        for (auto it = info.interfaces.constBegin(); it != info.interfaces.constEnd(); ++it) {
            for (auto cmdIt = it.value().commands.constBegin(); cmdIt != it.value().commands.constEnd(); ++cmdIt) {
                if (!byName.contains(cmdIt.key())) {
                    byName.insert(cmdIt.key(), cmdIt.value());
                }
            }
        }

        for (auto cmdIt = byName.constBegin(); cmdIt != byName.constEnd(); ++cmdIt) {
            QVariantMap entry;
            entry.insert(QStringLiteral("module"), moduleName);
            entry.insert(QStringLiteral("name"), cmdIt.key());
            entry.insert(QStringLiteral("params"), paramsToVariantList(cmdIt.value().params));
            result.push_back(entry);
        }
    }
    return result;
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
