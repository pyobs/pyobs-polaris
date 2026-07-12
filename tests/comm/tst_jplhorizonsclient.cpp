#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTest>

#include "JplHorizonsClient.h"

using namespace comm;

// parseJplHorizonsResponse()'s test cases use real response bodies
// captured live against the actual JPL Horizons API
// (ssd.jpl.nasa.gov/api/horizons.api) while developing this - not
// guessed from documentation - see each test's own comment for the
// exact query that produced it. queryByName()'s own HTTP-round-trip
// tests use a hand-rolled local stub server instead (same technique
// tst_vfsclient.cpp/tst_simbadclient.cpp already use), so this suite
// never needs real network access to run in CI.
class TestJplHorizonsClient : public QObject
{
    Q_OBJECT

private slots:
    void parseResponseExtractsRaDecAndTargetName();
    void parseResponseFallsBackToSearchedNameWhenTargetLineMissing();
    void parseResponseReturnsNulloptWhenNoMatchFound();
    void parseResponseReturnsNulloptWhenAmbiguous();
    void parseResponseReturnsNulloptForMalformedNumericField();

    void queryByNameParsesSuccessfulResponse();
    void queryByNameSendsExpectedQueryParameters();
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

    static QByteArray httpResponse(const QByteArray &body)
    {
        return "HTTP/1.1 200 OK\r\nContent-Length: " + QByteArray::number(body.size())
            + "\r\nConnection: close\r\n\r\n" + body;
    }
};

// Captured live via COMMAND='Ceres', QUANTITIES='1', CSV_FORMAT=YES,
// ANG_FORMAT=DEG, CENTER='500@399', EPHEM_TYPE=OBSERVER (trimmed to the
// parts parseJplHorizonsResponse() actually looks at).
void TestJplHorizonsClient::parseResponseExtractsRaDecAndTargetName()
{
    const QByteArray response =
        "Target body name: Ceres (2000001)                 {source: dawn_final}\n"
        "Center body name: Earth (399)                     {source: dawn_final}\n"
        "$$SOE\n"
        " 2024-Jul-09 00:00:00.000, , ,   285.36259,  -29.51593,\n"
        "$$EOE\n";

    const std::optional<JplHorizonsResult> result =
        parseJplHorizonsResponse(response, QStringLiteral("Ceres"));

    QVERIFY(result.has_value());
    QCOMPARE(result->ra, 285.36259);
    QCOMPARE(result->dec, -29.51593);
    QCOMPARE(result->targetName, QStringLiteral("Ceres (2000001)"));
}

void TestJplHorizonsClient::parseResponseFallsBackToSearchedNameWhenTargetLineMissing()
{
    const QByteArray response = "$$SOE\n 2024-Jul-09 00:00:00.000, , ,    49.15340,   17.25512,\n$$EOE\n";

    const std::optional<JplHorizonsResult> result = parseJplHorizonsResponse(response, QStringLiteral("499"));

    QVERIFY(result.has_value());
    QCOMPARE(result->targetName, QStringLiteral("499"));
}

// Captured live querying "NotARealAsteroidXYZ123" - no $$SOE block at
// all, just a "No matches found" diagnostic.
void TestJplHorizonsClient::parseResponseReturnsNulloptWhenNoMatchFound()
{
    const QByteArray response =
        "JPL/DASTCOM            Small-body Index Search Results\n"
        " Comet AND asteroid index search:\n"
        "   NAME = NotARealAsteroidXYZ123;\n"
        " Matching small-bodies: \n"
        "    No matches found.\n";

    QVERIFY(!parseJplHorizonsResponse(response, QStringLiteral("NotARealAsteroidXYZ123")).has_value());
}

// Captured live querying "Europa" - matches both the Jovian moon and a
// spacecraft, so Horizons asks the caller to disambiguate by ID# instead
// of returning an ephemeris - also no $$SOE block, same as the
// not-found case above (see parseJplHorizonsResponse()'s own header
// comment for why both fall into the same nullopt path).
void TestJplHorizonsClient::parseResponseReturnsNulloptWhenAmbiguous()
{
    const QByteArray response =
        " Multiple major-bodies match string \"EUROPA*\"\n"
        "  ID#      Name                               Designation  IAU/aliases/other\n"
        "      502  Europa                                          JII\n"
        "     -159  Europa Clipper (spacecraft)        2024-182A\n"
        "   Number of matches =  2. Use ID# to make unique selection.\n";

    QVERIFY(!parseJplHorizonsResponse(response, QStringLiteral("Europa")).has_value());
}

void TestJplHorizonsClient::parseResponseReturnsNulloptForMalformedNumericField()
{
    const QByteArray response = "$$SOE\n 2024-Jul-09 00:00:00.000, , , not-a-number,   17.25512,\n$$EOE\n";
    QVERIFY(!parseJplHorizonsResponse(response, QStringLiteral("499")).has_value());
}

