# Qt Test, not Catch2: it already ships with the system Qt6 install (no
# extra Conan/FetchContent dependency), and later phases will want
# QSignalSpy-based assertions (e.g. Phase 4's subscribe ref-counting) that
# Qt Test is built for. This is the project's test framework for everything
# downstream - see DEVELOPMENT.md Phase 1.5.
find_package(Qt6 REQUIRED COMPONENTS Test Qml Quick)

add_executable(tst_wirevalue
    codec/tst_wirevalue.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireValue.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.cpp
)
target_include_directories(tst_wirevalue PRIVATE ${CMAKE_SOURCE_DIR}/src/codec)
target_link_libraries(tst_wirevalue PRIVATE Qt6::Test Qt6::Xml)

add_test(NAME tst_wirevalue COMMAND tst_wirevalue)

add_executable(tst_schema
    codec/tst_schema.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.h
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/InterfaceSchema.h
    ${CMAKE_SOURCE_DIR}/src/codec/SchemaParse.h
    ${CMAKE_SOURCE_DIR}/src/codec/SchemaParse.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.cpp
)
target_include_directories(tst_schema PRIVATE ${CMAKE_SOURCE_DIR}/src/codec)
target_link_libraries(tst_schema PRIVATE Qt6::Test Qt6::Xml)

add_test(NAME tst_schema COMMAND tst_schema)

add_executable(tst_statesubscription
    comm/tst_statesubscription.cpp
    ${CMAKE_SOURCE_DIR}/src/comm/StateSubscription.h
    ${CMAKE_SOURCE_DIR}/src/comm/StateSubscription.cpp
    ${CMAKE_SOURCE_DIR}/src/comm/StateSubscriptionManager.h
    ${CMAKE_SOURCE_DIR}/src/comm/StateSubscriptionManager.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireValue.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/VariantBridge.h
    ${CMAKE_SOURCE_DIR}/src/codec/VariantBridge.cpp
)
target_include_directories(tst_statesubscription PRIVATE
    ${CMAKE_SOURCE_DIR}/src/comm
    ${CMAKE_SOURCE_DIR}/src/codec
    ${qxmpp_BINARY_DIR}/src
)
target_link_libraries(tst_statesubscription PRIVATE Qt6::Test Qt6::Xml Qt6::Network Qt6::Qml QXmppQt6)

add_test(NAME tst_statesubscription COMMAND tst_statesubscription)

add_executable(tst_encode
    codec/tst_encode.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.h
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireValue.h
    ${CMAKE_SOURCE_DIR}/src/codec/Encode.h
    ${CMAKE_SOURCE_DIR}/src/codec/Encode.cpp
)
target_include_directories(tst_encode PRIVATE ${CMAKE_SOURCE_DIR}/src/codec)
target_link_libraries(tst_encode PRIVATE Qt6::Test Qt6::Xml)

add_test(NAME tst_encode COMMAND tst_encode)

add_executable(tst_variantbridge
    codec/tst_variantbridge.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.h
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireValue.h
    ${CMAKE_SOURCE_DIR}/src/codec/VariantBridge.h
    ${CMAKE_SOURCE_DIR}/src/codec/VariantBridge.cpp
)
target_include_directories(tst_variantbridge PRIVATE ${CMAKE_SOURCE_DIR}/src/codec)
target_link_libraries(tst_variantbridge PRIVATE Qt6::Test Qt6::Xml)

add_test(NAME tst_variantbridge COMMAND tst_variantbridge)

add_executable(tst_eventmanager
    comm/tst_eventmanager.cpp
    ${CMAKE_SOURCE_DIR}/src/comm/EventLogModel.h
    ${CMAKE_SOURCE_DIR}/src/comm/EventLogModel.cpp
    ${CMAKE_SOURCE_DIR}/src/comm/EventManager.h
    ${CMAKE_SOURCE_DIR}/src/comm/EventManager.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireValue.h
)
target_include_directories(tst_eventmanager PRIVATE
    ${CMAKE_SOURCE_DIR}/src/comm
    ${CMAKE_SOURCE_DIR}/src/codec
    ${qxmpp_BINARY_DIR}/src
)
target_link_libraries(tst_eventmanager PRIVATE Qt6::Test Qt6::Xml Qt6::Network Qt6::Qml QXmppQt6)

