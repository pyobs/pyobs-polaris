# `CameraView.qml` image controls, round 2: pyobs-gui-matching cuts, tone curve, colormap, trimsec

Status: implemented, closed.

**Direct follow-up request**, immediately after the previous entry's
screenshot-blocked report: "how do I enter percentile? make it the same
as in pyobs-gui please. and also add tone-curve stretch, colormap and
trimsec." Two things going on here worth separating - a real gap in the
prior pass (no way to actually pick a percentage, `FitsImageItem` only
ever used a hardcoded 99.5 default), and the three pieces of
`fitswidget.ui` explicitly deferred in that same prior pass's own
TODO.md entry.

**Cuts presets redesigned to match `comboCuts` exactly**, dropping the
separate "Min/Max" mode from round 1 entirely: `qfitswidget`'s own
`comboCuts` model is `["100.0%", "99.9%", "99.0%", "95.0%", "Custom"]` -
no "Min/Max" entry, because percentile=100 *is* the literal min/max
(`clipFraction` becomes 0, `computeStretch()`'s percentile branch reduces
to exactly the old MinMax branch's arithmetic). Rather than keep a
redundant third mode, `StretchMode::MinMax` was deleted outright and
`FitsImageItem` gained `setPercentilePreset(double)` (switches to
percentile mode with an exact percentage) and `enterCustomMode()`
(switches to custom *without* changing the current limits - the "just
clicked Custom in the combo, haven't touched Lo/Hi yet" case, split out
from `setManualLimits()` which does both at once). `computeStretch()`'s
default percentile also moved from 99.5 to 99.9, matching `comboCuts`'
own default selection.

**Tone curve, colormap, trimsec** - the three pieces round 1's own
TODO.md entry listed as needing "new rendering infrastructure, not just
control-wiring": added a `ToneCurve` enum (linear/log/sqrt/squared/
asinh) applied to the black/white-normalized `[0,1]` value rather than
the raw pixel value the way `qfitswidget`'s `FuncNorm` operates on it -
same qualitative compression shape, but sidesteps `FuncNorm`'s masked-
array handling for non-positive raw pixel values (sqrt/log of a value in
`[0,1]` is always well-defined, no edge case to handle at all). A
`Colormap` enum (Gray/Viridis/Hot/Cool/Jet) with hand-rolled
piecewise-linear control-point interpolation - a deliberately small
curated set, not an attempt at matplotlib's ~150-map `comboColormap`
library (vendoring a colormap library for that would be real dependency
weight for no functional gain over a practical subset an astronomer
would actually reach for). `renderGrayscale()` was renamed `render()`
and now always returns `Format_RGB32` (not `Format_Grayscale8`) so
colormap output has somewhere to put non-gray channels - no back-compat
shim kept for the old name/format, existing callers (`FitsImageItem`,
all of `tst_fitsstretch.cpp`) were updated directly instead, per this
project's own "don't keep unused back-compat hacks" convention. A new
`applyTrimSec()` parses the header's `TRIMSEC` keyword ("[x0:x1,y0:y1]",
FITS 1-based inclusive) and zeroes pixels outside it - not a crop
(`FitsImageItem`'s width/height/every downstream assumption about pixel
count stays put), matching `qfitswidget`'s own `_trimsec()` exactly.

**A real bug, caught by a failing unit test before it ever reached a
live check**: the first version of `applyTrimSec()` alone wasn't enough
- `computeStretch()` still happily counted the newly-zeroed border
pixels as real data, pulling the black level down to 0 on every single
trimmed image regardless of what the actual trimmed region contained.
Re-reading `qfitswidget.py`'s `_trim_image()` explained why this isn't a
problem there: `self.trimmed_data[self.trimmed_data > 0]` filters out
*all* non-positive pixels before ever computing cuts, not just as a
trimsec side effect. Matched that filter in `computeStretch()` directly
(excludes both non-finite *and* non-positive values now) - the tradeoff
this implies for legitimately non-positive science pixels (e.g. noise
dipping below zero in a background-subtracted frame) is `qfitswidget`'s
own design choice, kept for parity rather than "improved on", since the
whole point of this request was to match pyobs-gui's actual behavior,
quirks included. Also had to fix `applyTrimSec()` itself to strip
surrounding single quotes before parsing - `FitsImage::headerValue()`
hands back the *raw* on-disk value for a FITS string keyword (still
quoted, e.g. `'[1:512,1:512]'`), not the already-unquoted form a first
guess at the test data assumed.

