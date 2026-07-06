cmake_minimum_required(VERSION 3.21)

project(pyobs-gui++ LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Xml Network)

qt_standard_project_setup(REQUIRES 6.5)

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

qt_add_executable(pyobs-gui++
    src/main.cpp
    src/comm/XmppClient.cpp
    src/comm/XmppClient.h
    src/comm/ModuleInfo.h
    src/comm/ModuleListModel.h
    src/comm/ModuleListModel.cpp
    src/comm/Discovery.h
    src/comm/Discovery.cpp
    src/comm/StateSubscription.h
    src/comm/StateSubscription.cpp
    src/comm/StateSubscriptionManager.h
    src/comm/StateSubscriptionManager.cpp
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
)

qt_add_qml_module(pyobs-gui++
    URI pyobs.gui
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/widgets/KeyValueCard.qml
)

target_link_libraries(pyobs-gui++ PRIVATE
    Qt6::Quick
    Qt6::Xml
    Qt6::Network
    QXmppQt6
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
target_include_directories(pyobs-gui++ PRIVATE src/comm)

enable_testing()
add_subdirectory(tests)
