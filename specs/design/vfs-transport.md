# VFS transport (`config::VfsEndpointsModel` + `comm::VfsClient`)

Status: implemented, closed.

**Scope**: the first slice of TODO.md's "`ICamera` follow-up: image
display, VFS" - config storage + HTTP fetch only, stopping at "bytes in
hand". No FITS decode (`cfitsio`) or image-display widget yet, and
nothing calls this from `CameraView.qml`'s `NewImageEvent` flow yet
either - there's nothing useful to do with raw bytes until decode exists.
Narrower than that TODO item's full scope on purpose; see TODO.md's own
updated text.

**Reference-side finding**: `pyobs-web-client` only has the *config* half
of this (`useVfsConfig.ts` + `SettingsView.vue`'s "VFS Endpoints"
section) - a per-bare-JID `{root, baseUrl, username, password}` list and
`resolveVfsPath()`. Nothing in `pyobs-web-client` actually fetches a file
with it - no `DataDisplayWidget` equivalent exists there at all. This
project is ahead of the reference implementation here, not porting an
existing end-to-end pattern.

**Wire-side confirmation** (`pyobs-core` source, not assumed): `pyobs/
vfs/httpfile.py`'s `HttpFile` backend is a plain HTTP GET
(`urljoin(download_base, filename)`), optional preemptive-safe HTTP Basic
Auth (`aiohttp.BasicAuth`), no `WWW-Authenticate` challenge - it just
401s outright on bad credentials. `VirtualFileSystem.split_root()` splits
a VFS path as `{root}/{rest...}`, leading slash stripped first.

**Design, mirroring `SavedAccountsModel`'s existing keychain-backed list
pattern** (user-confirmed choice over folding this into `CameraView.qml`
or skipping the UI entirely - a real Settings page, since VFS credentials
are sensitive and Polaris had no settings page of any kind before this):

- `config::VfsEndpointsModel` - `QAbstractListModel`, one flat QSettings
  array (now carrying a `bareJid` field per row, unlike
  `SavedAccountsModel`) filtered to `currentJid` for display/row
  bookkeeping (`visibleIndices()` maps model rows to storage indices).
  Password storage/retrieval reuses `SavedAccountsModel`'s exact async
  QtKeychain job shape (`storePassword`/`loadPassword`/
  `clearStoredPassword`, same `kKeychainService = "Polaris"` - safe to
  share since both classes key entries on their own independent random
  `QUuid` ids, not on anything that could collide). `resolveVfsPath()`
  reimplements `split_root` + endpoint lookup, returning
  `{url, endpointId, username, hasStoredPassword}` for a caller to then
  drive `loadPassword()`/`VfsClient::fetchFile()` itself - this class
  does no fetching of its own.
- `comm::VfsClient` - wraps one `QNetworkAccessManager` (already linked
  via `Qt6::Network`, no new dependency). `fetchFile(requestId, url,
  username, password)` sends `Authorization: Basic` preemptively rather
  than reacting to a 401 challenge - simpler, and correct here since
  `HttpFile`'s server side never sends a challenge anyway. No caching, no
  retry - every call is a live GET, matching this project's "the wire
  protocol is the source of truth" stance elsewhere.
- `qml/views/SettingsView.qml` - new page, new "Settings" sidebar entry
  (static pages are now indices 0-4: Status/Shell/Logs/Events/Settings;
  dynamic `WidgetRegistry` pages now start at index 5, not 4 - every
  `stack.currentIndex` arithmetic in `MainWindow.qml` shifted
  accordingly). List-left/details-right, same idiom as
  `LoginWindow.qml`'s account manager. Its "Test connection" button
  fetches the endpoint's bare `baseUrl` (not a real VFS file - there's no
  filename to test against outside of a real `grab_data()` call) purely
  to prove reachability/auth wiring; any HTTP response (even a 404)
  distinguishes "the server answered" from "connection refused/timed
  out".
