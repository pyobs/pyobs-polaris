#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <optional>
#include <qqmlintegration.h>

namespace comm {

// Degrees, degrees, canonical/matched identifier - the three columns
// this class's fixed ADQL query below asks SIMBAD's TAP service for.
struct SimbadResult {
    double ra;
    double dec;
    QString mainId;
};

// Parses a SIMBAD TAP `sync` endpoint's CSV response (this project
// always requests FORMAT=csv - see queryByName()) - a header line
// ("ra,dec,main_id") followed by zero or one data line (this class's own
// ADQL query matches by exact identifier via SIMBAD's `ident` table, so
// realistically never more than one row - unlike pyobs-gui's own
// _query_simbad(), which used astroquery's fuzzy Simbad.query_object()
// and could get several, only ever using the first). `main_id` is
// double-quoted by the server whenever it contains a space (confirmed
// live against the real endpoint, e.g. `"M  31"`), so this does real
// (if minimal) RFC4180 quoted-field parsing, not a bare QString::split().
// Returns std::nullopt for a header-only response (object not found), a
// response that isn't CSV at all (e.g. the VOTable/XML error document
// the service sends for a malformed query - never expected here since
// this class's own query is fixed and pre-tested, but still handled
// rather than trusted blindly), or unparseable ra/dec fields.
std::optional<SimbadResult> parseSimbadCsv(const QByteArray &csv);

// Resolves an object name (any SIMBAD-known identifier - catalog
// designations like "M31"/"NGC 224" and common names like "Sirius" all
// work, confirmed live against the real service) to coordinates via
// SIMBAD's TAP service, matching pyobs-gui's own telescopewidget.py
// `_query_simbad()` (astroquery's `Simbad.query_object()` under the
// hood) but talking TAP/ADQL directly instead of adding astroquery's own
// dependency stack - this project already has QNetworkAccessManager
// (see VfsClient.h, the same "thin QNetworkAccessManager wrapper,
// signal-based completion" shape this mirrors) and Qt has no equivalent
// need for astroquery's Python-side VOTable machinery once a plain CSV
// response is requested instead of the service's own VOTable/XML
// default.
//
// No caching, no retry - matches VfsClient's own "every call is a live
// request" philosophy. Each call gets its own opaque requestId
// (caller-supplied) so a caller with multiple in-flight queries (e.g.
// several ITelescope modules' pages open at once, sharing this one
// instance) can tell its own queryReady/queryFailed signals apart - this
// class holds no per-request state beyond the QNetworkReply itself.
class SimbadClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    // `tapSyncUrl` defaults to the real SIMBAD TAP sync endpoint -
    // overridable only for tests (a local stub HTTP server, same
    // technique tst_vfsclient.cpp already uses for VfsClient) - QML/
    // production callers always get the real default, never override it.
    explicit SimbadClient(QObject *parent = nullptr,
                           QString tapSyncUrl = QStringLiteral("https://simbad.cds.unistra.fr/simbad/sim-tap/sync"));

    // Starts an async lookup of `name`. queryReady(requestId, ra, dec,
    // mainId) or queryFailed(requestId, errorMessage) fires once the
    // request completes - the latter for both "no object by that name"
    // and any actual network/HTTP failure, matching pyobs-gui's own
    // single "No result found" message not distinguishing the two either.
    Q_INVOKABLE void queryByName(const QString &requestId, const QString &name);

Q_SIGNALS:
    void queryReady(const QString &requestId, double ra, double dec, const QString &mainId);
    void queryFailed(const QString &requestId, const QString &errorMessage);

private:
    QNetworkAccessManager m_networkAccessManager;
    QString m_tapSyncUrl;
};

} // namespace comm
