# `ITelescope` follow-up: libnova + destination-coordinate preview

Status: implemented, closed.

TODO.md's original scope for this item bundled libnova vendoring, a
destination-coordinate preview, and solar-frame pointing
(`IPointingHGS`/`IPointingHelioprojective`). Split during planning after
two blockers turned up that TODO.md hadn't anticipated - see that item's
own new write-up (a separate, explicitly-blocked entry) for the second
one. This section covers what shipped: libnova + the destination preview.

**Observer location has no wire path at all - confirmed by reading
pyobs-core source, not assumed.** The legacy Python `pyobs-gui`'s
`TelescopeWidget` only had access to an `astroplan.Observer` because it
ran *in-process* as a `pyobs.modules.Module` inside the same `MultiModule`
tree as the telescope module - `pyobs.object.Object.__init__`/`get_object`
share `location`/`observer` via plain Python attribute-copying at
construction time (`pyobs/object.py:245-327,476-479`), never serialized to
XMPP. No `ILocation` interface, no capability, nothing in disco#info
exposes it - a separate XMPP client process like this one structurally
cannot fetch it from a connected module. Fixed by adding three new
`AppSettings` properties (`observerLatitude`/`observerLongitude`/
`observerElevation`, `src/config/AppSettings.h`/`.cpp`) - a client-side-
only value the user enters once via `TelescopeView.qml`'s inline "Observer
Location" `TextField`s, not fetched from any module. Unlike
`pluginsDirectory` (deliberately no settings UI, a one-time developer-only
knob - see that property's own doc comment), this got real UI: it's a
genuinely interactive end-user feature. `AppSettings::hasObserverLocation()`
(`QSettings::contains()`-based, not a NaN sentinel - a double `NaN`'s
round-trip through `QSettings`' on-disk ini serialization isn't guaranteed
reliable across platforms/Qt versions) is how the preview knows "never set"
from "set to (0,0)".

**libnova vendoring.** Vendors the genuine upstream project (hosted on
SourceForge, git-accessible via `git.code.sf.net/p/libnova/libnova`),
pinned to its real tagged release `v0.16` (confirmed via `git ls-remote
--tags` - it does cut real releases, unlike some GitHub mirrors/forks of
it) via `FetchContent` in `cmake/Dependencies.cmake`, same treatment as
qxmpp/QtKeychain. (A CMake-ified third-party fork was evaluated first and
briefly vendored, but replaced with genuine upstream on request - nothing
about that fork's own algorithmic content was ever in question, but
depending on upstream directly is preferable when upstream can be made to
work at all.)

Upstream `v0.16` does ship a `CMakeLists.txt`, but it's old
(`cmake_minimum_required(VERSION 2.6)`, predates any option to disable its
own `lntest`/`examples` subdirectories) and needed several small, purely
mechanical build-system fixes - **none of them touch libnova's own
source/build files**, everything is additive configuration on this
project's own `FetchContent` block:

- `SOURCE_SUBDIR src` points `FetchContent` straight at
  `src/CMakeLists.txt`, skipping the top-level file entirely - its
  unconditional `add_subdirectory(lntest)` defines an executable target
  literally named `test`, which collides with CTest's reserved `test`
  target name once this project's own `enable_testing()` is active (a
  real configure error, confirmed by hitting it, not a hypothetical).
- Skipping the top-level file means its `project(libnova)` call (which
  would have implicitly enabled the C language) and its
  `include_directories(${libnova_SOURCE_DIR}/src)` (needed for libnova's
  own `.c` files to find their own `<libnova/foo.h>` headers) are both
  skipped too - replaced with an explicit `enable_language(C)` and a
  `target_include_directories(libnova PUBLIC ${libnova_SOURCE_DIR}/src)`
  call (`PUBLIC` so this project's own targets that link against
  `libnova` inherit the same include path automatically).
- `LIBRARY_NAME`/`BUILD_SHARED_LIBS` are variables `src/CMakeLists.txt`
  normally expects its (now-skipped) parent to have already set - set
  explicitly instead (`libnova`/`ON`).
