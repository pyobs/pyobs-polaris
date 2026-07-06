#pragma once

#include "ModuleInfo.h"

#include <QAbstractListModel>
#include <QVector>
#include <qqmlintegration.h>

namespace comm {

// The first point QML actually needs live C++ data (deferred from Phase 2,
// where ModuleInfo was still a plain, non-QML-bound struct). Phase 3 only
// needs JID + name (see DEVELOPMENT.md); more roles (interfaces, state,
// capabilities) get added once Phase 4 actually renders them, rather than
// exposing everything ModuleInfo already holds just because it's there.
class ModuleListModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Populated by XmppClient, not constructed directly in QML")

public:
    enum Role {
        JidRole = Qt::UserRole + 1,
        NameRole,
        // QVariantList of {"name":..., "version":...} entries, one per
        // interface that has a state block - Phase 4's KeyValueCard-per-
        // interface UI needs this to know what to call subscribeState()
        // for. Interfaces without a state block are omitted, not just
        // empty-stated, since there's nothing to render for them.
        StatefulInterfacesRole,
        // QVariantList of {"interface":..., "name":..., "paramCount":...}
        // entries, one per command across every interface - Phase 5's
        // debug panel needs this to let you pick a discovered command and
        // know how many null params to pass. Dispatch itself is by method
        // name alone (pyobs-core routes RPC calls without an interface
        // qualifier), so "interface" here is for display/grouping only.
        CommandsRole,
    };
    Q_ENUM(Role)

    explicit ModuleListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Adds a new module, or replaces the existing entry for the same bare
    // JID (a module re-announcing itself, or a fetchModuleInfo() reply
    // arriving for one already known from a live presence push).
    void upsert(const ModuleInfo &info);

    // Removes the module with this bare JID, if present (presence
    // type="unavailable"). No-op if it isn't in the list.
    void remove(const QString &bareJid);

    // Empties the whole list - matches useXmpp.ts's disconnect() resetting
    // its modules ref, called from XmppClient::disconnectFromServer().
    void clear();

private:
    QVector<ModuleInfo> m_modules;
};

}
