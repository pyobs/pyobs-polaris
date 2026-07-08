# Vendored dependency pins, kept in their own file rather than inline in
# CMakeLists.txt so CI's "Cache FetchContent-vendored dependency builds"
# step (see .github/workflows/build.yml) can key its cache on just this
# file's hash - hashing the whole CMakeLists.txt busted that cache (by far
# the most expensive part of a CI run: ~100 qxmpp source files plus
# QtKeychain, rebuilt from scratch) on every unrelated CMakeLists.txt edit,
# which in practice is nearly every commit (a new widget/source file added
# to qt_add_executable()/qt_add_qml_module()'s lists). Only touch this file
# when actually bumping one of the GIT_TAG pins below.

# qxmpp is vendored via FetchContent rather than Conan: see conanfile.txt
# for why (its ConanCenter recipe would rebuild all of Qt from source).
# Pinned to a tag, built against this project's system Qt6.
include(FetchContent)
set(BUILD_SHARED ON CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_INTERNAL_TESTS OFF CACHE BOOL "" FORCE)
set(BUILD_DOCUMENTATION OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_OMEMO OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    qxmpp
    GIT_REPOSITORY https://github.com/qxmpp-project/qxmpp.git
    GIT_TAG v1.10.2
)
FetchContent_MakeAvailable(qxmpp)

# QtKeychain: same treatment as qxmpp above (vendored via FetchContent,
# pinned to a tag, built against system Qt6) purely for consistency - one
# dependency-management story for "small C++/Qt library that needs to
# link against this project's system Qt", not because its Conan recipe
# has qxmpp's Qt-from-source problem (untested either way; not worth
# re-litigating while FetchContent already works). Needs libsecret-1-dev
# + pkg-config on Linux (its own CMakeLists.txt requires libsecret-1 via
# pkg_check_modules) - see DEVELOPMENT.md's Prerequisites.
set(BUILD_WITH_QT5 OFF CACHE BOOL "" FORCE)
set(BUILD_TEST_APPLICATION OFF CACHE BOOL "" FORCE)
set(BUILD_QTQUICK_DEMO OFF CACHE BOOL "" FORCE)
set(BUILD_TRANSLATIONS OFF CACHE BOOL "" FORCE)
# Its own autotest subdirectory is gated on this CTest convention variable
# (set via its own `include(CTest)`, defaulting to ON) - forcing it off
# here only skips *its* test suite, since this project's own tests/
# registers via plain add_test() unconditionally, not through this.
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    qtkeychain
    GIT_REPOSITORY https://github.com/frankosterfeld/qtkeychain.git
    GIT_TAG 0.17.0
)
FetchContent_MakeAvailable(qtkeychain)
