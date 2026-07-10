#include "CoordinateTransform.h"

#include <libnova/julian_day.h>
#include <libnova/precession.h>
#include <libnova/transform.h>

#include <cmath>

namespace coordxform {

namespace {

// libnova's own ln_hrz_posn.az convention (0 = South, 90 = West, 180 =
// North, 270 = East - confirmed directly from libnova/ln_types.h's own
// doc comment) is exactly 180 degrees rotated from the North-based
// convention this project uses everywhere else (IPointingAltAz's own
// AltAzState.az). Same conversion both directions - it's its own inverse.
double convertAzimuthConvention(double az)
{
    double result = std::fmod(az + 180.0, 360.0);
    if (result < 0.0) {
        result += 360.0;
    }
    return result;
}

}

HorizontalCoord equatorialToHorizontal(const EquatorialCoord &coord, const ObserverLocation &location,
                                       double julianDay)
{
    // ln_get_hrz_from_equ expects mean-of-date coordinates, not J2000 -
    // real bug caught empirically (a ~0.2-0.4 degree residual against
    // astropy's reference values that tracked almost exactly with the
    // amount of precession since J2000 for the test dates used). RA/Dec
    // everywhere else in this project (IPointingRaDec's own RaDecState,
    // what a user types into TelescopeView.qml) is J2000/ICRS, matching
    // pyobs-core's own BaseTelescope.move_radec (SkyCoord(..., frame=ICRS)
    // - see basetelescope.py) - precess forward to the target epoch first,
    // confirmed via precession.c's own doc comment ("Uses mean equatorial
    // coordinates and is only for initial epoch J2000.0").
    ln_equ_posn j2000Object { coord.ra, coord.dec };
    ln_equ_posn dateObject;
    ln_get_equ_prec(&j2000Object, julianDay, &dateObject);

    ln_lnlat_posn observer { location.longitude, location.latitude };
    ln_hrz_posn result;
    ln_get_hrz_from_equ(&dateObject, &observer, julianDay, &result);
    return HorizontalCoord { result.alt, convertAzimuthConvention(result.az) };
}

EquatorialCoord horizontalToEquatorial(const HorizontalCoord &coord, const ObserverLocation &location,
                                       double julianDay)
{
    ln_hrz_posn object { convertAzimuthConvention(coord.az), coord.alt };
    ln_lnlat_posn observer { location.longitude, location.latitude };
    ln_equ_posn dateResult;
    ln_get_equ_from_hrz(&object, &observer, julianDay, &dateResult);

    // Inverse of the precession step above: ln_get_equ_from_hrz returns
    // mean-of-date coordinates, precess back to J2000 to match this
    // project's RA/Dec convention everywhere else.
    ln_equ_posn j2000Result;
    ln_get_equ_prec2(&dateResult, julianDay, JD2000, &j2000Result);
    return EquatorialCoord { j2000Result.ra, j2000Result.dec };
}

double nowJulianDay()
{
    return ln_get_julian_from_sys();
}

QVariantMap CoordinateTransform::equatorialToHorizontal(double raDeg, double decDeg, double latDeg, double lonDeg,
                                                         double elevationM) const
{
    // libnova's ln_get_hrz_from_equ takes no elevation input at all - not
    // part of this simplified topocentric transform (unlike astropy's
    // EarthLocation-based one, which does account for observer height).
    // Still accepted here and stored in AppSettings for forward
    // compatibility/consistency with what the user actually enters, but
    // genuinely unused by this specific computation.
    const auto result = coordxform::equatorialToHorizontal(
        { raDeg, decDeg }, { latDeg, lonDeg, elevationM }, coordxform::nowJulianDay());
    return { { QStringLiteral("alt"), result.alt }, { QStringLiteral("az"), result.az } };
}

QVariantMap CoordinateTransform::horizontalToEquatorial(double altDeg, double azDeg, double latDeg, double lonDeg,
                                                         double elevationM) const
{
    const auto result = coordxform::horizontalToEquatorial(
        { altDeg, azDeg }, { latDeg, lonDeg, elevationM }, coordxform::nowJulianDay());
    return { { QStringLiteral("ra"), result.ra }, { QStringLiteral("dec"), result.dec } };
}

}
