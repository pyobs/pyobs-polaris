#pragma once

#include <QObject>
#include <QVariantMap>
#include <qqmlintegration.h>

namespace coordxform {

// Degrees.
struct EquatorialCoord {
    double ra;
    double dec;
};

// Degrees. az is North-based (0 = North, 90 = East, 180 = South, 270 =
// West), matching this project's existing IPointingAltAz/AltAzState
// convention everywhere else - NOT libnova's own struct ln_hrz_posn
// convention (0 = South, 90 = West, 180 = North, 270 = East, confirmed
// from libnova/ln_types.h's own doc comment) - equatorialToHorizontal()/
// horizontalToEquatorial() below convert at the boundary so nothing
// downstream of this file needs to know libnova's convention exists.
struct HorizontalCoord {
    double alt;
    double az;
};

// Degrees, degrees, meters. longitude is positive-East, same convention
// libnova's own ln_lnlat_posn uses (confirmed from source) and the same
// one most users will type in without a sign-convention surprise.
struct ObserverLocation {
    double latitude;
    double longitude;
    double elevation;
};

// Pure functions, no Qt object machinery - independently unit-testable
// (tests/util/tst_coordinatetransform.cpp) without an event loop or QML
// registration, same "plain free function" precedent as
// codec::xmlToValue (Decode.h) rather than PlotItem's QML-facing-class
// one. julianDay is an explicit parameter, not read from the system
// clock internally, so these stay deterministic - CoordinateTransform
// below (the QML-facing adapter) composes nowJulianDay() + these for
// "preview right now".
//
// No atmospheric refraction correction is applied. Confirmed against
// pyobs-core source (astroplan.Observer, constructed without pressure/
// temperature by pyobs.object.Object) that the server itself doesn't
// apply one either - matching that keeps this preview consistent with
// what move_radec's own server-side min_altitude check actually
// computes, not a systematically different (refracted) answer.
HorizontalCoord equatorialToHorizontal(const EquatorialCoord &coord, const ObserverLocation &location,
                                       double julianDay);
EquatorialCoord horizontalToEquatorial(const HorizontalCoord &coord, const ObserverLocation &location,
                                       double julianDay);

// Current UTC time as a libnova Julian Day (wraps ln_get_julian_from_sys()).
double nowJulianDay();

// Thin QML-facing adapter over the pure functions above - a singleton
// (one instance for the whole app, no per-connection state, unlike
// XmppClient) since this is stateless computation. Returns
// QVariantMap{"ra":...,"dec":...}/{"alt":...,"az":...} rather than a
// dedicated QML value type, matching this project's existing convention
// of plain QVariantMap/QVariantList across the C++/QML boundary (see
// VariantBridge.h) over introducing a new Q_GADGET type for two simple
// field pairs. Purely informational for TelescopeView.qml's destination
// preview - never changes what move_radec()/move_altaz() actually sends,
// which stays exactly the user's typed/spun values, unchanged.
class CoordinateTransform : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit CoordinateTransform(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    Q_INVOKABLE QVariantMap equatorialToHorizontal(double raDeg, double decDeg, double latDeg, double lonDeg,
                                                   double elevationM) const;
    Q_INVOKABLE QVariantMap horizontalToEquatorial(double altDeg, double azDeg, double latDeg, double lonDeg,
                                                   double elevationM) const;
};

}
