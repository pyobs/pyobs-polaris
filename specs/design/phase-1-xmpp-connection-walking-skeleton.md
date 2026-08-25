# Phase 1 — XMPP connection walking skeleton

Status: implemented, closed.

`comm::XmppClient` (QObject, `QML_ELEMENT`) wraps `QXmppClient`:
`connectToServer(jid, password)`, a `status` property
(`disconnected|connecting|connected|error`) mirroring `useXmpp.ts`'s
`XmppStatus` states exactly. Plain TCP only (`QXmppClient::connectToServer`)
— WebSocket transport isn't implemented; a WASM/browser build isn't
currently planned (dropped from `TODO.md`: beyond the transport swap, it
would also need a browser-safe replacement for keychain-backed password
storage and for the filesystem-based plugin loader, plus an unproven
Emscripten build of `cfitsio` — enough open design questions that it
isn't worth roadmapping speculatively). TLS stays strict
(`TLSEnabled`, full certificate
validation) by default; `insecureSkipTlsVerification` is an explicit,
off-by-default opt-in surfaced as a clearly-labeled login checkbox, for
self-signed dev certs only - `XmppClient` itself never persists it or
reads it from an ambient env var (see the "Configuration file + saved
accounts" (`specs/design/configuration-file-and-saved-accounts.md`) for how a *saved account* remembers its own
choice).

