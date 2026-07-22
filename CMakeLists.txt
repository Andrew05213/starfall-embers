cmake_minimum_required(VERSION 3.25)

# Honor CMAKE_MSVC_RUNTIME_LIBRARY when targets are created.
cmake_policy(SET CMP0091 NEW)

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

if(MSVC)
    # Godot's Windows binaries use the dynamic release CRT. Keep every target,
    # including Debug builds, on the same CRT and STL ABI before any target is
    # created. godot-cpp defaults to this policy as well.
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL"
        CACHE STRING "MSVC runtime used by all Starfall targets" FORCE)
    set(GODOTCPP_DEBUG_CRT OFF
        CACHE BOOL "Use the release dynamic CRT for godot-cpp Debug builds" FORCE)
    set(GODOTCPP_USE_STATIC_CPP OFF
        CACHE BOOL "Link godot-cpp against the dynamic MSVC runtime" FORCE)
endif()

add_subdirectory(native/sim_core)

if(STARFALL_BUILD_GODOT_BRIDGE)
    add_subdirectory(native/godot_bridge)
endif()

if(STARFALL_BUILD_TESTS)
    include(CTest)
    add_subdirectory(tests)
endif()

