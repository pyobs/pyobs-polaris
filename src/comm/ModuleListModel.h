#pragma once

#include "ModuleInfo.h"

#include <QAbstractListModel>
#include <QVariantList>
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
        // QVariantList of {"interface":..., "name":..., "params":[{"name":
        // ..., "type":..., "unit":..., "optional":...}, ...]} entries, one
        // per command across every interface - the full CommandSchema
        // (unlike CommandsRole above, which condenses params down to a
        // bare count). Needed by the Shell rewrite's parser (to encode
        // positional args against each param's real WireType) and
        // autocomplete popup (to render param signatures). "type" is
        // already unwrapped of its Optional wrapper when "optional" is
        // true, matching how a real-param call site would encode it -
        // wireTypeToString() is the same disco#info-string renderer
        // Discovery.cpp's debug logging uses (see codec::WireType.h),
        // reused rather than duplicated. Complements, not replaces,
        // CommandsRole - ShellView.qml's current module/method-picker UI
        // still uses that role until the Shell rewrite replaces it
        // wholesale (see TODO.md).
        CommandSchemasRole,
        // IModule capabilities' "version" field, or an empty string if the
        // module hasn't reported IModule capabilities (shouldn't happen for
        // a real pyobs module, but disco#info parsing failures degrade to
        // this rather than a crash) - the Status page's "Version" column.
        VersionRole,
        // QVariantList of {"group":..., "modes":[...]} entries decoded from
        // IMode capabilities ("modes" field: group name -> static list of
        // mode options), empty list if the module hasn't reported IMode
        // capabilities - ModeView.qml's per-group ComboBox population. Not
        // a generic capabilities-dump role, same narrow-scope discipline as
        // VersionRole above.
        ModeGroupsRole,
        // QVariantList of "{x}x{y}" strings decoded from IBinning
        // capabilities' "binnings" field (list of {x,y} structs), empty
        // list if the module hasn't reported IBinning capabilities -
        // CameraView.qml's IBinning ComboBox population. Same narrow-scope
        // discipline as ModeGroupsRole above, not a generic capabilities
        // dump.
        BinningOptionsRole,
        // QVariantMap {"fullFrameX":..., "fullFrameY":..., "fullFrameWidth":
        // ..., "fullFrameHeight":...} decoded from IWindow capabilities
        // (four flat int fields, no nesting), empty map if the module
        // hasn't reported IWindow capabilities - CameraView.qml's IWindow
        // SpinBox bounds.
        WindowExtentRole,
        // QVariantList of plain strings decoded from IImageFormat
        // capabilities' "image_formats" field, empty list if the module
        // hasn't reported IImageFormat capabilities - CameraView.qml's
        // IImageFormat ComboBox population.
        ImageFormatsRole,
        // "ready" / "error" / "local", derived from presence show/status -
        // see ModuleInfo::presenceState. The Status page's health badge.
        PresenceStateRole,
        // presence statusText() for the error case above - empty otherwise.
        PresenceErrorRole,
    };
    Q_ENUM(Role)

    explicit ModuleListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // True if any connected module's disco#info-reported interfaces
    // include this one (exact name, e.g. "IRoof") - lets a QML page gate
    // its own sidebar visibility on "is there actually a module for me to
    // show" without needing to iterate the model's rows itself (Qt gives
    // QML no generic random-access iteration over a QAbstractListModel -
    // see EventLogModel::entriesOfType() for the same kind of escape
    // hatch). Recompute this in QML on rowsInserted/rowsRemoved/
    // modelReset/dataChanged, not just once - it's a plain query, not a
    // live-updating binding on its own.
    Q_INVOKABLE bool hasInterface(const QString &interfaceName) const;

    // True if a module with exactly this bare JID is currently connected.
    // Same "QML gets no generic random-access iteration" escape-hatch
    // reasoning as hasInterface() above, for the module-specific (rather
    // than interface-specific) half of WidgetRegistry.qml's registration
    // lookup (TODO.md's "Plugin mechanism" item, step 1).
    Q_INVOKABLE bool hasModule(const QString &bareJid) const;

    // Flat, cross-module list of {"module":..., "name":..., "params":
    // [...]} entries - one per distinct command name per module, deduped
    // the same "first interface declaring a command wins" way
    // XmppClient::executeMethod()'s real-param overload resolves dispatch
    // (both iterate ModuleInfo::interfaces - a QMap sorted by interface
    // name - in that same order), so a popup entry's displayed params
    // always match what would actually execute. "module" is the JID's
    // local part - matches what the user types before "." in a shell
    // command, not any display name (see jidForModuleName()'s own doc
    // comment for why). Q_INVOKABLE escape hatch for the Shell's
    // autocomplete popup (TODO.md, step 4) - same "QML gets no generic
    // random-access iteration over a QAbstractListModel" reasoning as
    // hasInterface() above. Recompute this in QML on rowsInserted/
    // rowsRemoved/modelReset/dataChanged, not just once.
    Q_INVOKABLE QVariantList allCommands() const;

    // C++-internal lookup (not Q_INVOKABLE - QML never needs a whole
    // ModuleInfo, only the per-role data() already exposes): used by
    // XmppClient::executeMethod()'s real-parameter overload to find a
    // command's CommandSchema before encoding real values for it. Returns
    // nullptr if this bare JID isn't in the list. The returned pointer is
    // only valid until the next upsert()/remove()/clear() call - callers
    // must use it synchronously, not stash it.
    const ModuleInfo *find(const QString &bareJid) const;

    // C++-internal lookup (not Q_INVOKABLE, same reasoning as find() above):
    // used by XmppClient::executeShellCommand() to resolve the plain module
    // name a shell command is typed against (e.g. "mode" in
    // "mode.set_mode(...)") to that module's bare JID. Matches against the
    // JID's own local part, not ModuleInfo::name (the disco#info identity/
    // display name) - confirmed against pyobs-core's XmppComm source
    // (xmppcomm.py's _get_full_client_name()): it builds the target JID by
    // gluing the typed name directly onto the domain with no lookup or
    // escaping of any kind, so "name" (an independent, display-only field -
    // see module.py's own "name always tracks the comm's own identity...
    // not any locally configured string" comment) is never consulted for
    // routing. Returns an empty string if no connected module's JID has
    // this local part.
    QString jidForModuleName(const QString &moduleName) const;

    // Adds a new module, or replaces the existing entry for the same bare
    // JID (a module re-announcing itself, or a fetchModuleInfo() reply
    // arriving for one already known from a live presence push).
    void upsert(const ModuleInfo &info);

    // Removes the module with this bare JID, if present (presence
    // type="unavailable"). No-op if it isn't in the list.
    void remove(const QString &bareJid);

    // Updates just the presence-derived fields of an already-known module in
    // place (no disco#info re-fetch) - returns false if this JID isn't in
    // the list yet, so the caller knows to fall back to a full fetch instead.
    bool updatePresence(const QString &bareJid, const QString &state, const QString &errorText);

    // Empties the whole list - matches useXmpp.ts's disconnect() resetting
    // its modules ref, called from XmppClient::disconnectFromServer().
    void clear();

private:
    QVector<ModuleInfo> m_modules;
};

}
