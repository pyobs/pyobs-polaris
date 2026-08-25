# Plugin mechanism, step 2: external QML plugin loading

Status: implemented, closed.

`AppSettings::pluginsDirectory`/`pluginFiles()` + `PluginLoader.qml` -
step 2 of TODO.md's "Plugin mechanism for custom module widgets" item.
`AppSettings` gained a `pluginsDirectory` string setting (empty by
default - "don't scan for anything" - `QSettings`-backed, same as
`lastSelectedAccountId`, with no settings-UI control yet, same "add
settings as needed, don't design a UI speculatively" discipline that
class's own header comment already states) and a `pluginFiles()`
`Q_INVOKABLE` (every `*.qml` file directly inside that directory,
non-recursive, returned as ready-to-use `file://` URL strings - resolving
local-path-to-URL conversion in C++ rather than leaving easy-to-get-wrong
string concatenation to QML). `MainWindow.qml`'s `Component.onCompleted`
calls `PluginLoader.loadAll(appSettings.pluginFiles())` right after
registering the five built-ins, then one final `refreshVisibility()`
covering both.

**Plugin file contract** (also documented at the top of
`PluginLoader.qml` itself, and demonstrated end-to-end by
`examples/plugins/TelescopeQuickView.qml`): a plugin `.qml` file's root
type is a plain `QtObject` exposing `targetInterface` XOR `targetJid`
(which of step 1's two registration kinds this is), `iconGlyph`/`label`
(sidebar text), an optional `exclusive` (jid-registrations only - see
step 1's own note on this), and a `widget` `Component` - the actual UI,
instantiated later via `Loader` exactly like a built-in widget's own
`Component`, and able to close over the plugin root's own `xmppClient`
property the same way `MainWindow.qml`'s `roofComponent` et al. close
over `root.xmppClient`. `PluginLoader` instantiates the root object with
`xmppClient` bound to the app's real `XmppClient` - **a considered
choice, not the only option**: TODO.md's own step 2 bullet asked for "a
defined, stable plugin API surface" and named `jid`/`interfaces`/
subscribe-execute helpers as the kind of thing to pass in, which could
have meant a deliberately narrower, curated context object instead of
handing over the whole `XmppClient`. Went with reusing the exact same
contract every built-in widget already gets instead: it's already proven
stable (nothing about it has changed across any of this project's many
widget-adding phases), asks a plugin author to learn nothing new beyond
what's already documented for built-in widgets, and a narrower API would
itself need ongoing design/maintenance for a need that doesn't concretely
exist yet - revisit only if a real plugin actually needs protecting
*from* something on `XmppClient`, not preemptively.

A malformed/errored plugin file is logged via `console.warn()` and
skipped (`Component.status === Component.Error`, or exactly one of
`targetInterface`/`targetJid` not being set) - one broken third-party
file doesn't take the whole app down. `Qt.createComponent()`'s
`Component.Loading` status is handled defensively (connects to
`statusChanged` and finishes registration once ready) even though local
`file://` components load synchronously in every case actually observed -
`refreshVisibility()`'s single call right after `loadAll()` returns
depends on that synchronous-in-practice timing to give a freshly-loaded
plugin its correct initial sidebar visibility; a plugin that genuinely
loaded asynchronously would still register correctly (the registry's
`entries` array is reassigned reactively either way) but would stay
hidden until the next real module-list change - a known, narrow,
accepted gap, not a bug, given no local file has ever actually exercised
that path.

**Live-verified against a real connected module with no built-in widget
at all** - not synthetic: `examples/plugins/TelescopeQuickView.qml`
targets `ITelescope` (a bare `IMotion` marker interface - see this doc's
own `ITelescope` MVP notes; this repo ships no built-in widget for it),
essentially `RoofView.qml`'s own shape pointed at a different interface.
Verified live (real ejabberd server, the same long-running
`dummy-telescope.yaml` instance used throughout this session,
screenshotted via `spectacle -b -n` with the user clicking through since
no input-automation tool exists in this environment - same limitation
noted throughout this file): pointed `AppSettings::pluginsDirectory` at
`examples/plugins/` via a temporary `Main.qml` edit (reverted after,
including explicitly resetting the now-persisted `QSettings` value back
to empty - `AppSettings` writes to the same real config file the actual
app uses, so the temporary *code* being reverted doesn't undo an
already-*persisted* setting on its own), confirmed a "🔭 Telescope
(plugin)" sidebar entry appeared under MODULES with no console warnings,
and clicking into it showed the real `telescope@localhost` module's real
live `IMotion` state (status `parked`, a real timestamp) with working
Init/Park/Stop buttons - proof the whole path works end to end:
directory scanning, component loading, registration, sidebar/StackLayout
rendering, real `xmppClient` binding, and real state subscription/RPC
dispatch from code that lives entirely outside this repo.

