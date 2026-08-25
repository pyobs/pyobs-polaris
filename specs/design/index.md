# Design docs

Living architecture/design docs, one per feature or subsystem. Kept around after landing
(`status: implemented`), not deleted.

- [phase-0-project-bootstrap.md](phase-0-project-bootstrap.md) — project bootstrap (Qt6/CMake
  skeleton, qxmpp vendored via FetchContent). *implemented, closed*
- [phase-1-xmpp-connection-walking-skeleton.md](phase-1-xmpp-connection-walking-skeleton.md) —
  XMPP connection walking skeleton. *implemented, closed*
- [phase-1-5-value-xml-codec.md](phase-1-5-value-xml-codec.md) — value/XML codec (schema-less
  decode). *implemented, closed*
- [phase-2-disco-info-discovery.md](phase-2-disco-info-discovery.md) — disco#info discovery.
  *implemented, closed*
- [phase-3-presence-driven-module-list.md](phase-3-presence-driven-module-list.md) —
  presence-driven module list. *implemented, closed*
- [phase-4-generic-state-subscription-and-rendering.md](phase-4-generic-state-subscription-and-rendering.md)
  — generic state subscription + rendering. *implemented, closed*
- [phase-5-rpc-execution.md](phase-5-rpc-execution.md) — RPC execution. *implemented, closed*
- [phase-6-events.md](phase-6-events.md) — events. *implemented, closed*
- [phase-7-custom-widget-iroof.md](phase-7-custom-widget-iroof.md) — first custom widget:
  `IRoof`. *implemented, closed*
- [phase-7-5-app-shell-login-and-sidebar-navigation.md](phase-7-5-app-shell-login-and-sidebar-navigation.md)
  — app shell: login window + sidebar navigation. *implemented, closed*
- [configuration-file-and-saved-accounts.md](configuration-file-and-saved-accounts.md) —
  configuration file + saved accounts. *implemented, closed*
- [status-page.md](status-page.md) — status page. *implemented, closed*
- [dashboard-and-roofwidget-removed.md](dashboard-and-roofwidget-removed.md) — Dashboard and
  `RoofWidget` removed. *implemented, closed*
- [roof-state-display-bug.md](roof-state-display-bug.md) — `Array.isArray()` unreliable across
  the C++/QML boundary for roof state display. *implemented, closed*
- [persistent-log-footer.md](persistent-log-footer.md) — persistent log footer. *implemented,
  closed*
- [custom-widget-iautofocus.md](custom-widget-iautofocus.md) — custom widget: `IAutoFocus`.
  *implemented, closed*
- [custom-widget-iacquisition.md](custom-widget-iacquisition.md) — custom widget:
  `IAcquisition`. *implemented, closed*
- [custom-widget-iautoguiding.md](custom-widget-iautoguiding.md) — custom widget:
  `IAutoGuiding`. *implemented, closed*
- [custom-widget-imode.md](custom-widget-imode.md) — custom widget: `IMode`. *implemented,
  closed*
- [logs-page-real-filtering.md](logs-page-real-filtering.md) — real filtering on the Logs page.
  *implemented, closed*
- [events-page-all-incoming-events.md](events-page-all-incoming-events.md) — new page: all
  incoming events. *implemented, closed*
- [resizable-sidebar.md](resizable-sidebar.md) — resizable sidebar. *implemented, closed*
- [shell-rewrite-parameterized-command-execution.md](shell-rewrite-parameterized-command-execution.md)
  — Shell rewrite: real parameterized command execution. *implemented, closed*
- [plugin-mechanism-step-1-internal-widget-registry.md](plugin-mechanism-step-1-internal-widget-registry.md)
  — plugin mechanism, step 1: internal widget registry. *implemented, closed*
- [plugin-mechanism-step-2-external-qml-plugin-loading.md](plugin-mechanism-step-2-external-qml-plugin-loading.md)
  — plugin mechanism, step 2: external QML plugin loading. *implemented, closed*
- [custom-widget-iweather.md](custom-widget-iweather.md) — custom widget: `IWeather`.
  *implemented, closed*
- [custom-widget-itelescope-mvp.md](custom-widget-itelescope-mvp.md) — custom widget:
  `ITelescope` (MVP). *implemented, closed*
- [custom-widget-icamera-mvp.md](custom-widget-icamera-mvp.md) — custom widget: `ICamera` (MVP —
  exposure control, no image display). *implemented, closed*
- [itelescope-follow-up-libnova-destination-coordinate-preview.md](itelescope-follow-up-libnova-destination-coordinate-preview.md)
  — `ITelescope` follow-up: libnova + destination-coordinate preview. *implemented, closed*
- [vfs-transport.md](vfs-transport.md) — VFS transport (`config::VfsEndpointsModel` +
  `comm::VfsClient`). *implemented, closed*
- [fits-decode.md](fits-decode.md) — FITS decode (`fits::FitsImage`, first real Conan
  dependency). *implemented, closed*
- [image-display-widget.md](image-display-widget.md) — image display widget
  (`fits::FitsImageItem`). *implemented, closed*
