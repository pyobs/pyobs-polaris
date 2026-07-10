#include "VfsClient.h"

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace comm {

VfsClient::VfsClient(QObject *parent)
    : QObject(parent)
{
}

void VfsClient::fetchFile(const QString &requestId, const QString &url, const QString &username,
                           const QString &password)
{
    QNetworkRequest request{QUrl(url)};
    if (!username.isEmpty()) {
        const QByteArray credentials = (username + QLatin1Char(':') + password).toUtf8();
        request.setRawHeader("Authorization", "Basic " + credentials.toBase64());
    }

    QNetworkReply *reply = m_networkAccessManager.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestId] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT fileFailed(requestId, reply->errorString());
            return;
        }
        Q_EMIT fileReady(requestId, reply->readAll());
    });
}

} // namespace comm
