cmake_minimum_required(VERSION 3.21)

project(polaris LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(WIN32)
    # Windows has no RPATH equivalent for locating dependency DLLs at
    # runtime (unlike Linux/macOS, where CMake's build-tree RPATH already
    # points every executable straight at wherever each FetchContent
    # dependency's .so/.dylib actually lives) - a .exe only searches its
    # own directory (plus PATH/System32) by default. Left at CMake's
    # per-target default, every test binary and the vendored qxmpp/
    # QtKeychain/libnova DLLs each land in their own separate build
    # subdirectory, so nothing can find its dependencies at runtime -
    # not a build failure, but a silent hang (a failed-to-load-DLL
    # executable can trigger a Windows Error Reporting dialog that
    # blocks forever with no interactive session to dismiss it, rather
    # than a fast, obvious error). Funnelling every executable and shared
    # library this project builds into one shared output directory - set
    # before qt_add_executable()/include(cmake/Dependencies.cmake) so it
    # also applies to the FetchContent-vendored targets - means each
    # .exe finds its dependency DLLs right next to itself, no separate
    # copy step needed.
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
endif()

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Xml Network)
# Conan dependency (conanfile.txt), unlike qxmpp/QtKeychain below - see
# that file's own comment on why cfitsio doesn't need the FetchContent/
# system-Qt workaround qxmpp does (no Qt dependency of its own to
# conflict with).
find_package(cfitsio REQUIRED)

qt_standard_project_setup(REQUIRES 6.5)

# qxmpp/QtKeychain FetchContent pins - see cmake/Dependencies.cmake's own
# header comment for why these live in a separate file (CI cache-key
# scoping), not inlined here.
include(cmake/Dependencies.cmake)

qt_add_executable(polaris
    src/main.cpp
    src/comm/XmppClient.cpp
    src/comm/XmppClient.h
    src/config/AppSettings.h
    src/config/AppSettings.cpp
    src/config/SavedAccountsModel.h
    src/config/SavedAccountsModel.cpp
    src/config/VfsEndpointsModel.h
    src/config/VfsEndpointsModel.cpp
    src/comm/VfsClient.h
    src/comm/VfsClient.cpp
    src/comm/ModuleInfo.h
    src/comm/ModuleListModel.h
    src/comm/ModuleListModel.cpp
    src/comm/Discovery.h
    src/comm/Discovery.cpp
    src/comm/StateSubscription.h
    src/comm/StateSubscription.cpp
    src/comm/StateSubscriptionManager.h
    src/comm/StateSubscriptionManager.cpp
    src/comm/Rpc.h
    src/comm/Rpc.cpp
    src/comm/EventLogModel.h
    src/comm/EventLogModel.cpp
    src/comm/EventManager.h
    src/comm/EventManager.cpp
    src/codec/WireValue.h
    src/codec/Decode.h
    src/codec/Decode.cpp
    src/codec/WireType.h
    src/codec/WireType.cpp
    src/codec/InterfaceSchema.h
    src/codec/SchemaParse.h
    src/codec/SchemaParse.cpp
    src/codec/VariantBridge.h
    src/codec/VariantBridge.cpp
    src/codec/Encode.h
    src/codec/Encode.cpp
    src/plot/PlotItem.h
    src/plot/PlotItem.cpp
    src/shell/ShellCommandParser.h
    src/shell/ShellCommandParser.cpp
    src/util/CoordinateTransform.h
    src/util/CoordinateTransform.cpp
    src/fits/FitsImage.h
    src/fits/FitsImage.cpp
    src/fits/FitsStretch.h
    src/fits/FitsStretch.cpp
    src/fits/FitsImageItem.h
    src/fits/FitsImageItem.cpp
    src/fits/FitsFileWriter.h
    src/fits/FitsFileWriter.cpp
)

if(APPLE)
    # qt_add_executable() doesn't opt into a real .app bundle on its own -
    # without this, "polaris" is a bare Mach-O executable, which
    # macdeployqt (release packaging, see build.yml) can't deploy into:
    # it specifically embeds Qt frameworks/plugins into an existing
    # Foo.app/Contents/{Frameworks,PlugIns}, not a loose binary.
    set_target_properties(polaris PROPERTIES MACOSX_BUNDLE TRUE)
endif()

# qt_add_qml_module's automatic QML_FILES scanning doesn't inspect a
# file's own `pragma Singleton` to decide the generated qmldir entry -
# without this, SidebarPanelRegistry.qml resolves as a regular
# (non-singleton) type at runtime, and referencing it by bare type name
# from QML (as every consumer here does, never instantiating it directly)
# fails with a confusing "Property 'registerPanel' of object
# SidebarPanelRegistry is not a function" rather than a clear "unknown
# type" error - caught live, not something a clean build alone reveals.
# Must come before qt_add_qml_module() - it reads this property when it
# processes QML_FILES below.
set_source_files_properties(qml/SidebarPanelRegistry.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(polaris
    URI pyobs.polaris
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/LoginWindow.qml
        qml/MainWindow.qml
        qml/WidgetRegistry.qml
        qml/SidebarPanelRegistry.qml
        qml/PluginLoader.qml
        qml/views/ShellView.qml
        qml/views/LogsView.qml
        qml/views/EventsView.qml
        qml/views/SettingsView.qml
        qml/views/StatusView.qml
        qml/views/RoofView.qml
        qml/views/TelescopeView.qml
        qml/views/CameraView.qml
        qml/views/AutoFocusView.qml
        qml/views/AcquisitionView.qml
        qml/views/AutoGuidingView.qml
        qml/views/ModeView.qml
        qml/views/WeatherView.qml
        qml/widgets/KeyValueCard.qml
        qml/widgets/LogFooter.qml
        qml/widgets/WireValueFormat.js
        qml/widgets/TemperaturesPanel.qml
        qml/widgets/FiltersPanel.qml
        qml/widgets/FocuserPanel.qml
        qml/widgets/CoolingPanel.qml
)

target_link_libraries(polaris PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Xml
    Qt6::Network
    QXmppQt6
    qt6keychain
    libnova
    cfitsio::cfitsio
)

# QXmppQt6's target_include_directories only exposes qxmpp_export.h (from
# generate_export_header) as a PRIVATE include, so consumers linking against
# it via FetchContent need this added explicitly.
target_include_directories(polaris PRIVATE ${qxmpp_BINARY_DIR}/src)

# libnova's ln_types.h requires exactly one of LIBNOVA_SHARED/
# LIBNOVA_STATIC to be defined, but (unlike QXmppQt6 above) its own
# CMakeLists.txt doesn't propagate this to consumers via
# target_compile_definitions(... PUBLIC ...) - see cmake/Dependencies.cmake's
# own comment on the libnova FetchContent block for why. Matches
# BUILD_SHARED_LIBRARY defaulting to ON there.
target_compile_definitions(polaris PRIVATE LIBNOVA_SHARED)

# qmltyperegistrar emits #include <HeaderName.h> using only the header's
# basename (taken from the #include in the .cpp that defined the QML_ELEMENT
# class), so every directory holding such a header needs to be on the include
# path directly - add each new one here as later phases add QML_ELEMENT types
# outside src/comm.
target_include_directories(polaris PRIVATE src/comm src/config src/plot src/util src/fits)

enable_testing()
add_subdirectory(tests)
