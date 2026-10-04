# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries for releases before this file existed were generated from commit subjects.

## [2.0.0] - 2026-09-03

- docs: update release-notes feature list to match the actual current app
- Fix CI: macOS release notes heredoc corrupting the release step
- Fix Doxyfile: HTML_OUTPUT must be html/, not the api/ root
- Add Sphinx/Doxygen docs site; split DEVELOPMENT.md into specs/
- Fix stale DummyTelescope class path
- Remove dead name: key from fixture configs
- Add dependabot.yml (github-actions), targeting develop for PRs
- Make the display-settings button toggle its popup closed on a second click
- Anchor Camera page's display-settings popup under its button
- Collapse Camera page's Stretch/Colormap row into a summary + popup
- Make Camera page's image toolbars reflow instead of clipping
- Lay out Telescope page's jog buttons like keyboard arrow keys
- Redesign Telescope page layout: reflow, collapse, merge, decouple sidebar
- Add ACL / permitted-methods gating across every RPC-triggering control
- Add Compass jog widget to Telescope page
- Document GCC 15.2.0 ICE workaround for building cfitsio
- Color-code Telescope page buttons, matching pyobs-gui's semantic scheme
- Add multi-row selection to the log entry copy feature
- Add right-click "Copy" to log entries on the Logs page and log footer
- Use pyobs-core 2.0.0.dev18's ModuleLocation for the Telescope observer location
- Add JPL Horizons ephemeris lookup to the Telescope Move fields
- Add SIMBAD name resolution to the Telescope Move fields
- Add sexagesimal RA/Dec parsing to the Telescope Move fields
- Fix collapsed sidebar toggle not staying pinned to the window edge
- Add resizable, collapsible right-hand sidebar shared across pages
- Fix sidebar panel width/top-margin bugs on Camera and Telescope pages
- Generalize Camera/Telescope sidebars into a panel registry
- Add IFilters/IFocuser widgets to Camera and Telescope pages
- Camera page: ITemperatures widget with a live multi-sensor plot
- Status page: expandable per-module drill-down, pyobs-gui-style coloring
- CI: set CCACHE_SLOPPINESS for Apple clang's direct-mode gap
- CI: pin macos-latest -> macos-14
- Fix CI: copy vendored DLLs into Qt's own prefix before windeployqt
- Fix CI: windeployqt --ignore-library-errors for vendored qt6keychain.dll
- CI: add ccache for this project's own source (not just vendored deps)
- Fix CI: macOS release packaging path - polaris.app, not bin/polaris.app
- CI: scope push trigger to develop + tags, not main
- Add Windows/macOS release artifacts; fix missing liblibnova.so in Linux tarball
- Update DEVELOPMENT.md: Windows/macOS now build+test in CI
- Fix CI: Windows DLL discovery (the "runs forever" hang) + split cache steps
- Fix CI: export libnova's symbols from its Windows DLL
- Fix CI: stop libnova's MSVC PREFIX/IMPORT_PREFIX hack colliding under FetchContent
- Fix CI: define libnova's real BUILD_SHARED_LIBRARY option, not just CMake's BUILD_SHARED_LIBS
- Fix CI: correct Windows/macOS Qt6 version+arch for install-qt-action
- Fix CI: run tst_fitsstretch/tst_fitsimageitem with QT_QPA_PLATFORM=offscreen
- Add Windows/macOS to CI matrix for build+test coverage
- Fix CI: supply an empty config.h for libnova's julian_day.c
- Drop WASM build from the roadmap
- Add QML vs QtWidgets retrospective to DEVELOPMENT.md
- Add a visible indicator that the sidebar nav list is scrollable
- Make sidebar nav scrollable instead of spilling into the log footer
- Move current account and Sign out into a header ToolBar
- Switch VFS "Test connection" to /ping, fix Settings page bugs
- Note that Windows/macOS QtKeychain backends are untested
- Add scripts/screenshot_page.py: reusable AT-SPI live-verification tool
- Add Camera image controls: auto-save, cuts, tone curve, colormap, trimsec
- Make sidebar nav accessible, enabling AT-SPI-driven live GUI testing
- Fix stale StatusView.qml comment referencing deleted DashboardView
- Redesign Roof/AutoFocus/Acquisition/AutoGuiding/Mode layouts
- Redesign TelescopeView.qml layout to match telescopewidget.ui
- CameraView.qml: fetch settings once, apply as a batch on Expose
- Redesign CameraView.qml layout, switch app style Material -> Fusion
- Fix CameraView.qml: NewImageEvent module comparison never matched
- Document CLion/IDE build-profile gotcha in README, fix stale widget list
- Document CLion/ad-hoc build-profile gotcha with the Conan toolchain
- Add image display widget: fits::FitsImageItem, wired into CameraView
- Add FITS decode: fits::FitsImage via cfitsio
- Add VFS transport: config::VfsEndpointsModel + comm::VfsClient
- Add ITelescope follow-up: libnova + destination-coordinate preview
- Add ICamera widget (MVP - exposure control, no image display)
- Fix stale pyobs.gui import in TelescopeView.qml
- Add ITelescope widget (MVP)