**Two more real bugs, both QML, both caught only by an actual
screenshot** (not by the build or by `ctest` - the whole reason this
project's bar is "verified live", see the very top of this file):
1. A newly-added `cutsComboIndexFor()` helper function was accidentally
   declared inside the wrong `ColumnLayout` (the image column's own
   anonymous, `id`-less one) instead of on `cameraDelegate`, but called
   as `cameraDelegate.cutsComboIndexFor(...)` from the combo's
   `currentIndex` binding. QML doesn't error loudly on this the way a
   compiled language would - the binding just throws a caught-and-
   logged `TypeError` ("Property 'cutsComboIndexFor' ... is not a
   function") to the console (invisible unless you're watching stdout)
   and silently leaves `currentIndex` at its pre-binding default of 0,
   which happened to *look* like a plausible value (the combo showed
   "100.0%" instead of the real default "99.9%") rather than an obvious
   blank/broken state. Fixed by moving the function to `cameraDelegate`
   properly, alongside its sibling `suggestedSaveFileName()`.
2. `ComboBox.indexOfValue()` - used for the new `Stretch:`/`Colormap:`
   combos' `currentIndex` bindings, the same idiom `stretchCombo` (now
   `cutsCombo`) used successfully in round 1 - turned out unreliable for
   these particular object-array models (`textRole`/`valueRole`, current
   value read from a forward-referenced `fitsImageItem` property):
   `currentIndex` silently stayed at `-1` (blank combo, no visible
   selection at all), again with no QML warning printed anywhere. Rather
   than debug `indexOfValue()`'s own internals further, replaced both
   call sites with the same hand-written linear-search idiom
   `cutsComboIndexFor()` already used (factored into a small
   `indexOfStringValue(values, value)` helper) - proven to work
   correctly, and one fewer built-in method to trust blindly next time a
   similar combo gets added.

**Live verification**: full `ctest` pass (18/18, up from round 1's 18 -
`tst_fitsstretch`/`tst_fitsimageitem` both grew substantially: new cases
for percentile=100≡min/max, non-positive-value filtering, each tone
curve's brightness direction, reversed-colormap inversion, two
colormaps' exact endpoint RGB values, `applyTrimSec()`'s rectangle math
and quoted/malformed-header handling, and `FitsImageItem`'s own
`trimSecEnabled` end-to-end integration) confirmed before every live
attempt, exactly the discipline that caught bug 1 above via a failing
`trimSecDefaultsToEnabledAndAffectsLevels` assertion before it ever
reached a screenshot. The session's screen (locked at the end of the
prior entry) was unlocked by the time this pass started
(`qdbus6 org.freedesktop.ScreenSaver GetActive` → `false`), so this
pass *did* get real screenshots - `Cuts:`/`Stretch:`/`Colormap:` all
showing their correct live default values (`99.9%`/`Linear`/`Gray`),
and a full round-trip `Expose` → real rendered grayscale noise image at
the default settings, all via a real `grab_data()` RPC through the same
AT-SPI-driven flow documented above. One AT-SPI-specific gotcha hit
along the way: **every module's `CameraView.qml` delegate exists in the
accessibility tree simultaneously** (the same "eagerly instantiated,
`Repeater`-over-all-modules" shape every custom widget here uses, per
`CLAUDE.md`), so a name-only button search for "Expose" matched *eight*
buttons, one per module, only one of which was actually
`ATSPI_STATE_SHOWING` - the first attempt fired `grab_data` at
`autofocus@localhost` (a real RPC, real "Unknown command" error logged,
no lasting harm) before switching the click helper to filter on that
state. Interactively selecting a value from an *open* `ComboBox` popup
was not attempted via AT-SPI - `ComboBox` only exposes a `SetFocus`
action, nothing to open/select a popup item with, and this session
already has one documented case of synthetic-keyboard input causing an
unintended side effect (see the entry above) - judged not worth
revisiting for marginal extra confidence when the exact same
`onActivated: ... = currentValue` idiom is already proven live-working
elsewhere on this same page, and every individual behavior it drives is
covered by the unit tests above instead.