- `julian_day.c` guards its own fallback `round()` implementation behind
  `#ifndef HAVE_ROUND` - a macro normally supplied by the `autoconf`
  `configure` script this CMake-only build never runs, so the fallback
  always compiled in and collided with glibc's real `round()` ("static
  declaration of 'round' follows non-static declaration"). `round()` is a
  real C99 function present on every platform this project targets -
  defining `HAVE_ROUND` via `target_compile_definitions(libnova PRIVATE
  HAVE_ROUND)` is the correct fix, not a workaround for something
  actually missing.
- **Missed on first pass, only surfaced on CI's clean build**:
  `julian_day.c` also has its own unconditional `#include "config.h"` -
  same root cause as `HAVE_ROUND` above (the skipped autotools
  `configure` step normally `autoheader`-generates it), but this one
  is a hard "no such file" compile error rather than a silent runtime
  bug, so it should have been the more obvious of the two - it wasn't
  caught locally because a stale `_deps/libnova-build` from before this
  file existed stuck around instead of a real clean-tree build. Fixed by
  writing an empty `config.h` into the build tree and adding it to
  `libnova`'s own (`PRIVATE`) include path - **do not** `configure_file()`
  libnova's real `config.h.in`: it `#undef`s `HAVE_ROUND`, which would
  silently cancel the `target_compile_definitions()` fix above (the two
  aren't independent - config.h's own `#undef` wins over an earlier `-D`
  compile definition, so whichever fix touches config.h has to know about
  the other one). No other compiled source includes config.h, so an empty
  file is sufficient.
