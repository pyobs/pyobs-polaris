# Qt Test, not Catch2: it already ships with the system Qt6 install (no
# extra Conan/FetchContent dependency), and later phases will want
# QSignalSpy-based assertions (e.g. Phase 4's subscribe ref-counting) that
# Qt Test is built for. This is the project's test framework for everything
# downstream - see DEVELOPMENT.md Phase 1.5.
find_package(Qt6 REQUIRED COMPONENTS Test Qml)

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