- [cameraview-layout-pass-material-to-fusion.md](cameraview-layout-pass-material-to-fusion.md) —
  `CameraView.qml` layout pass + global style switch (Material → Fusion). *implemented, closed*
- [cameraview-image-controls-follow-up-auto-save-custom-cuts.md](cameraview-image-controls-follow-up-auto-save-custom-cuts.md)
  — `CameraView.qml` image controls follow-up: auto-save, custom cuts. *implemented, closed*
- [cameraview-image-controls-round-2.md](cameraview-image-controls-round-2.md) —
  `CameraView.qml` image controls, round 2: pyobs-gui-matching cuts, tone curve, colormap,
  trimsec. *implemented, closed*
- [settingsview-test-connection-switched-to-ping.md](settingsview-test-connection-switched-to-ping.md)
  — `SettingsView.qml` "Test connection" switched to `/ping`. *implemented, closed*
- [current-account-and-sign-out-in-header.md](current-account-and-sign-out-in-header.md) —
  current account + "Sign out" moved into a `header: ToolBar`. *implemented, closed*
- [sidebar-nav-scrollable.md](sidebar-nav-scrollable.md) — sidebar nav made scrollable, not just
  clipped. *implemented, closed*
- [sidebar-scroll-indicator-bug.md](sidebar-scroll-indicator-bug.md) — Fusion's `ScrollBar`
  wasn't rendering at all. *implemented, closed*
- [status-page-expandable-per-module-drilldown.md](status-page-expandable-per-module-drilldown.md)
  — Status page: expandable per-module drill-down. *implemented, closed*
- [keyvaluecard-follow-up-color-coded-nested-values.md](keyvaluecard-follow-up-color-coded-nested-values.md)
  — `KeyValueCard.qml` follow-up: color-coded nested values, ported from `statuswidget.py`.
  *implemented, closed*
- [status-page-follow-up-one-line-per-state-and-capabilities.md](status-page-follow-up-one-line-per-state-and-capabilities.md)
  — Status page follow-up: one-line-per-State/Capabilities, matching `statuswidget.py` exactly.
  *implemented, closed*
- [cameraview-follow-up-itemperatures-widget.md](cameraview-follow-up-itemperatures-widget.md) —
  `CameraView.qml` follow-up: `ITemperatures` widget, `PlotItem` multi-series support.
  *implemented, closed*
- [cameraview-follow-up-per-sensor-checkboxes.md](cameraview-follow-up-per-sensor-checkboxes.md)
  — `CameraView.qml` follow-up: per-sensor checkboxes for the temperatures plot. *implemented,
  closed*
- [cameraview-follow-up-time-range-filter.md](cameraview-follow-up-time-range-filter.md) —
  `CameraView.qml` follow-up: time-range filter for the temperatures plot. *implemented, closed*
- [ifilters-ifocuser-shared-panels.md](ifilters-ifocuser-shared-panels.md) —
  `IFilters`/`IFocuser` on both Camera and Telescope, shared `TemperaturesPanel`/
  `FiltersPanel`/`FocuserPanel`. *implemented, closed*
- [sidebarpanelregistry-generalizing-camera-telescope-sidebar.md](sidebarpanelregistry-generalizing-camera-telescope-sidebar.md)
  — `SidebarPanelRegistry.qml`: generalizing Camera's/Telescope's sidebar. *implemented, closed*
- [sidebarpanelregistry-follow-up-two-layout-bugs.md](sidebarpanelregistry-follow-up-two-layout-bugs.md)
  — `SidebarPanelRegistry.qml` layout follow-up: two bugs from one root cause, including the
  `CoolingPanel` width bug. *implemented, closed*
- [sidebarcolumn-resizable-collapsible-sidebar.md](sidebarcolumn-resizable-collapsible-sidebar.md)
  — `SidebarColumn.qml`: resizable, collapsible, shared-width sidebar. *implemented, closed*
- [sexagesimal-radec-parsing.md](sexagesimal-radec-parsing.md) — sexagesimal RA/Dec parsing for
  `TelescopeView.qml`'s Move fields. *implemented, closed*
- [simbad-name-resolution.md](simbad-name-resolution.md) — SIMBAD name resolution for
  `TelescopeView.qml`'s Move fields. *implemented, closed*
- [jpl-horizons-ephemeris-lookup.md](jpl-horizons-ephemeris-lookup.md) — JPL Horizons ephemeris
  lookup for `TelescopeView.qml`'s Move fields. *implemented, closed*
- [observer-location-from-module.md](observer-location-from-module.md) — observer location now
  comes from the module itself (`ModuleLocation`, pyobs-core 2.0.0.dev18+). *implemented, closed*
- [compass-widget.md](compass-widget.md) — compass widget for `TelescopeView.qml`'s Move fields.
  *implemented, closed*
- [acl-permitted-methods-gating.md](acl-permitted-methods-gating.md) — ACL / permitted-methods
  gating, project-wide. *implemented, closed*
