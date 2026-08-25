# Custom widget: `IWeather`

Status: implemented, closed.

`qml/views/WeatherView.qml`, registered into `WidgetRegistry` the same
one-line way every other built-in widget is (`MainWindow.qml`) - see
TODO.md's "Custom widget: `IWeather`" for the full design rationale.
Simpler than the ported `weatherwidget.py`: `WeatherState` is a plain
dataclass pushed via normal state publication (`good: bool, readings:
list[WeatherSensorReading{sensor, value, unit, time}]`), no RPC polling
needed at all - same subscribe-and-render shape as every other custom
widget. One tile per reading actually present (a `Flow`, not a fixed
11-tile grid), labelled via a client-side map ported from
`AVERAGE_SENSOR_FIELDS` (minus `sunalt` - no equivalent left in the
current `WeatherSensors` enum - plus a new `skymag` entry), with units
read straight off each reading's own wire `unit` field rather than a
second hardcoded map. `WeatherSensorReading` no longer carries a
per-sensor `good` flag (only one overall `WeatherState.good`), so unlike
the old widget's per-tile red/green coloring, this page colors a single
"Weather OK"/"Weather BAD" banner from that one flag instead - there's no
wire data left to color tiles independently.

**The fixture gap TODO.md flagged (no `Dummy*` module implementing
`IWeather`, since the only real implementation is an HTTP client to a
separate `pyobs-weather` service) got resolved upstream rather than
worked around here**: the user added `pyobs.modules.weather.MockWeather`
to `pyobs-core` - a genuinely self-contained simulated station (fixed
default values per sensor, `set_good`/`set_sensor_value` for driving it
in tests). `fixtures/weather.yaml` uses it, same shape as every other
fixture (`{include _comm.yaml}`, `user: weather`/`password: pyobs`) - no
mock HTTP responder needed after all.

Live-verified against a real running `MockWeather`
(`pyobs fixtures/weather.yaml`) with a throwaway headless harness (same
`comm::XmppClient`-direct technique as every other item in this file,
registering two new dev ejabberd accounts, `weather` and
`weatherharness`, for the module and the harness's own login
respectively) - not the QML itself, same limitation as everywhere else in
this file (no input-automation tool in this environment). Confirmed the
decoded `IWeather` state is exactly what `WeatherView.qml` assumes: 10
readings (every non-`TIME` `WeatherSensors` member `MockWeather`
defaults), each `sensor` value one of `WeatherView.qml`'s own
`sensorLabels` map's exact keys (`temp`/`humid`/`press`/`winddir`/
`windspeed`/`rain`/`skytemp`/
`dewpoint`/`particles`/`skymag` - `WeatherSensors` is a `StrEnum`, so the
wire value is the lowercase short form, not the member name), `unit`
already module-supplied text (`celsius`/`percent`/`hpa`/`deg`/`km/h`/
`bool`/`1/m3`/`mag/arcsec2`), and `good` a real bool. The harness's own
teardown then segfaulted - already-known, already out of scope (see this
doc's `IMode` section's own note on `StateSubscription`s parented
directly to `XmppClient`) - after all meaningful output had already
printed, so it didn't block confirming the decode. `set_good`'s RPC
round-trip specifically was *not* verified this way:
`XmppClient::executeMethod`'s real-param overload resolves commands
against disco#info's *interface-declared* commands only, and
`set_good`/`set_sensor_value` are `MockWeather`-only test helpers, not
part of `IWeather`'s own contract - a client-side-only limitation of that
lookup, not a wire bug, and irrelevant to this widget anyway (Start/Stop
controls are explicitly out of scope for this pass, see TODO.md). The
harness source itself wasn't kept, same as every other one-off harness
used throughout this project.

