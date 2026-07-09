# pyobs-polaris

**Polaris** is a clean-room C++/QML desktop client for
[pyobs](https://www.pyobs.org) 2.0, an observatory control framework.
It's modeled directly on
[pyobs-web-client](https://github.com/pyobs/pyobs-web-client): it has no
dependency on `pyobs-core` itself — everything is built from XMPP
presence and disco#info discovered live over the wire, using
[QXmpp](https://github.com/qxmpp-project/qxmpp) in place of Strophe.js.

Rendering is generic by default: connect, and any discovered module's
interfaces render as key/value cards straight from their disco#info
schema, no per-interface code required. Hand-written QML widgets opt in
only where a custom UI earns its place — currently `IRoof`,
`IAutoFocus`, `IAcquisition`, `IAutoGuiding`, `IMode`, and `IWeather`.
Third-party widgets can also be added at runtime via a plugin directory
(see `examples/plugins/`).

## Quick start

```bash
# One-time per machine:
pipx install conan && conan profile detect --force

git clone git@github.com:pyobs/pyobs-polaris.git
cd pyobs-polaris

conan install . --build=missing
cmake --preset conan-release -DCMAKE_BUILD_TYPE=Release
cmake --build --preset conan-release
ctest --output-on-failure --test-dir build/Release

./build/Release/polaris
```

Prerequisites (Linux; developed/CI'd on Ubuntu 26.04): Qt 6.5+
(`qt6-base-dev qt6-base-dev-tools qt6-declarative-dev
qt6-declarative-dev-tools`), `libsecret-1-dev pkg-config`, CMake 3.21+,
a C++20 compiler, and Conan 2.x. Polaris always links against the
**system** Qt install — it's never bundled, including in release
tarballs.

## Documentation

- **[DEVELOPMENT.md](DEVELOPMENT.md)** — the primary reference: full
  environment setup, a phase-by-phase history of every completed
  feature with its design decisions and gotchas, the plugin file
  contract, and the release process.
- **[TODO.md](TODO.md)** — what's planned next.

## Releases

Pushing a `vX.Y.Z` tag triggers CI to build, test, fix up the RUNPATH
via `patchelf`, and publish a GitHub release with the binary plus its
vendored `.so`s. System Qt6 is a runtime requirement and is documented
as such in each release's notes.