## [0.2.0] - 2026-07-09

- Add README
- Rename project to pyobs-polaris (GUI: Polaris)
- Add CLAUDE.md
- Add IWeather widget
- Add external QML plugin loading (plugin mechanism, step 2)
- Add internal widget registry (plugin mechanism, step 1)
- Rewrite Shell as a real command prompt with autocomplete
- Break Shell TODO item into four independently buildable steps
- CI: skip keychain-storing tests under CI, stop chasing real gnome-keyring
- Fix CI: stop busting the FetchContent cache on unrelated CMakeLists.txt edits
- Fix CI: give gcr-prompter a display so keychain collection creation works
- Fix CI: give the keychain test a real Secret Service to talk to
- Add custom widget: IMode
- Update IMode TODO: group:str landed upstream, item unblocked
- Correct IMode TODO: set_mode's group is still an int, not a string
- Update Shell TODO: rule out QCompleter explicitly, use a QML-native popup
- Update IMode TODO: set_mode's group param is now a string upstream
- Replace Shell TODO plan: command-line + autocomplete, not param widgets
- Make the sidebar resizable, like the log footer
- Remove filtering from EventsView.qml, fix Type/Data column overlap
- Add Events page: qml/views/EventsView.qml
- Add real per-module/level filtering to LogsView.qml
- Add TODO items: Events page, IMode widget, IWeather widget
- Add IAutoGuiding widget: AutoGuidingView.qml
- Put Acquisition's two plots side by side; fix margin overlap; arcsec
- Add IAcquisition widget: AcquisitionView.qml, PlotItem extensions
- Add IAutoFocus widget: AutoFocusView.qml, PlotItem, real RPC params
- Add IAutoFocus/IAcquisition/IAutoGuiding TODO item + first live fixture
- Fix RoofView's KeyValueCard stuck on "(no value yet)"
- Add diagnostics + write up the roof state-display bug for handoff
- Fix MainWindow.qml load failure: rename custom icon property
- Add a persistent log footer at the bottom of every page
- Match pyobs-web-client's sidebar layout: icons + Tools/Modules groups
- Bring back roof control as its own dedicated page
- Move Status to the top of the sidebar, remove Dashboard
- Persist "Skip TLS" per saved account
- Add a Status page: module health at a glance
- Revert the previous clang-tidy fix: it broke the build
- Fix clang-tidy modernize-return-braced-init-list in SchemaParse
- Replace single remembered login with a saved-accounts list, add server override
- Add a config file + remembered logins (password via OS keychain)
- TODO.md: add config file, remembered logins, parameterized shell commands, RoofWidget labeling
- Trim DEVELOPMENT.md to collapsed phase summaries, split TODO.md out
- Fix Main.qml never showing a window, and LoginWindow's TLS checkbox overflow
- DEVELOPMENT.md: add environment setup + current-status sections
- Phase 7.5: app shell - login window + sidebar navigation

## [0.1.0] - 2026-07-06

- CI: build and attach a release binary on version tag push
- Phase 7: first custom widget - RoofWidget (IRoof)
- Phase 6: events
- Phase 5: RPC execution
- DEVELOPMENT.md: Phase 7 uses IRoof, not ICamera
- Phase 4: generic state subscription + rendering
- Phase 3: presence-driven module list
- Revert old-Qt CI compatibility shims
- CI: run on ubuntu-26.04, cache Conan + qxmpp FetchContent build
- Fix CI build: QDomDocument::ParseOption needs Qt 6.8, CI ships older Qt6
- Phase 2: disco#info discovery
- Phase 1.5: value/XML codec (schema-less decode)
- Add .qmlproject for Qt Design Studio
- Fix unreadable Controls text: use ApplicationWindow + explicit dark theme
- Phase 1: XMPP connection walking skeleton
- Rename project from pyobs-qml-client to pyobs-gui++
- Phase 0: project bootstrap
