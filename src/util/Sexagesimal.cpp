#include "Sexagesimal.h"

#include <QRegularExpression>
#include <QStringList>
#include <cmath>

namespace sexagesimal {

namespace {

// Splits the (sign-stripped) remainder into numeric tokens by treating
// every run of characters that isn't a digit or '.' as a separator -
// handles "12:34:56.7", "12 34 56.7", and "12h34m56.7s" uniformly
// without needing a separate regex per notation.
QStringList tokenize(const QString &text)
{
    static const QRegularExpression separator(QStringLiteral("[^0-9.]+"));
    return text.split(separator, Qt::SkipEmptyParts);
}

}

std::optional<double> parseCoordinate(const QString &text, bool isHours)
{
    const QString trimmed = text.trimmed();
    if (trimmed.isEmpty()) {
        return std::nullopt;
    }

    double sign = 1.0;
    QString rest = trimmed;
    if (rest.startsWith(QLatin1Char('-'))) {
        sign = -1.0;
        rest = rest.mid(1);
    } else if (rest.startsWith(QLatin1Char('+'))) {
        rest = rest.mid(1);
    }

    const QStringList tokens = tokenize(rest);
    if (tokens.isEmpty() || tokens.size() > 3) {
        return std::nullopt;
    }

    bool ok = false;

    if (tokens.size() == 1) {
        // Single bare number - always plain decimal degrees, for both RA
        // and Dec (see this function's own header comment for why) - the
        // sign stripped above is reapplied here rather than left to
        // QString::toDouble(), since `rest` no longer contains it.
        const double value = tokens.at(0).toDouble(&ok);
        return ok ? std::make_optional(sign * value) : std::nullopt;
    }

    const double first = tokens.at(0).toDouble(&ok);
    if (!ok) {
        return std::nullopt;
    }

    const double minutes = tokens.at(1).toDouble(&ok);
    if (!ok || minutes < 0.0 || minutes >= 60.0) {
        return std::nullopt;
    }

    double seconds = 0.0;
    if (tokens.size() == 3) {
        seconds = tokens.at(2).toDouble(&ok);
        if (!ok || seconds < 0.0 || seconds >= 60.0) {
            return std::nullopt;
        }
    }

    const double magnitude = first + minutes / 60.0 + seconds / 3600.0;
    const double value = sign * magnitude;
    return isHours ? value * 15.0 : value;
}

double Sexagesimal::parseRa(const QString &text) const
{
    const auto result = parseCoordinate(text, true);
    return result.has_value() ? *result : std::nan("");
}

double Sexagesimal::parseDec(const QString &text) const
{
    const auto result = parseCoordinate(text, false);
    return result.has_value() ? *result : std::nan("");
}

}
