#include <QTest>

#include "CoordinateTransform.h"

using namespace coordxform;

namespace {

// Tolerance for comparing against astropy's reference values - libnova
// and astropy use different underlying reduction algorithms (libnova's
// own vs. astropy's ERFA/IAU2000), so exact equality isn't expected, just
// close agreement. A few arcminutes is plenty precise for a "preview
// before committing to Move" UI.
constexpr double kToleranceDeg = 0.05;

void compareDeg(double actual, double expected, const char *label)
{
    QVERIFY2(std::abs(actual - expected) < kToleranceDeg,
             qUtf8Printable(QStringLiteral("%1: expected %2, got %3").arg(label).arg(expected).arg(actual)));
}

}

class TestCoordinateTransform : public QObject
{
    Q_OBJECT

private slots:
    void equatorialToHorizontalMatchesAstropyBerlin();
    void equatorialToHorizontalMatchesAstropySydney();
    void equatorialToHorizontalMatchesAstropyMaunaKea();
    void horizontalToEquatorialIsTheInverse();
    void azimuthIsNorthBasedNotLibnovaSouthBased();
};

// Reference values computed via astropy (pyobs-core/.venv), pressure=0
// (no refraction, matching pyobs-core's own astroplan.Observer default -
// see DEVELOPMENT.md) - not asserted from memory, actually run:
//   SkyCoord(ra, dec, frame=ICRS).transform_to(
//       AltAz(location=EarthLocation.from_geodetic(lon, lat, height),
//             obstime=Time(jd, format="jd"), pressure=0*u.hPa))

void TestCoordinateTransform::equatorialToHorizontalMatchesAstropyBerlin()
{
    const EquatorialCoord coord { 83.633, 22.0145 };
    const ObserverLocation location { 52.52, 13.405, 34.0 };
    const HorizontalCoord result = equatorialToHorizontal(coord, location, 2460500.0);

    compareDeg(result.alt, 48.765657, "alt");
    compareDeg(result.az, 236.449355, "az");
}

void TestCoordinateTransform::equatorialToHorizontalMatchesAstropySydney()
{
    const EquatorialCoord coord { 201.298, -11.161 };
    const ObserverLocation location { -33.8688, 151.2093, 58.0 };
    const HorizontalCoord result = equatorialToHorizontal(coord, location, 2460500.5);

    compareDeg(result.alt, -19.525295, "alt");
    compareDeg(result.az, 119.220026, "az");
}

void TestCoordinateTransform::equatorialToHorizontalMatchesAstropyMaunaKea()
{
    const EquatorialCoord coord { 10.68, 41.27 };
    const ObserverLocation location { 19.8283, -155.478, 4200.0 };
    const HorizontalCoord result = equatorialToHorizontal(coord, location, 2460600.25);

    compareDeg(result.alt, -12.824531, "alt");
    compareDeg(result.az, 323.434708, "az");
}

void TestCoordinateTransform::horizontalToEquatorialIsTheInverse()
{
    // Round-trip through both conversions (same technique the astropy
    // reference computation itself used to sanity-check its own numbers)
    // rather than a second independent set of reference values - confirms
    // the inverse function and the azimuth-convention fix are consistent
    // with each other, not just individually plausible.
    const EquatorialCoord original { 83.633, 22.0145 };
    const ObserverLocation location { 52.52, 13.405, 34.0 };
    const double julianDay = 2460500.0;

    const HorizontalCoord horizontal = equatorialToHorizontal(original, location, julianDay);
    const EquatorialCoord roundTripped = horizontalToEquatorial(horizontal, location, julianDay);

    compareDeg(roundTripped.ra, original.ra, "ra");
    compareDeg(roundTripped.dec, original.dec, "dec");
}

void TestCoordinateTransform::azimuthIsNorthBasedNotLibnovaSouthBased()
{
    // Real bug this test exists to catch: libnova's own ln_hrz_posn.az is
    // South-based (0=South/90=West/180=North/270=East, confirmed from
    // libnova/ln_types.h's own doc comment) - a well-known gotcha (INDI/
    // KStars both correct for it). If equatorialToHorizontal() ever
    // regressed to returning the raw uncorrected libnova value, this
    // Berlin case's az would come back as 56.449355 (236.449355 - 180)
    // instead of 236.449355 - off by exactly 180 degrees, which
    // kToleranceDeg would never mask.
    const EquatorialCoord coord { 83.633, 22.0145 };
    const ObserverLocation location { 52.52, 13.405, 34.0 };
    const HorizontalCoord result = equatorialToHorizontal(coord, location, 2460500.0);

    QVERIFY(std::abs(result.az - 56.449355) > 90.0);
}

QTEST_MAIN(TestCoordinateTransform)
#include "tst_coordinatetransform.moc"