void TestJplHorizonsClient::queryByNameParsesSuccessfulResponse()
{
    const auto [server, port] = startStubServer(
        this, httpResponse("Target body name: Ceres (2000001)                 {source: dawn_final}\n"
                            "$$SOE\n 2024-Jul-09 00:00:00.000, , ,   285.36259,  -29.51593,\n$$EOE\n"));

    JplHorizonsClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/api").arg(port));
    QSignalSpy readySpy(&client, &JplHorizonsClient::queryReady);
    QSignalSpy failedSpy(&client, &JplHorizonsClient::queryFailed);

    client.queryByName(QStringLiteral("req-1"), QStringLiteral("Ceres"));

    QVERIFY(readySpy.wait());
    QCOMPARE(failedSpy.count(), 0);
    QCOMPARE(readySpy.first().at(0).toString(), QStringLiteral("req-1"));
    QCOMPARE(readySpy.first().at(1).toDouble(), 285.36259);
    QCOMPARE(readySpy.first().at(2).toDouble(), -29.51593);
    QCOMPARE(readySpy.first().at(3).toString(), QStringLiteral("Ceres (2000001)"));

    server->deleteLater();
}

void TestJplHorizonsClient::queryByNameSendsExpectedQueryParameters()
{
    auto *server = new QTcpServer(this);
    QVERIFY2(server->listen(QHostAddress::LocalHost), "failed to bind loopback test server");

    QByteArray capturedRequest;
    connect(server, &QTcpServer::newConnection, server, [server, &capturedRequest] {
        QTcpSocket *socket = server->nextPendingConnection();
        connect(socket, &QTcpSocket::readyRead, socket, [socket, &capturedRequest] {
            capturedRequest += socket->readAll();
            if (capturedRequest.contains("\r\n\r\n")) {
                const QByteArray body = "$$SOE\n 2024-Jul-09 00:00:00.000, , ,   285.36259,  -29.51593,\n$$EOE\n";
                socket->write("HTTP/1.1 200 OK\r\nContent-Length: " + QByteArray::number(body.size())
                               + "\r\nConnection: close\r\n\r\n" + body);
                socket->flush();
                socket->disconnectFromHost();
            }
        });
    });

    JplHorizonsClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/api").arg(server->serverPort()));
    QSignalSpy readySpy(&client, &JplHorizonsClient::queryReady);
    client.queryByName(QStringLiteral("req-2"), QStringLiteral("Ceres"));

    QVERIFY(readySpy.wait());
    const QString decoded = QUrl::fromPercentEncoding(capturedRequest);
    QVERIFY(decoded.contains(QStringLiteral("format=text")));
    QVERIFY(decoded.contains(QStringLiteral("COMMAND='Ceres'")));
    QVERIFY(decoded.contains(QStringLiteral("EPHEM_TYPE=OBSERVER")));
    QVERIFY(decoded.contains(QStringLiteral("CENTER='500@399'")));
    QVERIFY(decoded.contains(QStringLiteral("QUANTITIES='1'")));
    QVERIFY(decoded.contains(QStringLiteral("ANG_FORMAT=DEG")));

    server->deleteLater();
}

void TestJplHorizonsClient::queryByNameFailsWhenNoObjectFound()
{
    const auto [server, port] = startStubServer(this, httpResponse("No matches found.\n"));

    JplHorizonsClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/api").arg(port));
    QSignalSpy readySpy(&client, &JplHorizonsClient::queryReady);
    QSignalSpy failedSpy(&client, &JplHorizonsClient::queryFailed);

    client.queryByName(QStringLiteral("req-3"), QStringLiteral("NotARealAsteroidXYZ123"));

    QVERIFY(failedSpy.wait());
    QCOMPARE(readySpy.count(), 0);
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-3"));
    QVERIFY(!failedSpy.first().at(1).toString().isEmpty());

    server->deleteLater();
}

void TestJplHorizonsClient::queryByNameFailsOnHttpError()
{
    const auto [server, port] = startStubServer(
        this, "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");

    JplHorizonsClient client(nullptr, QStringLiteral("http://127.0.0.1:%1/api").arg(port));
    QSignalSpy failedSpy(&client, &JplHorizonsClient::queryFailed);

    client.queryByName(QStringLiteral("req-4"), QStringLiteral("Ceres"));

    QVERIFY(failedSpy.wait());
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-4"));

    server->deleteLater();
}

void TestJplHorizonsClient::queryByNameFailsWhenServerUnreachable()
{
    JplHorizonsClient client(nullptr, QStringLiteral("http://127.0.0.1:1/api"));
    QSignalSpy failedSpy(&client, &JplHorizonsClient::queryFailed);

    client.queryByName(QStringLiteral("req-5"), QStringLiteral("Ceres"));

    QVERIFY(failedSpy.wait());
    QCOMPARE(failedSpy.first().at(0).toString(), QStringLiteral("req-5"));
}

QTEST_MAIN(TestJplHorizonsClient)
#include "tst_jplhorizonsclient.moc"
