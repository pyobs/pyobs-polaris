#pragma once

#include "WireType.h"

#include <QMap>
#include <QString>
#include <QVector>
#include <optional>

namespace codec {

// Same shapes as pyobs-codec.ts's FieldSchema/CommandSchema/StateSchema/
// InterfaceSchema/EventSchema. `enums`/`commands` map keys are looked up by
// name, never iterated for display order, so a plain (sorted) QMap is fine
// here - unlike codec::WireDict (see WireValue.h), where wire order is
// exactly what's being preserved.

struct FieldSchema {
    QString name;
    WireType type;
    QString unit; // empty means "no unit", mirroring the TS `unit?`
};

struct CommandSchema {
    QString name;
    QVector<FieldSchema> params;
};

// `node` is a display label only (e.g. "state/ICooling/1"), NOT the real
// PubSub node - that's built from the module's JID username (see
// useXmpp.ts / Phase 4).
struct StateSchema {
    QString node;
    QVector<FieldSchema> fields;
};

struct InterfaceSchema {
    QString name;
    int version = 1;
    QMap<QString, QVector<QString>> enums; // enum name -> ordered values
    QMap<QString, CommandSchema> commands; // command name -> schema
    std::optional<StateSchema> state;
};

struct EventSchema {
    QString name;
    int version = 1;
    QMap<QString, QVector<QString>> enums;
    QVector<FieldSchema> fields;
};

}