add_test(NAME tst_eventmanager COMMAND tst_eventmanager)

add_executable(tst_vfsclient
    comm/tst_vfsclient.cpp
    ${CMAKE_SOURCE_DIR}/src/comm/VfsClient.h
    ${CMAKE_SOURCE_DIR}/src/comm/VfsClient.cpp
)
target_include_directories(tst_vfsclient PRIVATE ${CMAKE_SOURCE_DIR}/src/comm)
target_link_libraries(tst_vfsclient PRIVATE Qt6::Test Qt6::Network Qt6::Qml)

add_test(NAME tst_vfsclient COMMAND tst_vfsclient)

add_executable(tst_modulelistmodel
    comm/tst_modulelistmodel.cpp
    ${CMAKE_SOURCE_DIR}/src/comm/ModuleInfo.h
    ${CMAKE_SOURCE_DIR}/src/comm/ModuleListModel.h
    ${CMAKE_SOURCE_DIR}/src/comm/ModuleListModel.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/InterfaceSchema.h
    ${CMAKE_SOURCE_DIR}/src/codec/WireValue.h
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.h
    ${CMAKE_SOURCE_DIR}/src/codec/WireType.cpp
)
target_include_directories(tst_modulelistmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/src/comm
    ${CMAKE_SOURCE_DIR}/src/codec
)
target_link_libraries(tst_modulelistmodel PRIVATE Qt6::Test Qt6::Qml)

add_test(NAME tst_modulelistmodel COMMAND tst_modulelistmodel)

add_executable(tst_shellcommandparser
    shell/tst_shellcommandparser.cpp
    ${CMAKE_SOURCE_DIR}/src/shell/ShellCommandParser.h
    ${CMAKE_SOURCE_DIR}/src/shell/ShellCommandParser.cpp
)
target_include_directories(tst_shellcommandparser PRIVATE ${CMAKE_SOURCE_DIR}/src/shell)
target_link_libraries(tst_shellcommandparser PRIVATE Qt6::Test)

add_test(NAME tst_shellcommandparser COMMAND tst_shellcommandparser)

add_executable(tst_plotitem
    plot/tst_plotitem.cpp
    ${CMAKE_SOURCE_DIR}/src/plot/PlotItem.h
    ${CMAKE_SOURCE_DIR}/src/plot/PlotItem.cpp
)
target_include_directories(tst_plotitem PRIVATE ${CMAKE_SOURCE_DIR}/src/plot)
target_link_libraries(tst_plotitem PRIVATE Qt6::Test Qt6::Quick Qt6::Qml)