- `VfsEndpointsModel`/`VfsClient` are instantiated once in `Main.qml`
  (`VfsEndpointsModel.currentJid: xmppClient.jid` - already bare,
  `LoginWindow.qml`'s `jidField` has no separate resource input) and
  passed down through `MainWindow.qml`, same top-level-wiring pattern as
  `XmppClient`/`AppSettings`/`SavedAccountsModel`.

**Testing**: `tests/config/tst_vfsendpointsmodel.cpp` mirrors
`tst_savedaccountsmodel.cpp`'s shape exactly, including the same
real-keychain-backend/CI-skip idiom for the two keychain round-trip
tests, plus `currentJid`-filtering and `resolveVfsPath` split/join cases.
`tests/comm/tst_vfsclient.cpp` is new in kind for this project - a
hand-rolled `QTcpServer`-based local HTTP stub (success body, preemptive
Basic Auth header capture, 404, connection-refused) rather than mocking
`QNetworkAccessManager`, matching this project's "verify against the
real thing" bar in miniature for a component too fast/local to need a
whole ejabberd+fixture round trip just to unit-test HTTP parsing.

**Live verification** (`fixtures/httpfilecache.yaml` is new - pairs with
`fixtures/camera.yaml`, which gained a `vfs:` block pointing its `cache`
root at it, plus a `location:` block): confirmed the *entire* chain for
real, not just the new C++ code in isolation. `pyobs
fixtures/httpfilecache.yaml` + `pyobs fixtures/camera.yaml` running
against the dev ejabberd server, `grab_data()` invoked via a throwaway
Python `XmppComm` proxy script (mirrors driving it from `CameraView.qml`'s
existing "Expose" button, without needing GUI automation - see below)
returned `/cache/pyobs-20260710-0001-e00.fits.gz`. A hand-compiled
headless harness (this project's documented technique - `moc` run
manually, linked directly against the built `VfsEndpointsModel.cpp`/
`VfsClient.cpp` plus the vendored `libqt6keychain.so`/`qtkeychain`
FetchContent headers under `build/Release/_deps/`) then called
`resolveVfsPath()` on that exact filename and `fetchFile()` on the
result: **532800 bytes, sha256
`21e48d5038a5a54c67c11ee0427e90f595ae6b2607c810ed7b958db7d57bd1ae`**,
byte-for-byte identical to a plain `curl` of the same URL used as an
independent reference. Two real gaps, both by necessity rather than
oversight:
- `pyobs.modules.utils.HttpFileCache` (confirmed via source) takes no
  `username`/`password` constructor args at all and enforces no auth -
  there's no live pyobs module anywhere to test `VfsClient`'s
  preemptive-Basic-Auth path against, so that path is stub-server-tested
  only (`tst_vfsclient.cpp`), same class of gap as `ICamera`'s
  `IAbortable`/`IFilters` schema-verified-only caveats.
- No GUI click-through of the new Settings page itself - same
  no-`xdotool`/`wmctrl`-available limitation noted in `ICamera`'s and the
  `ITelescope` follow-up's own write-ups. The wire-level harness (`specs/steering/environment-setup.md`)
  (byte-identical fetch of a real, live-produced file) is a stronger
  correctness signal than a visual click-through would have been for
  this particular feature (data correctness, not layout), so this is a
  real but narrow gap, not a substitute for verification that matters
  here.

**Fixture-writing gotcha, worth remembering**: `BaseCamera`'s default
`filenames` pattern is `/cache/pyobs-{...}.fits.gz`, but
`VirtualFileSystem`'s own built-in default roots are only `pyobs`/
`robotic` (both `LocalFile`) - `cache` isn't one of them. Without an
explicit `vfs:` block, `grab_data()` fails outright with "Could not find
root cache for file", not a silent fallback to some default location.
Separately, `grab_data()` also unconditionally needs a `location:` block
- `FitsHeaderMixin`'s `DAY-OBS` header computation calls
`night_obs(self._observer)`, and `_observer` is `None` without one
(`AttributeError: 'NoneType' object has no attribute 'sun_set_time'`,
confirmed live) - neither gap is specific to VFS, but both blocked this
verification pass until fixed, and would block any future
`grab_data()`-touching work against this fixture the same way.

