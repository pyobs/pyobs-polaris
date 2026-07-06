# Qt Test, not Catch2: it already ships with the system Qt6 install (no
# extra Conan/FetchContent dependency), and later phases will want
# QSignalSpy-based assertions (e.g. Phase 4's subscribe ref-counting) that
# Qt Test is built for. This is the project's test framework for everything
# downstream - see DEVELOPMENT.md Phase 1.5.
find_package(Qt6 REQUIRED COMPONENTS Test)

add_executable(tst_wirevalue
    codec/tst_wirevalue.cpp
    ${CMAKE_SOURCE_DIR}/src/codec/WireValue.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.h
    ${CMAKE_SOURCE_DIR}/src/codec/Decode.cpp
)
target_include_directories(tst_wirevalue PRIVATE ${CMAKE_SOURCE_DIR}/src/codec)
target_link_libraries(tst_wirevalue PRIVATE Qt6::Test Qt6::Xml)

add_test(NAME tst_wirevalue COMMAND tst_wirevalue)
