#pragma once

#include "../codec/InterfaceSchema.h"
#include "../codec/WireValue.h"

#include <QMap>
#include <QString>

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
};

}
