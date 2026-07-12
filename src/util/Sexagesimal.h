#pragma once

#include <QObject>
#include <QString>
#include <optional>
#include <qqmlintegration.h>

namespace sexagesimal {

// Parses `text` as either a plain decimal number (returned unchanged, in
// degrees) or a sign-prefixed sexagesimal "H:M:S" / "H M S" / "HhMmSs"
// string (colon, space, and h/m/s/d-letter separators all accepted,
// seconds optional - see the .cpp's own tokenize() comment for the exact
// rule). `isHours` multiplies a *sexagesimal* result by 15 (hours ->
// degrees) - only for the multi-component form, matching how RA is
// conventionally written in hours when colon-separated (SIMBAD/DS9/
// etc.). A single bare number always means plain decimal degrees
// regardless of `isHours`, for both RA and Dec - this project's own
// Move fields have always accepted plain decimal degrees directly (see
// TelescopeView.qml's "RA [deg]"/"Dec [deg]" labels), and this keeps
// that working unchanged now that sexagesimal notation is *also*
// accepted, rather than switching the field over to pyobs-gui's own
// telescopewidget.py behavior (which always parses via astropy's
// `SkyCoord(..., unit=(u.hour, u.deg))`, so even a lone typed number
// there means hours, never degrees, for RA).
//
// Returns std::nullopt for empty input, unparseable tokens, more than
// three components, or an out-of-range minutes/seconds component (each
// must be in [0, 60)) - deliberately no semantic range check on the
// final degrees value itself (e.g. RA past 360 or Dec past 90), just
// syntax validity, matching how the existing plain-decimal input never
// range-checked either.
std::optional<double> parseCoordinate(const QString &text, bool isHours);

// Thin QML-facing adapter, following CoordinateTransform.h's own "pure
// functions + singleton adapter" split (see that file). Returns NaN
// (rather than an optional - QML has no direct optional/nullopt idiom)
// when parseCoordinate() itself returns std::nullopt; callers check with
// `isNaN()`.
class Sexagesimal : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Sexagesimal(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

    Q_INVOKABLE double parseRa(const QString &text) const;
    Q_INVOKABLE double parseDec(const QString &text) const;
};

}
