# Phase 0 — project bootstrap

Status: implemented, closed.

Qt6 (`Quick`, `Xml`, `Network`) + CMake project skeleton, C++20,
`qt_add_qml_module`. Conan (`conanfile.txt`) is the project's general C++
dependency manager for anything that comes up later (e.g. `cfitsio` for
FITS handling, plotting libs) — pin exact resolved versions, treat it like
`uv.lock`. **`qxmpp` is the one deliberate exception**: ConanCenter's
recipe pulls in `qt/[>=6]` as a build dependency, which would rebuild all
of Qt from source and conflict with the system Qt6 this project links
against — so it's vendored via CMake `FetchContent` instead, pinned to a
git tag, built directly against system Qt6.

