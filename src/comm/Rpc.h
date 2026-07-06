#pragma once

#include "../codec/InterfaceSchema.h"
#include "../codec/WireValue.h"

#include <QString>
#include <QVector>
#include <functional>

class QXmppClient;

namespace comm {

// Mirrors useXmpp.ts's RpcResult: success/value on the happy path; on
// failure, errorClass is only set for a real remote fault (an actual
// exception raised in the module's command), left empty for a plain
// XMPP-level transport error (item-not-found, forbidden, timeout, ...) -
// callers can tell "some XMPP error" apart from a genuine remote exception
// this way, same distinction the acceptance criterion cares about.
struct RpcResult {
    bool success = false;
    codec::WireValue value; // decoded return value; null WireValue for a void return
    QString errorClass;
    QString errorMessage;
};

// Ports useXmpp.ts's executeMethod: builds the XEP-0009 RPC IQ
// (jabber:iq:rpc envelope, urn:pyobs:rpc:1 value payload - same
// double-wrapping as the TS side, not flattened), sends it to fullJid, and
// reports the decoded return value or fault/error back through `callback`.
void executeMethod(QXmppClient &client, const QString &fullJid, const QString &methodName,
                   const QVector<codec::WireValue> &params, const QVector<codec::FieldSchema> &paramSchemas,
                   std::function<void(RpcResult)> callback);

}
