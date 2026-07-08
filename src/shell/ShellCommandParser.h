#pragma once

#include <QString>
#include <QVariantList>
#include <optional>

namespace shell {

// A single parsed command: `module.command(arg1, arg2, ...)`. `params` holds
// one QVariant per positional arg - a double for a number literal, a QString
// for a quoted string - matching exactly what codec::fromQVariant() already
// consumes for each param's target FieldSchema.type
// (XmppClient::executeMethod()'s real-param overload), so no further
// bridging is needed once this is wired up to real dispatch.
struct ParsedCommand {
    QString module;
    QString command;
    QVariantList params;
};

// Ports pyobs-core's pyobs/utils/shellcommand.py ShellCommand.parse() grammar
// (read directly against the installed venv's source, not inferred): `module
// .command(` then zero or more positional args, each either a NUMBER
// (optional unary `-`) or a quoted STRING, comma-separated, closing `)`.
// Positional only - no named params, no bool/enum literals as a distinct
// token type (see TODO.md's Shell item, step 2).
//
// Two deliberate departures from the Python original, not faithful-port
// gaps - confirmed by reading pyobs-core's source, not assumed:
//   - Single-quoted strings are unquoted the same as double-quoted ones. The
//     Python original's `t.string[0] in ['"', '"']` check tests for a double
//     quote twice (a copy-paste bug), so a single-quoted string there falls
//     through to the "keep the raw token" branch and keeps its quotes
//     attached - not a behavior worth preserving.
//   - A unary `-` is only accepted directly before a NUMBER. The Python
//     original applies `sign` only when appending a NUMBER but still
//     silently *accepts* (and drops) a `-` before a STRING or a second `-`
//     in a row, since `sign` is simply overwritten to -1 rather than
//     validated - this parser rejects both as malformed input instead of
//     silently ignoring the stray token.
class ShellCommandParser
{
public:
    // Returns std::nullopt if `input` doesn't match the grammar - same hard
    // yes/no, no-partial-result convention as codec::parseVersionedFeature()
    // (SchemaParse.h), not an exception or an out-param error string (no
    // precedent for either elsewhere in this codebase).
    static std::optional<ParsedCommand> parse(const QString &input);
};

}