- `v0.16`'s own `cmake_minimum_required(VERSION 2.6)` is a hard configure
  error on modern CMake ("Compatibility with CMake < 3.5 has been
  removed") - fixed via `CMAKE_POLICY_VERSION_MINIMUM`, CMake's own
  documented escape hatch for vendoring old projects, scoped to only this
  one `FetchContent_MakeAvailable` call (not set globally).
- `ln_types.h` requires exactly one of `LIBNOVA_SHARED`/`LIBNOVA_STATIC`
  to be defined, but (since the top-level file that would normally set
  this for consumers is skipped) this project's own `polaris` and
  `tst_coordinatetransform` targets need
  `target_compile_definitions(... PRIVATE LIBNOVA_SHARED)` added
  explicitly (`CMakeLists.txt`/`tests/CMakeLists.txt`).

Target name is `libnova` (its own `set(LIBRARY_NAME libnova)`), not `nova`
like the fork used - anyone updating from an older checkout that still
references `nova` needs to update both `target_link_libraries` call sites.

**New C++**: `src/util/CoordinateTransform.h`/`.cpp` - pure functions
(`coordxform::equatorialToHorizontal`/`horizontalToEquatorial`, no `QObject`,
independently unit-tested, `codec::xmlToValue`'s "plain free function"
precedent rather than `PlotItem`'s QML-facing-class one) plus a thin
`QML_SINGLETON` adapter (`coordxform::CoordinateTransform`) `TelescopeView.qml`
calls directly. **Two real bugs caught, neither assumed - both confirmed
against libnova's own source and cross-checked against astropy, then fixed
before shipping:**
- **Azimuth convention.** `libnova/ln_types.h`'s own doc comment on
  `ln_hrz_posn.az`: "0 deg = South, 90 deg = West, 180 deg = Nord, 270 deg
  = East" - South-based, exactly 180° rotated from this project's own
  North-based convention everywhere else (`IPointingAltAz`'s `AltAzState.az`).
  Fixed with `az = fmod(az + 180.0, 360.0)` at the `coordxform` boundary,
  so nothing downstream ever sees libnova's convention.
- **Precession.** `ln_get_hrz_from_equ` expects mean-*of-date* equatorial
  coordinates, not J2000 - `precession.c`'s own doc comment on
  `ln_get_equ_prec`: "Uses mean equatorial coordinates and is only for
  initial epoch J2000.0". This project's RA/Dec convention everywhere else
  (`IPointingRaDec`'s `RaDecState`, what a user types into
  `TelescopeView.qml`, matching pyobs-core's own `BaseTelescope.move_radec`
  - `SkyCoord(..., frame=ICRS)`) is J2000/ICRS. Missing this precession
  step produced a systematic ~0.2-0.4° error against astropy's reference
  values in the unit test - suspiciously close to the ~24.5 years of
  precession (~50″/year) between J2000 and the test dates used, which is
  what led to finding it. Fixed by precessing J2000→date before
  `ln_get_hrz_from_equ` (`ln_get_equ_prec`) and date→J2000 after
  `ln_get_equ_from_hrz` (`ln_get_equ_prec2`).
- **Elevation is accepted but genuinely unused** - `ln_get_hrz_from_equ`/
  `ln_get_equ_from_hrz` take no elevation parameter at all (unlike
  astropy's `EarthLocation`-based transform, which does account for
  observer height). Still stored/passed through for forward compatibility
  with what the user actually enters, not silently dropped from the API,
  but has zero effect on the computed result - noted explicitly in
  `CoordinateTransform.cpp` so it isn't mistaken for an oversight.

No atmospheric refraction correction is applied, matching pyobs-core's own
server-side behavior exactly (confirmed via source: `astroplan.Observer` is
constructed by `pyobs.object.Object` without `pressure`/`temperature`, so
`pressure` defaults to zero/no atmosphere) - the preview would otherwise
systematically disagree with what `move_radec`'s own server-side
`min_altitude` check actually computes.

**Correctness verification methodology** (this feature has no wire/RPC
component at all - "live-verify against a real pyobs module" doesn't apply
the same way it did for every prior widget): cross-checked
`coordxform::equatorialToHorizontal`/`horizontalToEquatorial` against
`astropy`'s `SkyCoord.transform_to(AltAz(..., pressure=0))` for three fixed
(RA, Dec, lat, lon, elevation, JD) tuples, computed via the already-
available `pyobs-core/.venv` astropy install, `tests/util/
tst_coordinatetransform.cpp`, tolerance `0.05°` (libnova and astropy use
different underlying reduction algorithms - not bit-identical, but far
tighter than a "preview before committing to Move" UI needs). All three
cases passed cleanly once precession was added; a fourth test
(`azimuthIsNorthBasedNotLibnovaSouthBased`) pins the convention-fix
direction explicitly so a regression back to the raw libnova value (an
exact 180° error) can't slip through unnoticed even if some future test
tolerance were loosened.

**A second, live-GUI-caught bug, distinct from the two libnova ones
above**: the destination-preview `Label`'s binding originally called
`AppSettings::hasObserverLocation()` (a `Q_INVOKABLE`, not a property) as
its very first check, returning early ("Set observer location above to
preview") when unset. Since a `Q_INVOKABLE` call creates no QML binding
dependency by itself, and the binding's first-ever evaluation happened
while location actually was still unset, the early return meant
`observerLatitude`/`observerLongitude` were *never* read as properties
during that evaluation - so no reactive dependency on them was ever
established, and the preview silently never updated even after a real
location was entered. Caught live: launched the app, watched the user
(interacting with the running window directly, not through screenshot-only
verification) type an observer location into the fields, and the preview
stayed stuck on the placeholder text instead of showing computed values.
Fixed by reading `observerLatitude`/`observerLongitude`/`observerElevation`
unconditionally at the top of the binding, before any early return, so the
dependency is always established regardless of which branch executes.

**GUI verification note**: restarting the app to pick up the above fix
logged out the session, landing back at the login screen (pre-filled
saved credentials, just needs "Connect" clicked) - same
no-`xdotool`/`wmctrl`-available limitation as `ICamera`'s own writeup.
Unlike that pass, though, this feature's correctness rests primarily on
the astropy-cross-checked unit tests above (deterministic, quantified),
not on a visual click-through - the live-GUI session (even though not
fully re-verified end-to-end after the final fix) is what caught the
reactivity bug in the first place, which the unit tests alone couldn't
have (it's a QML-binding-specific bug, invisible to pure C++ tests).

