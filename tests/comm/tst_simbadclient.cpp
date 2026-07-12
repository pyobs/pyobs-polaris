#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTest>

#include "SimbadClient.h"

using namespace comm;

// parseSimbadCsv()'s test cases use real response bodies captured live
// against the actual SIMBAD TAP service (simbad.cds.unistra.fr) while
// developing this - not guessed from documentation - see each test's own
// comment for the exact query that produced it. queryByName()'s own
// HTTP-round-trip tests use a hand-rolled local stub server instead
// (same technique tst_vfsclient.cpp already uses for VfsClient), so this
// suite never needs real network access to run in CI.
class TestSimbadClient : public QObject
{
    Q_OBJECT

private slots:
    void parseCsvExtractsRaDecAndQuotedMainId();
    void parseCsvHandlesUnquotedMainId();
    void parseCsvReturnsNulloptForHeaderOnlyResponse();
    void parseCsvReturnsNulloptForVOTableErrorDocument();
    void parseCsvReturnsNulloptForMalformedNumericField();

    void queryByNameParsesSuccessfulResponse();
    void queryByNameEscapesSingleQuoteInName();
    void queryByNameSendsCsvFormatAndAdqlQuery();
    void queryByNameFailsWhenNoObjectFound();
    void queryByNameFailsOnHttpError();
    void queryByNameFailsWhenServerUnreachable();

private:
    static QPair<QTcpServer *, quint16> startStubServer(QObject *parent, const QByteArray &response)
    {
        auto *server = new QTcpServer(parent);
        if (!server->listen(QHostAddress::LocalHost)) {
            qFatal("failed to bind loopback test server");
        }
        QObject::connect(server, &QTcpServer::newConnection, server, [server, response] {
            QTcpSocket *socket = server->nextPendingConnection();
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

    static QByteArray csvResponse(const QByteArray &body)
    {
        return "HTTP/1.1 200 OK\r\nContent-Type: text/csv;charset=UTF-8\r\nContent-Length: "
            + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
    }
};

// Captured live via:
//   QUERY=SELECT basic.ra, basic.dec, basic.main_id FROM basic
//     JOIN ident ON basic.oid = ident.oidref WHERE ident.id = 'M31'
void TestSimbadClient::parseCsvExtractsRaDecAndQuotedMainId()
{
    const QByteArray csv = "ra,dec,main_id\n10.684708333333333,41.268750000000004,\"M  31\"\n";
    const std::optional<SimbadResult> result = parseSimbadCsv(csv);

    QVERIFY(result.has_value());
    QCOMPARE(result->ra, 10.684708333333333);
    QCOMPARE(result->dec, 41.268750000000004);
    QCOMPARE(result->mainId, QStringLiteral("M  31"));
}

void TestSimbadClient::parseCsvHandlesUnquotedMainId()
{
    const QByteArray csv = "ra,dec,main_id\n101.28715533333335,-16.71611586111111,Sirius\n";
    const std::optional<SimbadResult> result = parseSimbadCsv(csv);

    QVERIFY(result.has_value());
    QCOMPARE(result->mainId, QStringLiteral("Sirius"));
}

// Captured live querying a nonexistent identifier - the service returns
// just the header row, no data.
void TestSimbadClient::parseCsvReturnsNulloptForHeaderOnlyResponse()
{
    QVERIFY(!parseSimbadCsv(QByteArrayLiteral("ra,dec,main_id\n")).has_value());
    QVERIFY(!parseSimbadCsv(QByteArrayLiteral("ra,dec,main_id")).has_value());
}

// Captured live from an intentionally-malformed ADQL query (using
// UPPER(), which this service's ADQL dialect rejects) - even with
// FORMAT=csv requested, an error comes back as a VOTable/XML document,
// not CSV. This project's own query is fixed and already verified not to
// hit this, but parseSimbadCsv() must not crash or misparse it either.
void TestSimbadClient::parseCsvReturnsNulloptForVOTableErrorDocument()
{
    const QByteArray xml =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<VOTABLE version=\"1.3\"><RESOURCE type=\"results\">"
        "<INFO name=\"QUERY_STATUS\" value=\"ERROR\">Incorrect ADQL query</INFO>"
        "</RESOURCE></VOTABLE>\n";
    QVERIFY(!parseSimbadCsv(xml).has_value());
}

void TestSimbadClient::parseCsvReturnsNulloptForMalformedNumericField()
{
    const QByteArray csv = "ra,dec,main_id\nnot-a-number,41.27,\"M  31\"\n";
    QVERIFY(!parseSimbadCsv(csv).has_value());
}

void TestSimbadClient::queryByNameParsesSuccessfulResponse()
{
    const auto [server, port] = startStubServer(
        this, csvResponse("ra,dec,main_id\n10.684708333333333,41.268750000000004,\"M  31\"\n"));

    SimbadClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/sync").arg(port));
    QSignalSpy readySpy(&client, &SimbadClient::queryReady);
    QSignalSpy failedSpy(&client, &SimbadClient::queryFailed);

    client.queryByName(QStringLiteral("req-1"), QStringLiteral("M31"));

    QVERIFY(readySpy.wait());
    QCOMPARE(failedSpy.count(), 0);
    QCOMPARE(readySpy.first().at(0).toString(), QStringLiteral("req-1"));
    QCOMPARE(readySpy.first().at(1).toDouble(), 10.684708333333333);
    QCOMPARE(readySpy.first().at(2).toDouble(), 41.268750000000004);
    QCOMPARE(readySpy.first().at(3).toString(), QStringLiteral("M  31"));

    server->deleteLater();
}

void TestSimbadClient::queryByNameEscapesSingleQuoteInName()
{
    auto *server = new QTcpServer(this);
    QVERIFY2(server->listen(QHostAddress::LocalHost), "failed to bind loopback test server");

    QByteArray capturedRequest;
    connect(server, &QTcpServer::newConnection, server, [server, &capturedRequest] {
        QTcpSocket *socket = server->nextPendingConnection();
        connect(socket, &QTcpSocket::readyRead, socket, [socket, &capturedRequest] {
            capturedRequest += socket->readAll();
            if (capturedRequest.contains("\r\n\r\n")) {
                const QByteArray body = "ra,dec,main_id\n";
                socket->write("HTTP/1.1 200 OK\r\nContent-Length: " + QByteArray::number(body.size())
                               + "\r\nConnection: close\r\n\r\n" + body);
                socket->flush();
                socket->disconnectFromHost();
            }
        });
    });

    SimbadClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/sync").arg(server->serverPort()));
    QSignalSpy failedSpy(&client, &SimbadClient::queryFailed);
    client.queryByName(QStringLiteral("req-2"), QStringLiteral("O'Brien"));

    QVERIFY(failedSpy.wait());
    // The request line's query string is percent-encoded, so decode it
    // back before checking - the doubled quote (`O''Brien`) must appear;
    // a lone `O'Brien` is not a substring of `O''Brien` (there's a
    // second `'` in between), so this also confirms the escaping
    // actually happened rather than the raw name passing through as-is.
    const QString decoded = QUrl::fromPercentEncoding(capturedRequest);
    QVERIFY(decoded.contains(QStringLiteral("O''Brien")));

    server->deleteLater();
}

void TestSimbadClient::queryByNameSendsCsvFormatAndAdqlQuery()
{
    auto *server = new QTcpServer(this);
    QVERIFY2(server->listen(QHostAddress::LocalHost), "failed to bind loopback test server");

    QByteArray capturedRequest;
    connect(server, &QTcpServer::newConnection, server, [server, &capturedRequest] {
        QTcpSocket *socket = server->nextPendingConnection();
        connect(socket, &QTcpSocket::readyRead, socket, [socket, &capturedRequest] {
            capturedRequest += socket->readAll();
            if (capturedRequest.contains("\r\n\r\n")) {
                const QByteArray body = "ra,dec,main_id\n";
                socket->write("HTTP/1.1 200 OK\r\nContent-Length: " + QByteArray::number(body.size())
                               + "\r\nConnection: close\r\n\r\n" + body);
                socket->flush();
                socket->disconnectFromHost();
            }
        });
    });

    SimbadClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/sync").arg(server->serverPort()));
    QSignalSpy failedSpy(&client, &SimbadClient::queryFailed);
    client.queryByName(QStringLiteral("req-3"), QStringLiteral("M31"));

    QVERIFY(failedSpy.wait());
    const QString decoded = QUrl::fromPercentEncoding(capturedRequest);
    QVERIFY(decoded.contains(QStringLiteral("FORMAT=csv")));
    QVERIFY(decoded.contains(QStringLiteral("LANG=ADQL")));
    QVERIFY(decoded.contains(QStringLiteral("ident.id = 'M31'")));

    server->deleteLater();
}

void TestSimbadClient::queryByNameFailsWhenNoObjectFound()
{
    const auto [server, port] = startStubServer(this, csvResponse("ra,dec,main_id\n"));

    SimbadClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/sync").arg(port));
    QSignalSpy readySpy(&client, &SimbadClient::queryReady);
    QSignalSpy failedSpy(&client, &SimbadClient::queryFailed);

    client.queryByName(QStringLiteral("req-4"), QStringLiteral("ThisObjectDoesNotExist12345"));

    QVERIFY(failedSpy.wait());
    QCOMPARE(readySpy.count(), 0);
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-4"));
    QVERIFY(!failedSpy.first().at(1).toString().isEmpty());

    server->deleteLater();
}

void TestSimbadClient::queryByNameFailsOnHttpError()
{
    const auto [server, port] = startStubServer(
        this, "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");

    SimbadClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/sync").arg(port));
    QSignalSpy failedSpy(&client, &SimbadClient::queryFailed);

    client.queryByName(QStringLiteral("req-5"), QStringLiteral("M31"));

    QVERIFY(failedSpy.wait());
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-5"));

    server->deleteLater();
}

void TestSimbadClient::queryByNameFailsWhenServerUnreachable()
{
    SimbadClient client(nullptr, QStringLiteral("http://127.0.0.1:1/sync"));
    QSignalSpy failedSpy(&client, &SimbadClient::queryFailed);

    client.queryByName(QStringLiteral("req-6"), QStringLiteral("M31"));

    QVERIFY(failedSpy.wait());
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-6"));
}

QTEST_MAIN(TestSimbadClient)
#include "tst_simbadclient.moc"
