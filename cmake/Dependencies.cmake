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

# libnova (TODO.md's "ITelescope follow-up"): same treatment as qxmpp/
# qtkeychain above, pinned via FetchContent against system libs - not a
# Conan dependency, same one-story-for-small-C-libraries reasoning as
# QtKeychain's own comment. This is the genuine upstream project (hosted
# on SourceForge, mirrored to git.code.sf.net for git access), pinned to
# its actual v0.16 tagged release - confirmed via `git ls-remote --tags`,
# not a third-party fork.
#
# Also skips the top-level file's own project(libnova) call, which is
# what would otherwise have implicitly enabled the C language for this
# whole build (this project's own top-level project(polaris LANGUAGES CXX)
# only enables C++) - libnova is a plain C library, so enable_language(C)
# explicitly, or CMake fails later with "CMAKE_C_COMPILE_OBJECT... cmake
# may not be built correctly" while trying to compile its .c sources.
enable_language(C)
#
# SOURCE_SUBDIR src points FetchContent straight at src/CMakeLists.txt,
# skipping this version's top-level CMakeLists.txt (and therefore its
# unconditional add_subdirectory(lntest)/add_subdirectory(examples) -
# this old version predates any BUILD_TESTING/BUILD_EXAMPLES-style option
# to disable them, and lntest's own executable target is literally named
# `test`, which collides with CTest's reserved "test" target name once
# this project's own enable_testing() is active - a real configure error,
# not a hypothetical one). src/CMakeLists.txt normally expects its parent
# (the skipped top-level file) to have already set a couple of variables
# first - LIBRARY_NAME (the actual target name, `libnova`) and
# BUILD_SHARED_LIBS (add_library() with neither STATIC nor SHARED given
# defaults to static if this is unset) - set explicitly below since nothing
# else will. Nothing in libnova's own source/build files is patched -
# this is exactly upstream's unmodified content, just entered at a
# different subdirectory than its own top-level file would.
set(LIBRARY_NAME libnova)
set(BUILD_SHARED_LIBS ON)
FetchContent_Declare(
    libnova
    GIT_REPOSITORY https://git.code.sf.net/p/libnova/libnova
    GIT_TAG v0.16
    SOURCE_SUBDIR src
)
# v0.16's own cmake_minimum_required(VERSION 2.6) is a hard configure error
# on modern CMake ("Compatibility with CMake < 3.5 has been removed") -
# nothing to do with this project's own setup. CMAKE_POLICY_VERSION_MINIMUM
# is CMake's own documented escape hatch for exactly this (vendoring an
# old project whose actual CMakeLists.txt content doesn't rely on anything
# from CMake versions that old, just declares a low floor).
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
FetchContent_MakeAvailable(libnova)
unset(CMAKE_POLICY_VERSION_MINIMUM)
# Another thing the skipped top-level file would normally have set up
# (its own include_directories(${libnova_SOURCE_DIR}/src)) - without it,
# libnova's own .c files can't even find their own <libnova/foo.h>
# headers, let alone consumers. PUBLIC (not PRIVATE) so it also
# propagates to anything that links against libnova - this project's own
# CMakeLists.txt/tests/CMakeLists.txt don't need to separately add this
# same include directory to their own targets.
target_include_directories(libnova PUBLIC ${libnova_SOURCE_DIR}/src)
# julian_day.c guards its own fallback `static inline double round(double x)`
# behind #ifndef HAVE_ROUND - HAVE_ROUND is normally defined by the
# autotools configure script (AC_CHECK_FUNCS([round]) into config.h),
# which this CMake-only build never runs, so the fallback always compiles
# in and collides with glibc's real round() ("static declaration of
# 'round' follows non-static declaration"). round() is a real C99
# function, present on every platform this project actually targets
# (glibc, macOS, MSVC 2013+) - defining HAVE_ROUND ourselves is the
# correct fix, not a workaround for something actually missing.
target_compile_definitions(libnova PRIVATE HAVE_ROUND)
unset(LIBRARY_NAME)
unset(BUILD_SHARED_LIBS)

# libnova's ln_types.h requires exactly one of LIBNOVA_SHARED/
# LIBNOVA_STATIC to be defined, but (since its top-level CMakeLists.txt is
# skipped above) nothing sets that for consumers via
# target_compile_definitions(... PUBLIC ...) the way qxmpp/qtkeychain's own
# targets do. Any of this project's own sources that #include a libnova
# header need the same definition added explicitly on their own target(s)
# - see CMakeLists.txt's target_compile_definitions(polaris ...) and
# tests/CMakeLists.txt's tst_coordinatetransform target - matching
# BUILD_SHARED_LIBS ON above.
