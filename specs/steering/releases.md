# Releases

Standing contributor-guidance doc for cutting a release — keep it up to date as the process
changes.

Push a `vX.Y.Z` tag and CI does the rest: builds, runs tests, packages a redistributable tarball
(binary + the vendored `libQXmppQt6.so.5`, RUNPATH patched with `patchelf` so it's actually
runnable once extracted — see `.github/workflows/build.yml`'s own comments), and creates the
GitHub release with that tarball attached, via `gh` (pre-installed on GitHub-hosted runners,
authenticated with the automatic `GITHUB_TOKEN`). No manual artifact-building or uploading needed.
`v0.1.0` is the first example of this. System Qt6 itself is deliberately never bundled — the
release notes call this out as a runtime requirement instead.
