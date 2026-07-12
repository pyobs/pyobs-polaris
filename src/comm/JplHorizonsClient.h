#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <optional>
#include <qqmlintegration.h>

namespace comm {

// Degrees, degrees, human-readable target name (e.g. "Ceres (2000001)") -
// the astrometric RA/Dec Horizons reports for `name` at the current
// moment (geocentric, "500@399" - matches astroquery's own
// `Horizons(location=None, ...)` default, confirmed from its source) plus
// whatever "Target body name:" line the response itself carries, purely
// for a nicer confirmation message (falls back to the raw searched name
// if that line isn't found for some target type).
struct JplHorizonsResult {
    double ra;
    double dec;
    QString targetName;
};

// Parses a JPL Horizons `format=text`+`CSV_FORMAT=YES` ephemeris
// response. The interesting data lives between the response's own
// `$$SOE`/`$$EOE` markers (Horizons' "start/end of ephemeris" convention)
// - this class's fixed request (a single `TLIST` epoch, `QUANTITIES='1'`
// i.e. astrometric RA & DEC only) always produces exactly one CSV data
// row there with a fixed column layout, confirmed live against the real
// service: `<datetime>, , , <RA deg>, <DEC deg>,` - the two blank fields
// between the datetime and RA are circumstance-flag columns Horizons
// always emits regardless of which quantities were requested, not
// something QUANTITIES='1' controls.
//
// Returns std::nullopt when there's no `$$SOE` block at all - which,
// confirmed live, is exactly what Horizons returns for every failure
// mode this class needs to handle uniformly (unknown name, no match, and
// an ambiguous name matching several bodies all produce a response with
// no ephemeris block, just a diagnostic message instead) - matching
// pyobs-gui's own single generic "No result found" message not
// distinguishing these cases either.
std::optional<JplHorizonsResult> parseJplHorizonsResponse(const QByteArray &response, const QString &fallbackName);

// Resolves a solar-system body name/designation/number (e.g. "Ceres",
// "499" for Mars, "Halley" - anything Horizons' own name-matching
// accepts) to its current apparent-sky position via JPL Horizons' own
// HTTP API, matching pyobs-gui's own telescopewidget.py
// `_query_jpl_horizons()` (astroquery's `Horizons(...).ephemerides()`)
// but talking the API directly instead of adding astroquery's own
// dependency stack - same reasoning as SimbadClient.h's own header
// comment on why that talks SIMBAD's TAP service directly rather than
// pulling in astroquery for one HTTP request. Unlike SIMBAD (a fixed
// catalog position), Horizons computes a body's *actual current*
// position (light-time corrected, geocentric) for the requested epoch -
// this class always asks for "now" (`coordxform::nowJulianDay()`, the
// same helper CoordinateTransform's own QML adapter uses for its
// preview), matching pyobs-gui's own `epochs=Time.now().jd`.
//
// No caching, no retry - same "every call is a live request" philosophy
// as VfsClient/SimbadClient. Each call gets its own opaque requestId
// (caller-supplied) for the same multi-in-flight-caller reason those two
// classes' own header comments already explain.
class JplHorizonsClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    // `apiUrl` defaults to the real Horizons API endpoint - overridable
    // only for tests (a local stub HTTP server, same technique
    // tst_vfsclient.cpp/tst_simbadclient.cpp already use).
    explicit JplHorizonsClient(QObject *parent = nullptr,
                                QString apiUrl = QStringLiteral("https://ssd.jpl.nasa.gov/api/horizons.api"));

    // Starts an async lookup of `name`. queryReady(requestId, ra, dec,
    // targetName) or queryFailed(requestId, errorMessage) fires once the
    // request completes.
    Q_INVOKABLE void queryByName(const QString &requestId, const QString &name);

Q_SIGNALS:
    void queryReady(const QString &requestId, double ra, double dec, const QString &targetName);
    void queryFailed(const QString &requestId, const QString &errorMessage);

private:
    QNetworkAccessManager m_networkAccessManager;
    QString m_apiUrl;
};

} // namespace comm
