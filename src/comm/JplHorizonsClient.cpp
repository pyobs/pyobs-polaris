#include "JplHorizonsClient.h"

#include "CoordinateTransform.h"

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>

namespace comm {

namespace {

// Extracts the single ephemeris data row between `$$SOE`/`$$EOE`, if
// present at all - see parseJplHorizonsResponse()'s own header comment
// for why "no $$SOE line" uniformly means "nothing to show" across every
// failure mode this needs to handle.
QString extractEphemerisLine(const QString &text)
{
    const QStringList lines = text.split(QRegularExpression(QStringLiteral("\r?\n")));
    int soeIndex = -1;
    for (int i = 0; i < lines.size(); ++i) {
        if (lines.at(i).trimmed() == QStringLiteral("$$SOE")) {
            soeIndex = i;
            break;
        }
    }
    if (soeIndex < 0 || soeIndex + 1 >= lines.size()) {
        return QString();
    }
    return lines.at(soeIndex + 1);
}

// "Target body name: Ceres (2000001)                 {source: dawn_final}"
// -> "Ceres (2000001)" - purely cosmetic (the confirmation message), so a
// missing/differently-shaped line just falls back to the searched name
// rather than failing the whole lookup over it.
QString extractTargetName(const QString &text, const QString &fallbackName)
{
    static const QRegularExpression pattern(QStringLiteral("Target body name:\\s*(.+?)\\s*\\{"));
    const QRegularExpressionMatch match = pattern.match(text);
    if (!match.hasMatch()) {
        return fallbackName;
    }
    return match.captured(1).trimmed();
}

}

std::optional<JplHorizonsResult> parseJplHorizonsResponse(const QByteArray &response, const QString &fallbackName)
{
    const QString text = QString::fromUtf8(response);
    const QString dataLine = extractEphemerisLine(text);
    if (dataLine.isEmpty()) {
        return std::nullopt;
    }

    const QStringList fields = dataLine.split(QLatin1Char(','));
    if (fields.size() < 5) {
        return std::nullopt;
    }

    bool raOk = false;
    bool decOk = false;
    const double ra = fields.at(3).trimmed().toDouble(&raOk);
    const double dec = fields.at(4).trimmed().toDouble(&decOk);
    if (!raOk || !decOk) {
        return std::nullopt;
    }

    return JplHorizonsResult { ra, dec, extractTargetName(text, fallbackName) };
}

JplHorizonsClient::JplHorizonsClient(QObject *parent, QString apiUrl)
    : QObject(parent)
    , m_apiUrl(std::move(apiUrl))
{
}

void JplHorizonsClient::queryByName(const QString &requestId, const QString &name)
{
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("format"), QStringLiteral("text"));
    query.addQueryItem(QStringLiteral("COMMAND"), QStringLiteral("'%1'").arg(name));
    query.addQueryItem(QStringLiteral("EPHEM_TYPE"), QStringLiteral("OBSERVER"));
    // Geocentric - matches astroquery's own Horizons(location=None, ...)
    // default (confirmed from source: self.location = '500@399').
    query.addQueryItem(QStringLiteral("CENTER"), QStringLiteral("'500@399'"));
    // Astrometric RA & DEC only - the one quantity pyobs-gui's own
    // _query_jpl_horizons() actually reads (eph["RA"]/eph["DEC"]) out of
    // astroquery's much broader default request-everything set.
    query.addQueryItem(QStringLiteral("QUANTITIES"), QStringLiteral("'1'"));
    query.addQueryItem(QStringLiteral("CSV_FORMAT"), QStringLiteral("YES"));
    query.addQueryItem(QStringLiteral("ANG_FORMAT"), QStringLiteral("DEG"));
    query.addQueryItem(QStringLiteral("TLIST"), QString::number(coordxform::nowJulianDay(), 'f', 6));

    QUrl url(m_apiUrl);
    url.setQuery(query);

    QNetworkReply *reply = m_networkAccessManager.get(QNetworkRequest(url));
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestId, name] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT queryFailed(requestId, reply->errorString());
            return;
        }

        const std::optional<JplHorizonsResult> result = parseJplHorizonsResponse(reply->readAll(), name);
        if (!result.has_value()) {
            Q_EMIT queryFailed(requestId, QStringLiteral("No result found for \"%1\"").arg(name));
            return;
        }

        Q_EMIT queryReady(requestId, result->ra, result->dec, result->targetName);
    });
}

} // namespace comm
