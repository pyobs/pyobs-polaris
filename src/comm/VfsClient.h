#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <qqmlintegration.h>

namespace comm {

// Fetches a file's bytes over plain HTTP GET, matching pyobs-core's
// HttpFile VFS backend exactly (see pyobs/vfs/httpfile.py): a base URL
// joined with the VFS-relative filename (config::VfsEndpointsModel does
// that join, this class only ever sees the final URL), optional HTTP
// Basic Auth. Deliberately separate from VfsEndpointsModel the same way
// StateSubscriptionManager/Rpc are separate from XmppClient - this class
// has zero XMPP/config dependency, just QNetworkAccessManager.
//
// Sends Authorization: Basic preemptively (not in response to a 401
// challenge) when a username is given - simpler than a two-round-trip
// challenge/response, and correct here since HttpFile's own server side
// (aiohttp) never sends a WWW-Authenticate challenge in the first place,
// it just 401s outright (see httpfile.py's `_download()`).
//
// No caching, no retry - every fetchFile() call is a live GET, matching
// this project's "the wire protocol is the source of truth" ethos
// elsewhere (see CLAUDE.md). Each call gets its own opaque requestId
// (caller-supplied) purely so a caller juggling multiple in-flight
// fetches can tell its own fileReady/fileFailed signals apart - this
// class holds no per-request state of its own beyond the QNetworkReply.
class VfsClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit VfsClient(QObject *parent = nullptr);

    // Starts an async GET of `url`. `username` empty means no
    // Authorization header at all - `password` is ignored in that case.
    // fileReady(requestId, data) or fileFailed(requestId, errorMessage)
    // fires once the request completes.
    Q_INVOKABLE void fetchFile(const QString &requestId, const QString &url, const QString &username = QString(),
                                const QString &password = QString());

Q_SIGNALS:
    void fileReady(const QString &requestId, const QByteArray &data);
    void fileFailed(const QString &requestId, const QString &errorMessage);

private:
    QNetworkAccessManager m_networkAccessManager;
};

} // namespace comm
