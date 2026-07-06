#pragma once

#include "InterfaceSchema.h"

#include <QString>
#include <optional>

class QDomElement;

namespace codec {

enum class FeatureKind { Interface, State, Event, Capabilities };

struct VersionedFeature {
    QString name;
    int version = 1;
};

// Ports pyobs-codec.ts's parseVersionedFeature: parses a
// `urn:pyobs:{kind}:{name}:{version}` namespace string. Returns nullopt if
// `feat` doesn't match that shape (wrong kind prefix, or a non-numeric/
// missing version suffix).
std::optional<VersionedFeature> parseVersionedFeature(FeatureKind kind, const QString &feat);

// Ports pyobs-codec.ts's parseInterfaceSchema: parses a disco#info
// `<{urn:pyobs:interface:Name:version}interface>` element (optional
// `<types>`, then `<command>` elements, then an optional `<state>`).
InterfaceSchema parseInterfaceSchema(const QDomElement &element);

// Ports pyobs-codec.ts's parseEventSchema: parses a disco#info
// `<{urn:pyobs:event:Name:version}event>` element (optional `<types>`, then
// `<field>` elements directly - no `<state>` wrapper, unlike interfaces).
EventSchema parseEventSchema(const QDomElement &element);

}
