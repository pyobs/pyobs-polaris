pyobs-polaris
##############

**Polaris** is a `pyobs <https://www.pyobs.org>`_ (`documentation <https://docs.pyobs.org>`_)
GUI client for telescope fleets, written in C++/Qt/QML. It has no dependency on ``pyobs-core``
itself — everything is built from XMPP presence and disco#info discovered live over the wire
(`QXmpp <https://github.com/qxmpp-project/qxmpp>`_ in place of Strophe.js).


Example configuration
**********************

There's no module-side YAML config — this is a desktop app a user logs into directly. What you
configure instead:

At runtime, a user logs in with a JID + password against an ejabberd server (credentials
optionally remembered via the OS keychain, ``QtKeychain``-backed). A plugins directory
(``AppSettings::pluginsDirectory``) can point at a folder of external ``*.qml`` widget files —
each exposing exactly one of ``targetInterface``/``targetJid``, plus ``iconGlyph``, ``label``,
``widget`` — auto-loaded at startup; see ``examples/plugins/`` for a worked example.


Available classes
******************

.. toctree::
   :maxdepth: 2

   api/index

Generated from ``src/`` via Doxygen + `doxysphinx <https://github.com/boschglobal/doxysphinx>`_ —
see ``../Doxyfile``. ``qml/`` isn't covered here (Doxygen doesn't parse QML); the ``qml/views/``
screens are documented in "Views" below instead.


Views
*****

One QML view per top-level screen (``qml/views/*.qml``). No screenshots yet — written from
source, not a running instance; add those as a follow-up.

RoofView
========
Drives ``IRoof`` — status readout plus Open/Close/Stop.

ModeView
========
Drives ``IMode``.

WeatherView
===========
Drives ``IWeather``.

AutoFocusView
=============
Drives ``IAutoFocus``.

AutoGuidingView
===============
Drives ``IAutoGuiding``.

AcquisitionView
===============
Drives ``IAcquisition``.

TelescopeView
=============
Drives ``ITelescope`` — Init/Park/Stop, move-to-coordinates (RA/Dec, Alt/Az), a compass widget for
directional offsets, sexagesimal input parsing, and SIMBAD/JPL Horizons name/ephemeris resolution
for the Move fields.

CameraView
==========
Drives ``ICamera`` — exposure control, live ``IExposure`` state, and FITS decode/display
(``fits::FitsImage`` via ``cfitsio``) of the grabbed image, plus shared
``IFilters``/``IFocuser``/``ITemperatures`` sidebar panels.

StatusView
==========
Generic per-module drill-down — every currently-online module's full capability/state, rendered
from its own disco#info schema with no per-interface code (mirrors ``KeyValueCard.vue``'s field
ordering and color-coding for nested values).

EventsView
==========
Every incoming event, not just log lines — a generic feed for anything a module publishes.

LogsView
========
Live, filterable log stream.

ShellView
=========
A generic RPC console: ``module.command(arg1, arg2, ...)`` syntax, parameterized command
execution against any connected module's live command schema.

SettingsView
============
Connection settings — saved accounts (keychain-backed), plugins directory, "Test connection".


Keyboard shortcuts
*******************

None bound globally as of this writing.
