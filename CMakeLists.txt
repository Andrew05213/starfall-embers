cmake_minimum_required(VERSION 3.25)

project(
    starfall_embers
    VERSION 0.0.1
    DESCRIPTION "Fallen Stars, Living Matter"
    LANGUAGES CXX
)

option(STARFALL_BUILD_TESTS "Build native smoke and unit tests" ON)
option(STARFALL_BUILD_GODOT_BRIDGE "Build the Godot GDExtension bridge" OFF)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_subdirectory(native/sim_core)

if(STARFALL_BUILD_GODOT_BRIDGE)
    add_subdirectory(native/godot_bridge)
endif()

if(STARFALL_BUILD_TESTS)
    include(CTest)
    add_subdirectory(tests)
endif()
