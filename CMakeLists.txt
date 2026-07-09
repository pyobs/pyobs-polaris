cmake_minimum_required(VERSION 3.21)

project(pyobs-gui++ LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Xml Network)

qt_standard_project_setup(REQUIRES 6.5)

# qxmpp/QtKeychain FetchContent pins - see cmake/Dependencies.cmake's own
# header comment for why these live in a separate file (CI cache-key
# scoping), not inlined here.
include(cmake/Dependencies.cmake)

qt_add_executable(pyobs-gui++
    src/main.cpp
    src/comm/XmppClient.cpp
    src/comm/XmppClient.h
    src/config/AppSettings.h
    src/config/AppSettings.cpp
    src/config/SavedAccountsModel.h
    src/config/SavedAccountsModel.cpp
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
)

qt_add_qml_module(pyobs-gui++
    URI pyobs.gui
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/LoginWindow.qml
        qml/MainWindow.qml
        qml/WidgetRegistry.qml
        qml/PluginLoader.qml
        qml/views/ShellView.qml
        qml/views/LogsView.qml
        qml/views/EventsView.qml
        qml/views/StatusView.qml
        qml/views/RoofView.qml
        qml/views/AutoFocusView.qml
        qml/views/AcquisitionView.qml
        qml/views/AutoGuidingView.qml
        qml/views/ModeView.qml
        qml/views/WeatherView.qml
        qml/widgets/KeyValueCard.qml
        qml/widgets/LogFooter.qml
)

target_link_libraries(pyobs-gui++ PRIVATE
    Qt6::Quick
    Qt6::Xml
    Qt6::Network
    QXmppQt6
    qt6keychain
)

# QXmppQt6's target_include_directories only exposes qxmpp_export.h (from
# generate_export_header) as a PRIVATE include, so consumers linking against
# it via FetchContent need this added explicitly.
target_include_directories(pyobs-gui++ PRIVATE ${qxmpp_BINARY_DIR}/src)

# qmltyperegistrar emits #include <HeaderName.h> using only the header's
# basename (taken from the #include in the .cpp that defined the QML_ELEMENT
# class), so every directory holding such a header needs to be on the include
# path directly - add each new one here as later phases add QML_ELEMENT types
# outside src/comm.
target_include_directories(pyobs-gui++ PRIVATE src/comm src/config src/plot)

enable_testing()
add_subdirectory(tests)
