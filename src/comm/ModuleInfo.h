#pragma once

#include "../codec/InterfaceSchema.h"
#include "../codec/WireValue.h"

#include <QMap>
#include <QString>
#include <QStringList>
#include <optional>

namespace comm {

// Same shape as pyobs-web-client's PyobsModule type. Plain struct, not a
// QObject: QML doesn't need to bind to this directly until Phase 4.
struct ModuleInfo {
    QString jid; // bare JID, e.g. camera@localhost
    QString fullJid; // full JID with resource, e.g. camera@localhost/pyobs
    QString name;
    QMap<QString, codec::InterfaceSchema> interfaces;
    QMap<QString, codec::EventSchema> events;
    QMap<QString, codec::WireValue> capabilities; // interface name -> decoded capabilities

    // ACL gating (TODO.md's "ACL / permitted-methods gating"): nullopt means
    // not yet fetched, or the get_permitted_methods() RPC failed - fail
    // open (everything permitted), matching pyobs-gui's own BaseWidget.
    // permitted() fallback. Populated by XmppClient after disco#info
    // resolves, via a second, RPC-level round trip (a different wire
    // protocol than disco#info, so not folded into fetchModuleInfo()
    // itself) - see XmppClient::fetchPermittedMethods(). Left untouched by
    // ModuleListModel::updatePresence(), same as every other disco#info-
    // derived field here.
    std::optional<QStringList> permittedMethods;

    // Module lifecycle state from presence (show/status), not disco#info -
    // mirrors pyobs-core's ModuleState ("ready"/"error"/"local"; "closed"
    // has no representation here since an unavailable module is removed
    // from the list entirely rather than kept around in a closed state).
    // Defaults to "ready" since a module is only ever added to the list on
    // available presence in the first place.
    QString presenceState = QStringLiteral("ready");
    QString presenceError;
};

}
