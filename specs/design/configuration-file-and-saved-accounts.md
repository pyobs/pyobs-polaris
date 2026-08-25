# Configuration file + saved accounts

Status: implemented, closed.

**Goal:** a config file in the system's default location; a list of saved
login accounts (not just one remembered login) that can be added, edited,
and deleted, with per-account opt-in password storage - see `TODO.md`'s
original entries, now done. First shipped as a single remembered login,
then reworked into a full list on direct request once that landed - the
single-login version is gone, not kept alongside this.

- `config::AppSettings` (QObject, `QML_ELEMENT`) wraps a plain `QSettings`
  for genuinely app-wide, non-per-account settings — resolves to the
  system default location (e.g. `~/.config/pyobs/Polaris.conf` on
  Linux) purely from `QCoreApplication::setOrganizationName()`/
  `setApplicationName()` in `main.cpp`, which must run before any
  `QSettings` is constructed. Currently holds only
  `lastSelectedAccountId` (which row to preselect in the login window on
  next launch) - add more here as app-wide (not per-account) needs come
  up.
- `config::SavedAccountsModel` (`QAbstractListModel`, `QML_ELEMENT`) is
  the actual saved-account list: `id`/`jid`/`label`/`hasStoredPassword`/
  `host`/`port`/`insecureSkipTls` roles, persisted as a `QSettings` array
  (`beginReadArray`/`beginWriteArray`, key `"accounts"`, rewritten in full
  on every add/update/remove - never a bottleneck at this scale).
  `insecureSkipTls` (added after a report that "Save changes" silently
  dropped the login window's "Skip TLS" checkbox) is a deliberate
  exception to `XmppClient::insecureSkipTlsVerification`'s own
  never-persisted default (see Phase 1): a *saved account* is itself an
  explicit, visible, user-created record, so `LoginWindow.qml` reads this
  role back into `xmppClient.insecureSkipTlsVerification` in
  `selectAccount()` and writes it back out from that same live property
  when "Save as new account"/"Save changes" is clicked - a brand new,
  unselected connection is unaffected and still starts from `false`
  either way. **Each account's
  `id` is a generated `QUuid`, independent of its `jid`/`label`, and is
  what the keychain entry is actually keyed on** - editing an account's
  jid must never orphan its stored password, which keying on the jid
  itself would risk the moment it's edited.
- **Saving an account and storing its password are two fully independent
  actions**, not one bundled step: `addAccount()`/`updateAccount()` never
  touch the keychain at all; `storePassword()`/`clearStoredPassword()` are
  separate calls the login window only makes when its own "Store password
  in system keychain" checkbox says to. This is what makes "connect
  without storing credentials" the default rather than a special case:
  `LoginWindow.qml`'s Connect button *never* saves anything on its own -
  it just calls `xmppClient.connectToServer()` with whatever's currently
  in the fields, full stop. Saving/editing/deleting a row is only ever a
  deliberate, separate button click ("Save as new account"/"Save
  changes"/"Delete").
- **The password itself never touches `QSettings`/the config file.**
  `SavedAccountsModel` vendors **QtKeychain**
  (`frankosterfeld/qtkeychain`, tag `0.17.0`) via CMake `FetchContent`,
  same treatment as qxmpp (Phase 0) — `storePassword()`/`loadPassword()`/
  `clearStoredPassword()` go through `QKeychain::WritePasswordJob`/
  `ReadPasswordJob`/`DeletePasswordJob` (async, `finished` signal), keyed
  on the account's `id` under service `"Polaris"`. On Linux this needs
  `libsecret-1-dev` + `pkg-config` to build (see Prerequisites) and a
  running Secret Service provider (gnome-keyring/KWallet) at runtime for
  it to actually persist anything — `QKeychain::isAvailable()` is false
  without one, and `WritePasswordJob`s fail cleanly rather than silently
  falling back to plaintext (no `setInsecureFallback(true)` anywhere - not
  worth the risk for a password).
- **Windows/macOS build+test in CI now; the real keychain round-trip is
  still dev-machine-only.** QtKeychain ships a Windows Credential Manager
  (`wincred`) backend and a macOS Keychain backend alongside the Linux
  Secret Service one, and none of `SavedAccountsModel`'s code is
  Linux-specific — it only ever calls the generic
  `QKeychain::isAvailable()`/job API. CI (`.github/workflows/build.yml`)
  now runs the full build+test matrix on `windows-latest` and
  `macos-latest` too, not just `ubuntu-26.04` (getting there took several
  rounds of genuinely platform-specific fixes — wrong Qt `arch` for
  aqtinstall, macOS's Xcode SDK dropping the `AGL` framework, three
  separate libnova/MSVC CMake quirks, and Windows DLL discoverability
  causing tests to hang rather than fail — see this file's own git
  history on that workflow and on `CMakeLists.txt`/`cmake/
  Dependencies.cmake` for the details). That proves the code builds,
  links, and the rest of the test suite passes on both platforms. It does
  *not* prove the real keychain round-trip works there: `
  storeAndLoadPasswordRoundTripsThroughKeychain`/
  `removeAccountDeletesItsKeychainEntry` skip themselves under CI on
  every OS (`realKeychainBackendAvailable()` checks the same `CI` env var
  everywhere, not just Linux), so actually exercising Windows Credential
  Manager or macOS Keychain still requires someone running the app by
  hand on those platforms — doesn't meet this project's usual "verified
  against the real thing" bar until that happens.
- **Transactional commit, not optimistic:** `storePassword()` only flips
  `hasStoredPassword` to `true` *after* the keychain write succeeds
  (`credentialsSaved(id)`), never before - the same reasoning as the
  original single-login design (see git history): a machine with no
  keychain backend at all must never end up with `hasStoredPassword=true`
  and no password ever actually stored, silently re-failing
  `loadPassword()` forever after. `LoginWindow.qml` surfaces
  `credentialsSaveFailed(id)`/`credentialsForgetFailed(id)` as a visible
  (orange) notice for the same reason.
- `LoginWindow.qml` is list-left/details-right (`RowLayout` of a
  `ListView` bound to `accountsModel`, plus a details `ColumnLayout`), not
  a single form - `selectAccount(id)` (`id === ""` means "new connection")
  populates the detail fields and kicks off `loadPassword()` if
  `hasStoredPassword`. Each list row also has its own quick-connect
  (`▶`) button, enabled only when that account has a stored password -
  true one-click reconnect, tracked via `quickConnectPendingId` so the
  eventual `passwordReady(id, ...)` signal knows to call
  `connectToServer()` immediately instead of just prefilling the password
  field (plain row-click selection does the latter only). Guarded by `id
  !== root.selectedAccountId`/matching `quickConnectPendingId` checks so
  rapidly clicking two different rows' connect buttons can't cross-wire
  which account a delayed keychain read ends up connecting.
- `qt6keychain` builds as a shared library (`BUILD_SHARED_LIBS` defaults
  `ON` upstream) - like `libQXmppQt6.so.5`, it needs bundling alongside the
  `polaris` binary for releases (`.github/workflows/build.yml`'s
  packaging step), not just at dev-build time.
- Its own `autotest` subdirectory builds by default (gated on the CTest
  convention variable `BUILD_TESTING`, set via its own `include(CTest)`)
  — forced off in `CMakeLists.txt` since it's pure extra build time here;
  this project's own `tests/` registers via plain `add_test()`
  unconditionally, unaffected by that variable.
- `tests/config/tst_savedaccountsmodel.cpp` exercises the **real** OS
  keychain (skipping itself via `QSKIP` if `QKeychain::isAvailable()` is
  false) rather than mocking QtKeychain, matching this project's "verify
  against the real thing" philosophy elsewhere — every test that writes a
  keychain entry also deletes it again before finishing, so a run never
  leaves test credentials behind in a developer's real keychain.

**Follow-up, found live against a real SAAO server (`monet.saao.ac.za`):**
a saved account there connected successfully but appeared to hang for
about a minute before doing so. Root-caused with a throwaway headless
harness (same technique as the live-verification fixtures above, deleted
after use - and deliberately logging only `QXmppLogger::InformationMessage
| WarningMessage`, never `ReceivedMessage`/`SentMessage`, since those
include the raw SASL auth stanza i.e. the real password): that domain has
no DNS SRV records for its XMPP service, so `QXmppOutgoingClient` falls
back to trying legacy implicit-TLS on port 5223 first, then STARTTLS on
5222 - and 5223 is closed/filtered there in a way that silently drops the
connection instead of refusing it, so QXmpp has to wait out a full OS-level
TCP connect timeout (around a minute) before falling through to 5222,
which then connects and authenticates immediately. Not a bug in this
project - but indistinguishable from actually being stuck without knowing
the cause.

Fixed with a client-side escape hatch rather than requiring server/DNS
changes: `SavedAccountsModel` gained optional per-account `host`/`port`
override fields (empty/`0` = no override, normal SRV-based discovery), and
`XmppClient::connectToServer()` gained matching optional `host`/`port`
parameters - `QXmppConfiguration::setHost()` makes `QXmppOutgoingClient`
connect straight there, skipping SRV lookup (and the 5223 attempt)
entirely. `LoginWindow.qml` surfaces this as an "Override server address"
checkbox revealing host/port fields, applied consistently everywhere a
connection is initiated (the plain Connect button, and the per-row
quick-connect path). Verified live: enabling the override against
`monet.saao.ac.za:5222` connects immediately instead of stalling.

