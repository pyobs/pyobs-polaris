#include "ShellCommandParser.h"

#include <QVector>

namespace shell {

namespace {

enum class TokenKind { Name, Dot, Open, Close, Comma, Minus, Number, String };

struct Token {
    TokenKind kind;
    QString text; // Name text, or unquoted String content
    double number = 0.0; // valid only for Number
};

// Hand-rolled lexer, not Python's `tokenize` module - this project links no
// Python runtime, and the grammar is small enough not to need one. Returns
// std::nullopt on any character/token it can't make sense of (unterminated
// string, malformed number, unrecognized character).
std::optional<QVector<Token>> lex(const QString &input)
{
    QVector<Token> tokens;
    const int n = input.size();
    int i = 0;

    while (i < n) {
        const QChar c = input.at(i);

        if (c.isSpace()) {
            ++i;
            continue;
        }

        if (c.isLetter() || c == QLatin1Char('_')) {
            const int start = i;
            ++i;
            while (i < n && (input.at(i).isLetterOrNumber() || input.at(i) == QLatin1Char('_'))) {
                ++i;
            }
            tokens.push_back({ TokenKind::Name, input.mid(start, i - start), 0.0 });
            continue;
        }

        if (c.isDigit()) {
            const int start = i;
            ++i;
            while (i < n && input.at(i).isDigit()) {
                ++i;
            }
            if (i < n && input.at(i) == QLatin1Char('.')) {
                ++i;
                if (i >= n || !input.at(i).isDigit()) {
                    return std::nullopt; // e.g. "1." with no digit after the point
                }
                while (i < n && input.at(i).isDigit()) {
                    ++i;
                }
            }
            if (i < n && (input.at(i) == QLatin1Char('e') || input.at(i) == QLatin1Char('E'))) {
                ++i;
                if (i < n && (input.at(i) == QLatin1Char('+') || input.at(i) == QLatin1Char('-'))) {
                    ++i;
                }
                if (i >= n || !input.at(i).isDigit()) {
                    return std::nullopt; // e.g. "1e" or "1e+" with no exponent digits
                }
                while (i < n && input.at(i).isDigit()) {
                    ++i;
                }
            }
            bool ok = false;
            const double value = input.mid(start, i - start).toDouble(&ok);
            if (!ok) {
                return std::nullopt;
            }
            tokens.push_back({ TokenKind::Number, QString(), value });
            continue;
        }

        if (c == QLatin1Char('"') || c == QLatin1Char('\'')) {
            const QChar quote = c;
            ++i;
            QString value;
            bool closed = false;
            while (i < n) {
                const QChar ch = input.at(i);
                if (ch == QLatin1Char('\\') && i + 1 < n) {
                    value += ch;
                    value += input.at(i + 1);
                    i += 2;
                    continue;
                }
                if (ch == quote) {
                    closed = true;
                    ++i;
                    break;
                }
                value += ch;
                ++i;
            }
            if (!closed) {
                return std::nullopt; // unterminated string
            }
            tokens.push_back({ TokenKind::String, value, 0.0 });
            continue;
        }

        switch (c.toLatin1()) {
        case '.':
            tokens.push_back({ TokenKind::Dot, QString(), 0.0 });
            break;
        case '(':
            tokens.push_back({ TokenKind::Open, QString(), 0.0 });
            break;
        case ')':
            tokens.push_back({ TokenKind::Close, QString(), 0.0 });
            break;
        case ',':
            tokens.push_back({ TokenKind::Comma, QString(), 0.0 });
            break;
        case '-':
            tokens.push_back({ TokenKind::Minus, QString(), 0.0 });
            break;
        default:
            return std::nullopt; // unrecognized character
        }
        ++i;
    }

    return tokens;
}

}

std::optional<ParsedCommand> ShellCommandParser::parse(const QString &input)
{
    const auto tokensOpt = lex(input);
    if (!tokensOpt) {
        return std::nullopt;
    }
    const QVector<Token> &tokens = *tokensOpt;

    // Mirrors ShellCommand.parse()'s ParserState machine (Module/ModSep/
    // Command/Open/Param/ParamSep), minus the Python-tokenize-specific
    // START/CLOSE bookkeeping - "is this the last token" is checked directly
    // at each point a closing ')' is accepted instead.
    enum class State { Module, ModSep, Command, Open, Param, ParamSep };
    State state = State::Module;

    QString module;
    QString command;
    QVariantList params;
    bool negate = false;

    for (int i = 0; i < tokens.size(); ++i) {
        const Token &t = tokens.at(i);
        const bool isLast = (i == tokens.size() - 1);

        switch (state) {
        case State::Module:
            if (t.kind != TokenKind::Name) {
                return std::nullopt;
            }
            module = t.text;
            state = State::ModSep;
            break;

        case State::ModSep:
            if (t.kind != TokenKind::Dot) {
                return std::nullopt;
            }
            state = State::Command;
            break;

        case State::Command:
            if (t.kind != TokenKind::Name) {
                return std::nullopt;
            }
            command = t.text;
            state = State::Open;
            break;

        case State::Open:
            if (t.kind != TokenKind::Open) {
                return std::nullopt;
            }
            state = State::Param;
            break;

        case State::Param:
            if (params.isEmpty() && !negate && t.kind == TokenKind::Close) {
                return isLast ? std::make_optional(ParsedCommand { module, command, params }) : std::nullopt;
            }
            if (t.kind == TokenKind::Minus) {
                if (negate) {
                    return std::nullopt; // no double negation
                }
                negate = true;
                break;
            }
            if (t.kind == TokenKind::Number) {
                params.push_back(negate ? -t.number : t.number);
                negate = false;
                state = State::ParamSep;
                break;
            }
            if (t.kind == TokenKind::String) {
                if (negate) {
                    return std::nullopt; // unary minus is only valid before a NUMBER
                }
                params.push_back(t.text);
                state = State::ParamSep;
                break;
            }
            return std::nullopt;

        case State::ParamSep:
            if (t.kind == TokenKind::Comma) {
                state = State::Param;
                break;
            }
            if (t.kind == TokenKind::Close) {
                return isLast ? std::make_optional(ParsedCommand { module, command, params }) : std::nullopt;
            }
            return std::nullopt;
        }
    }

    return std::nullopt; // ran out of tokens before a closing ')'
}

}
