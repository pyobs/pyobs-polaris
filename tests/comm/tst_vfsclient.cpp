#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTest>

#include "VfsClient.h"

using namespace comm;

// Exercises VfsClient against a real (if minimal, hand-rolled) local HTTP
// server rather than mocking QNetworkAccessManager - matches this
// project's "verify against the real wire" testing philosophy elsewhere
// (see tst_statesubscription/tst_eventmanager). Doesn't need a whole
// pyobs.modules.utils.HttpFileCache module up for a unit test - just
// enough raw HTTP to prove VfsClient sends/parses what pyobs-core's own
// HttpFile backend (aiohttp) expects. See DEVELOPMENT.md's VFS transport
// write-up for the live-fixture verification (real HttpFileCache/
// DummyCamera) this doesn't replace.
class TestVfsClient : public QObject
{
    Q_OBJECT

private slots:
    void fetchFileReturnsBodyOnSuccess();
    void fetchFileSendsPreemptiveBasicAuthHeader();
    void fetchFileFailsOn404();
    void fetchFileFailsWhenServerUnreachable();

private:
    // Starts a QTcpServer on an ephemeral loopback port, accepts exactly
    // one connection, and replies with a fixed HTTP response once any
    // bytes of the request have arrived - just enough of the protocol
    // for QNetworkAccessManager's GET to round-trip. Returns the server
    // (caller keeps it alive for the request's duration, then deletes
    // it) and the port to fetch from.
    static QPair<QTcpServer *, quint16> startStubServer(QObject *parent, const QByteArray &response)
    {
        auto *server = new QTcpServer(parent);
        if (!server->listen(QHostAddress::LocalHost)) {
            qFatal("failed to bind loopback test server");
        }
        QObject::connect(server, &QTcpServer::newConnection, server, [server, response] {
            QTcpSocket *socket = server->nextPendingConnection();
            // A GET request has no body, so the request line + headers
            // always arrive in the client's first flushed write - reply
            // as soon as anything is readable, no need to wait for the
            // blank line the way fetchFileSendsPreemptiveBasicAuthHeader
            // below does (there because it needs to inspect the headers,
            // not just react to their arrival).
            auto connection = std::make_shared<QMetaObject::Connection>();
            *connection = QObject::connect(socket, &QTcpSocket::readyRead, socket, [socket, response, connection] {
                QObject::disconnect(*connection);
                socket->readAll();
                socket->write(response);
                socket->flush();
                socket->disconnectFromHost();
            });
        });
        return {server, server->serverPort()};
    }
};

void TestVfsClient::fetchFileReturnsBodyOnSuccess()
{
    const auto [server, port] = startStubServer(
        this, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello");

    VfsClient client;
    QSignalSpy readySpy(&client, &VfsClient::fileReady);
    QSignalSpy failedSpy(&client, &VfsClient::fileFailed);

    client.fetchFile(QStringLiteral("req-1"), QStringLiteral("http://127.0.0.1:%1/image.fits").arg(port));

    QVERIFY(readySpy.wait());
    QCOMPARE(failedSpy.count(), 0);
    QCOMPARE(readySpy.first().at(0).toString(), QStringLiteral("req-1"));
    QCOMPARE(readySpy.first().at(1).toByteArray(), QByteArrayLiteral("hello"));

    server->deleteLater();
}

void TestVfsClient::fetchFileSendsPreemptiveBasicAuthHeader()
{
    auto *server = new QTcpServer(this);
    QVERIFY2(server->listen(QHostAddress::LocalHost), "failed to bind loopback test server");

    QByteArray capturedRequest;
    connect(server, &QTcpServer::newConnection, server, [server, &capturedRequest] {
        QTcpSocket *socket = server->nextPendingConnection();
        connect(socket, &QTcpSocket::readyRead, socket, [socket, &capturedRequest] {
            capturedRequest += socket->readAll();
            if (capturedRequest.contains("\r\n\r\n")) {
                socket->write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");
                socket->flush();
                socket->disconnectFromHost();
            }
        });
    });

    VfsClient client;
    QSignalSpy readySpy(&client, &VfsClient::fileReady);
    client.fetchFile(QStringLiteral("req-2"), QStringLiteral("http://127.0.0.1:%1/x").arg(server->serverPort()),
                      QStringLiteral("alice"), QStringLiteral("hunter2"));

    QVERIFY(readySpy.wait());
    // "alice:hunter2" base64-encoded, matching aiohttp.BasicAuth's own
    // header shape server-side (see pyobs-core's httpfile.py).
    QVERIFY(capturedRequest.contains("Authorization: Basic YWxpY2U6aHVudGVyMg=="));

    server->deleteLater();
}

void TestVfsClient::fetchFileFailsOn404()
{
    const auto [server, port] = startStubServer(
        this, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");

    VfsClient client;
    QSignalSpy failedSpy(&client, &VfsClient::fileFailed);
    QSignalSpy readySpy(&client, &VfsClient::fileReady);

    client.fetchFile(QStringLiteral("req-3"), QStringLiteral("http://127.0.0.1:%1/missing.fits").arg(port));

    QVERIFY(failedSpy.wait());
    QCOMPARE(readySpy.count(), 0);
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-3"));
    QVERIFY(!failedSpy.first().at(1).toString().isEmpty());

    server->deleteLater();
}

void TestVfsClient::fetchFileFailsWhenServerUnreachable()
{
    VfsClient client;
    QSignalSpy failedSpy(&client, &VfsClient::fileFailed);

    // Port 1 is a reserved/unassigned TCP port - connection refused on
    // loopback, no server needs to be running at all.
    client.fetchFile(QStringLiteral("req-4"), QStringLiteral("http://127.0.0.1:1/x"));

    QVERIFY(failedSpy.wait());
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-4"));
}

QTEST_MAIN(TestVfsClient)
#include "tst_vfsclient.moc"
