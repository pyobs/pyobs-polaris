#include "SimbadClient.h"

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>

namespace comm {

namespace {

// Minimal RFC4180 quoted-field splitter for one CSV line - not a full
// CSV parser (no multi-line quoted fields, never needed here since every
// field this query can return is a single scalar), just enough to
// correctly split SIMBAD's own `"M  31"`-style quoted main_id values
// that a bare `QString::split(',')` would mishandle if such a field ever
// contained a comma (none of SIMBAD's own identifiers do today, but this
// doesn't rely on that staying true).
QStringList splitCsvLine(const QString &line)
{
    QStringList fields;
    QString current;
    bool inQuotes = false;

    for (int i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (inQuotes) {
            if (c == QLatin1Char('"')) {
                if (i + 1 < line.size() && line.at(i + 1) == QLatin1Char('"')) {
                    current += QLatin1Char('"');
                    ++i;
                } else {
                    inQuotes = false;
                }
            } else {
                current += c;
            }
        } else {
            if (c == QLatin1Char('"')) {
                inQuotes = true;
            } else if (c == QLatin1Char(',')) {
                fields << current;
                current.clear();
            } else {
                current += c;
            }
        }
    }
    fields << current;
    return fields;
}

}

std::optional<SimbadResult> parseSimbadCsv(const QByteArray &csv)
{
    const QString text = QString::fromUtf8(csv);
    // Splits on both \n and \r\n line endings, dropping any trailing
    // empty line the response's final newline would otherwise produce.
    const QStringList lines = text.split(QRegularExpression(QStringLiteral("\r?\n")), Qt::SkipEmptyParts);

    // Header-only (no object found) or not CSV at all (e.g. a VOTable/
    // XML error document - see this function's own header comment).
    if (lines.size() < 2) {
        return std::nullopt;
    }

    const QStringList fields = splitCsvLine(lines.at(1));
    if (fields.size() != 3) {
        return std::nullopt;
    }

    bool raOk = false;
    bool decOk = false;
    const double ra = fields.at(0).toDouble(&raOk);
    const double dec = fields.at(1).toDouble(&decOk);
    if (!raOk || !decOk) {
        return std::nullopt;
    }

    return SimbadResult { ra, dec, fields.at(2) };
}

SimbadClient::SimbadClient(QObject *parent, QString tapSyncUrl)
    : QObject(parent)
    , m_tapSyncUrl(std::move(tapSyncUrl))
{
}

void SimbadClient::queryByName(const QString &requestId, const QString &name)
{
    // Matches SIMBAD's own SQL-string escaping (confirmed live against
    // the real endpoint: a name containing a literal `'` needs it
    // doubled, standard SQL string-literal escaping, not backslash-
    // escaping) - without this, a name like "O'Brien" (hypothetical -
    // no such SIMBAD identifier, but the principle holds for any
    // apostrophe) would break the ADQL query's own string literal, not
    // just fail to match.
    const QString escapedName = QString(name).replace(QLatin1Char('\''), QStringLiteral("''"));
    const QString adql = QStringLiteral(
        "SELECT basic.ra, basic.dec, basic.main_id FROM basic "
        "JOIN ident ON basic.oid = ident.oidref WHERE ident.id = '%1'")
        .arg(escapedName);

    QUrlQuery query;
    query.addQueryItem(QStringLiteral("REQUEST"), QStringLiteral("doQuery"));
    query.addQueryItem(QStringLiteral("LANG"), QStringLiteral("ADQL"));
    query.addQueryItem(QStringLiteral("FORMAT"), QStringLiteral("csv"));
    query.addQueryItem(QStringLiteral("QUERY"), adql);

    QUrl url(m_tapSyncUrl);
    url.setQuery(query);

    QNetworkReply *reply = m_networkAccessManager.get(QNetworkRequest(url));
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestId, name] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            Q_EMIT queryFailed(requestId, reply->errorString());
            return;
        }

        const std::optional<SimbadResult> result = parseSimbadCsv(reply->readAll());
        if (!result.has_value()) {
            Q_EMIT queryFailed(requestId, QStringLiteral("No result found for \"%1\"").arg(name));
            return;
        }

        Q_EMIT queryReady(requestId, result->ra, result->dec, result->mainId);
    });
}

} // namespace comm
