# pyobs-gui++ — todo

What's planned next. See `DEVELOPMENT.md` for how to build, and for the
design decisions/gotchas behind everything already done (Phases 0–7.5).

Each item below should be its own PR/commit, buildable and runnable on its
own before moving to the next, and verified against a live ejabberd server
and real pyobs modules — not just unit tests. Never assume the schema
shape from memory of the Python/TS side; verify against source and the
real wire protocol. If an item's design turns out to need something not
anticipated here, fix this doc, don't just fix the code.

---

## Phase 8 — WebAssembly build

**Goal:** the same client, browser-deployable.

- Second Conan profile (Emscripten toolchain) alongside the native one —
  don't retrofit the native CMake setup for this later; get the second
  profile building (even just "hello world" Qt Quick in a canvas) before
  porting any XMPP code, to isolate WASM-specific build pain from protocol
  pain.
- Networking: raw `QXmppClient::connectToServer` (the native TCP path)
  does not work in a browser sandbox — this is where the WebSocket
  transport actually becomes necessary, same reasoning as `useXmpp.ts`'s
  `buildWsUrl()`/`wss://` handling.
- Threading: decide single-threaded vs. multithreaded WASM now, since it
  determines whether the deployment needs `Cross-Origin-Opener-Policy`/
  `Cross-Origin-Embedder-Policy` headers (`SharedArrayBuffer` requirement)
  — a hosting-environment constraint worth confirming works with wherever
  this actually gets deployed (SAAO's infrastructure) before committing to
  the multithreaded path.

**Acceptance:** the built `.wasm`/`.js`/`.html` bundle, served statically,
connects to the same ejabberd server the native build uses and renders the
same module list.

---

## Real parameterized command execution in Shell

**Goal:** `ShellView.qml`'s module → method → execute → log flow should
let you actually fill in command parameters and run them, the same way
`pyobs-web-client`'s `ShellView.vue` does — not just the current
all-null-params execution every entry point in this project uses so far
(see Phase 5/7.5 in `DEVELOPMENT.md`). Port `ShellView.vue`'s actual
parameter-entry behavior (per-`WireType` widgets: bool/enum/number/string)
rather than reinventing the UI from scratch.

- `ModuleListModel`'s `commands` role currently only exposes
  `{interface, name, paramCount}` (Phase 5) — needs to expose full
  `CommandSchema`s (param names/types/optionality) for real widgets to be
  built from.
- `codec::valueToXml` (Phase 5) already handles schema-aware encoding for
  non-null values; this is mostly new QML-side parameter UI plus wiring
  real values through `executeMethod` instead of `WireValue::null()` for
  every param.

---

## Loose ends from Phase 7

Not blocking, but worth closing out:

- `RoofWidget` hasn't had a real visual/interactive check on an actual
  display — only headless/offscreen verification so far (see
  `DEVELOPMENT.md`'s Phase 7 note on why: repeated loss of X11 access
  mid-session). Worth a manual look, now that a window reliably appears
  to look at (see the Phase 7.5 window-visibility fix in
  `DEVELOPMENT.md`).
- `RoofWidget` doesn't identify which module it belongs to on screen — it
  just shows up on the Dashboard unlabeled whenever an `IRoof` module is
  present, which reads as unclear if you don't already know it's the roof
  widget (came up as "what is this 'Roof' on the dashboard?" - a real
  first-impression question). Give it a visible heading/label (e.g. the
  module's JID or name) instead of relying on the reader already knowing
  what it is.
