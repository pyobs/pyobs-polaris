#pragma once

#include "ModuleInfo.h"

#include <QString>
#include <functional>

class QXmppClient;

namespace comm {

// Ports pyobs-web-client's fetchModuleInfo: sends one disco#info IQ to
// fullJid and parses <interface>/<event>/<capabilities> children by
// namespace exactly as useXmpp.ts does, invoking `callback` with the
// populated ModuleInfo once the (async) round trip completes. On an XMPP
// error or a malformed reply, `callback` still runs, with a ModuleInfo
// derived only from the JID (empty interfaces/events/capabilities) -
// mirrors useXmpp.ts's fetchModuleInfo catch{} fallback.
void fetchModuleInfo(QXmppClient &client, const QString &bareJid, const QString &fullJid,
                      std::function<void(ModuleInfo)> callback);

// Prints a ModuleInfo's interfaces/commands/state/events/capabilities to
// qInfo() - Phase 2's acceptance criterion is a manual diff against the raw
// disco#info XML, not a UI yet.
void logModuleInfo(const ModuleInfo &info);

}
