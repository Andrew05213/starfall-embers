if(NOT EXISTS "${PROJECT_SOURCE_DIR}/third_party/godot-cpp/CMakeLists.txt")
    message(FATAL_ERROR
        "godot-cpp is not initialized. Initialize the pinned submodule under "
        "third_party/godot-cpp before enabling STARFALL_BUILD_GODOT_BRIDGE."
    )
endif()

set(GODOTCPP_API_VERSION "4.6" CACHE STRING "Godot API compatibility floor" FORCE)
set(GODOTCPP_SYSTEM_HEADERS ON CACHE BOOL "Treat godot-cpp headers as system headers" FORCE)

add_subdirectory(
    "${PROJECT_SOURCE_DIR}/third_party/godot-cpp"
    "${CMAKE_BINARY_DIR}/third_party/godot-cpp"
)

add_library(starfall_godot_bridge SHARED
    src/register_types.cpp
    src/simulation_host_node.cpp
)

target_include_directories(starfall_godot_bridge
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(starfall_godot_bridge
    PRIVATE
        godot-cpp
        starfall::sim_core
)

target_compile_features(starfall_godot_bridge PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(starfall_godot_bridge PRIVATE /W4 /permissive-)
else()
    target_compile_options(starfall_godot_bridge PRIVATE -Wall -Wextra -Wpedantic)
endif()

string(TOLOWER "${CMAKE_SYSTEM_NAME}" STARFALL_GODOT_PLATFORM)
if(STARFALL_GODOT_PLATFORM STREQUAL "darwin")
    set(STARFALL_GODOT_PLATFORM "macos")
endif()

string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" STARFALL_GODOT_ARCH)
if(STARFALL_GODOT_ARCH MATCHES "^(amd64|x86_64)$")
    set(STARFALL_GODOT_ARCH "x86_64")
elseif(STARFALL_GODOT_ARCH MATCHES "^(aarch64|arm64)$")
    set(STARFALL_GODOT_ARCH "arm64")
endif()

set(STARFALL_GODOT_OUTPUT_DIR "${PROJECT_SOURCE_DIR}/game/addons/starfall_sim/bin")
set_target_properties(starfall_godot_bridge PROPERTIES
    OUTPUT_NAME "starfall_sim.${STARFALL_GODOT_PLATFORM}.$<IF:$<CONFIG:Debug>,debug,release>.${STARFALL_GODOT_ARCH}"
    LIBRARY_OUTPUT_DIRECTORY "${STARFALL_GODOT_OUTPUT_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${STARFALL_GODOT_OUTPUT_DIR}"
)

# Visual Studio and Xcode otherwise append a configuration subdirectory such
# as Debug/, while the .gdextension descriptor intentionally uses stable paths.
foreach(STARFALL_CONFIG DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    set_target_properties(starfall_godot_bridge PROPERTIES
        "LIBRARY_OUTPUT_DIRECTORY_${STARFALL_CONFIG}" "${STARFALL_GODOT_OUTPUT_DIR}"
        "RUNTIME_OUTPUT_DIRECTORY_${STARFALL_CONFIG}" "${STARFALL_GODOT_OUTPUT_DIR}"
    )
endforeach()
