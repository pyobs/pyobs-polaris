# Phase 6 — events

Status: implemented, closed.

Subscribes to every event a module's disco#info advertised
(`urn:pyobs:event:{name}:{version}`), hosted on the module's own bare JID
(PEP) — a different subscription path than Phase 4's pubsub-service state
nodes; don't conflate the two. Gotcha: events are **plain JSON on the
wire**, not the self-tagged `WireValue` vocabulary state/RPC use —
`<event xmlns="pyobs:event">{escaped JSON}</event>`, decoded with
`QJsonDocument::fromJson`; only `module` is derived client-side from the
notification's `from` JID (see `specs/design/phase-7-5-app-shell-login-and-sidebar-navigation.md`'s gotcha about why that
alone isn't reliable). Bounded in-memory event log (one central log for
the whole app, not per-widget — so no ref-counting needed here, unlike
Phase 4).