add_test(NAME tst_plotitem COMMAND tst_plotitem)
set_tests_properties(tst_plotitem PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

add_executable(tst_appsettings
    config/tst_appsettings.cpp
    ${CMAKE_SOURCE_DIR}/src/config/AppSettings.h
    ${CMAKE_SOURCE_DIR}/src/config/AppSettings.cpp
)
target_include_directories(tst_appsettings PRIVATE ${CMAKE_SOURCE_DIR}/src/config)
target_link_libraries(tst_appsettings PRIVATE Qt6::Test Qt6::Core Qt6::Qml)

add_test(NAME tst_appsettings COMMAND tst_appsettings)

add_executable(tst_savedaccountsmodel
    config/tst_savedaccountsmodel.cpp
    ${CMAKE_SOURCE_DIR}/src/config/SavedAccountsModel.h
    ${CMAKE_SOURCE_DIR}/src/config/SavedAccountsModel.cpp
)
target_include_directories(tst_savedaccountsmodel PRIVATE ${CMAKE_SOURCE_DIR}/src/config)
target_link_libraries(tst_savedaccountsmodel PRIVATE Qt6::Test Qt6::Core Qt6::Qml qt6keychain)

# Exercises the real OS keychain (skips itself via QSKIP if no backend is
# available - see initTestCase()) rather than mocking QtKeychain, matching
# this project's "verify against the real thing" testing philosophy
# elsewhere (DEVELOPMENT.md). That makes it unsuitable for a sandboxed CI
# runner with no keychain daemon - if CI ever adds this test to its own
# run, confirm a headless keyring (e.g. gnome-keyring with --unlock, or
# dbus-run-session) is available first rather than assuming this passes
# there unmodified.
add_test(NAME tst_savedaccountsmodel COMMAND tst_savedaccountsmodel)

add_executable(tst_vfsendpointsmodel
    config/tst_vfsendpointsmodel.cpp
    ${CMAKE_SOURCE_DIR}/src/config/VfsEndpointsModel.h
    ${CMAKE_SOURCE_DIR}/src/config/VfsEndpointsModel.cpp
)
target_include_directories(tst_vfsendpointsmodel PRIVATE ${CMAKE_SOURCE_DIR}/src/config)
target_link_libraries(tst_vfsendpointsmodel PRIVATE Qt6::Test Qt6::Core Qt6::Qml qt6keychain)

# Same real-keychain-backend, CI-skips-itself shape as
# tst_savedaccountsmodel - see its own comment above, identical reasoning.
add_test(NAME tst_vfsendpointsmodel COMMAND tst_vfsendpointsmodel)

# No Qml/Network/Xml needed - CoordinateTransform.cpp has zero XMPP/QML
# dependency (see its own header comment), just libnova.
add_executable(tst_coordinatetransform
    util/tst_coordinatetransform.cpp
    ${CMAKE_SOURCE_DIR}/src/util/CoordinateTransform.h
    ${CMAKE_SOURCE_DIR}/src/util/CoordinateTransform.cpp
)
target_include_directories(tst_coordinatetransform PRIVATE ${CMAKE_SOURCE_DIR}/src/util)
target_link_libraries(tst_coordinatetransform PRIVATE Qt6::Test Qt6::Qml libnova)
# See CMakeLists.txt's own comment on polaris's identical definition.
target_compile_definitions(tst_coordinatetransform PRIVATE LIBNOVA_SHARED)

add_test(NAME tst_coordinatetransform COMMAND tst_coordinatetransform)

# No Qml/Network/Xml needed either - FitsImage.cpp has zero Qt-object/QML
# dependency (see its own header comment), just cfitsio.
add_executable(tst_fitsimage
    fits/tst_fitsimage.cpp
    ${CMAKE_SOURCE_DIR}/src/fits/FitsImage.h
    ${CMAKE_SOURCE_DIR}/src/fits/FitsImage.cpp
)
target_include_directories(tst_fitsimage PRIVATE ${CMAKE_SOURCE_DIR}/src/fits)
target_link_libraries(tst_fitsimage PRIVATE Qt6::Test cfitsio::cfitsio)

add_test(NAME tst_fitsimage COMMAND tst_fitsimage)

# Pure functions, no Qt-object/QML dependency - same shape as tst_fitsimage.
add_executable(tst_fitsstretch
    fits/tst_fitsstretch.cpp
    ${CMAKE_SOURCE_DIR}/src/fits/FitsStretch.h
    ${CMAKE_SOURCE_DIR}/src/fits/FitsStretch.cpp
)
target_include_directories(tst_fitsstretch PRIVATE ${CMAKE_SOURCE_DIR}/src/fits)
target_link_libraries(tst_fitsstretch PRIVATE Qt6::Test Qt6::Gui)

add_test(NAME tst_fitsstretch COMMAND tst_fitsstretch)

# FitsImageItem is a QQuickPaintedItem - needs Quick/Qml like tst_plotitem,
# plus FitsImage/FitsStretch/cfitsio underneath it.
add_executable(tst_fitsimageitem
    fits/tst_fitsimageitem.cpp
    ${CMAKE_SOURCE_DIR}/src/fits/FitsImageItem.h
    ${CMAKE_SOURCE_DIR}/src/fits/FitsImageItem.cpp
    ${CMAKE_SOURCE_DIR}/src/fits/FitsImage.h
    ${CMAKE_SOURCE_DIR}/src/fits/FitsImage.cpp
    ${CMAKE_SOURCE_DIR}/src/fits/FitsStretch.h
    ${CMAKE_SOURCE_DIR}/src/fits/FitsStretch.cpp
)
target_include_directories(tst_fitsimageitem PRIVATE ${CMAKE_SOURCE_DIR}/src/fits)
target_link_libraries(tst_fitsimageitem PRIVATE Qt6::Test Qt6::Quick Qt6::Qml cfitsio::cfitsio)

add_test(NAME tst_fitsimageitem COMMAND tst_fitsimageitem)
