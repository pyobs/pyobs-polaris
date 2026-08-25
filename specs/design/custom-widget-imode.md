# Custom widget: `IMode`

Status: implemented, closed.

Ported from pyobs-gui's `modewidget.py` - `qml/views/ModeView.qml`, gated
in the sidebar the same way as the other custom widgets
(`hasModeModule`). One row per mode "group" a module exposes: a
`ComboBox` of that group's static options, showing/setting the live
current mode. Live-verified against a real `DummyMode`
(`fixtures/mode.yaml`): all three groups render with the right options,
picking a new mode round-trips over the wire and genuinely cycles
`IMotion` `slewing` -> `positioned` (DummyMode's 3s delay), and the combo
boxes disable/enable correctly around that transition.

**This item's own TODO.md note was briefly wrong, then got corrected
twice in-flight - worth recording since it's a good example of this
project's "verify against source, not memory" discipline catching a real
mistake**: an earlier pass claimed `IMode.set_mode`'s `group` param had
already changed upstream (`pyobs-core`) from a positional index to the
group name itself. Re-checking directly against `pyobs-core` source
before starting implementation found this false - `group` was still
`int`. The item was paused; the user then made that exact change upstream
themselves (`pyobs-core@3a0a70c3`), confirmed again from source once
landed, and only then did `ModeView.qml`/`ModeGroupsRole` get built
against the (now genuinely real) `group: str` shape. New role
`ModuleListModel::ModeGroupsRole` decodes `IMode` capabilities'
`modes: dict[str, list[str]]` field into a `QVariantList` of
`{"group":..., "modes":[...]}` entries - confirmed against the real
disco#info XML (nested `<dict>`-of-`<items>` under the `<capabilities>`
dataclass root) before trusting the `WireDict`/`WireList` decode
assumption. `set_mode(mode, group)` needed no new C++ at all - the
existing real-parameter `executeMethod(jid, name, QVariantList, callback)`
overload (built for `IAutoFocus`) handles two string params exactly like
any other type, confirmed live (not just from reading
`VariantBridge::fromQVariant`) via a throwaway headless harness driving
`comm::XmppClient` directly (same technique as Phase 1/4/7 - `xdotool`/
`wmctrl` still aren't installed here, so this remains the way to verify
C++/wire behavior without GUI input automation).

**Two unrelated things found and fixed/worked around along the way, not
this item's own bugs**:
- The dev ejabberd server's `mode`/`autofocus` (and likely other) fixture
  accounts had their passwords out of sync with what `fixtures/*.yaml`
  assume (`pyobs`) - fixed via `ejabberdctl change_password`, not a
  `pyobs-polaris` or `pyobs-core` bug, just dev-environment drift. Worth
  checking again if a fresh fixture run ever gets "Invalid username or
  password" for an account that's already in `registered_users`.
- `pyobs.modules.utils.DummyMode` isn't re-exported from that package's
  `__init__.py` in `pyobs-core` (every other `Dummy*` module used by this
  project's fixtures is) - `fixtures/mode.yaml` uses the full submodule
  path (`pyobs.modules.utils.dummymode.DummyMode`) as a workaround, which
  works fine since Python's import machinery binds the submodule onto its
  parent package as a side effect regardless of the `__init__.py` export.
  Worth an upstream `__init__.py` fix at some point; not blocking.

**Found, not fixed, out of scope for this item**: the live-verification
harness (`specs/steering/environment-setup.md`) segfaulted on shutdown (after all meaningful output had
already been produced) when its `StateSubscription`s were parented
directly to the `XmppClient` they came from and both were torn down
together. `StateSubscription::~StateSubscription()` calls
`unsubscribe()`, which dereferences `m_manager` - a raw pointer into
`XmppClient`'s own `m_client` member (`StateSubscriptionManager`, a
`QXmppClient` extension). If `XmppClient`'s own destructor runs (tearing
down `m_client` and its extensions as ordinary member destruction) before
the QObject base destructor gets to destroy `XmppClient`'s remaining
children (`~QObject()` runs after the derived class's own member
destructors), any subscription still parented directly to `XmppClient`
itself dereferences an already-destroyed manager. Every widget in this
project always parents its subscriptions to a QML delegate item instead
(shorter-lived than `xmppClient`, e.g. `roofDelegate`/`modeDelegate`), so
this specific ordering may not be reachable from the real app today - but
it's a real latent bug in shared `StateSubscription`/`XmppClient`
infrastructure (neither touched by this `IMode` change) worth its own
look, not something to fix as a drive-by here.

