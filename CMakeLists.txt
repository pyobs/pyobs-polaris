cmake_minimum_required(VERSION 3.21)

project(pyobs-qml-client LANGUAGES CXX)

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

qt_add_executable(pyobs-qml-client
    src/main.cpp
)

qt_add_qml_module(pyobs-qml-client
    URI pyobs.gui
    VERSION 1.0
    QML_FILES
        qml/Main.qml
)

target_link_libraries(pyobs-qml-client PRIVATE
    Qt6::Quick
    Qt6::Xml
    Qt6::Network
    QXmppQt6
)
