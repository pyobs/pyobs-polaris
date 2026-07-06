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

## Loose ends from Phases 7 / 7.5

Not blocking, but worth closing out:

- `RoofWidget` hasn't had a real visual/interactive check on an actual
  display — only headless/offscreen verification so far (see
  `DEVELOPMENT.md`'s Phase 7 note on why: repeated loss of X11 access
  mid-session). Worth a manual look, now that a window reliably appears
  to look at (see the Phase 7.5 window-visibility fix in
  `DEVELOPMENT.md`).
- `ShellView.qml`'s command execution is still all-null params, same as
  every other entry point in this project so far — real, type-aware
  per-parameter widgets (bool/enum/number/string, built from each param's
  actual `WireType`) would need `ModuleListModel`'s `commands` role to
  expose full `CommandSchema`s, not just `{interface, name, paramCount}`
  (see Phase 5 in `DEVELOPMENT.md`). A reasonable next increment.
