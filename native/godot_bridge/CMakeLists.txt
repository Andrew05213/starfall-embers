if(NOT EXISTS "${PROJECT_SOURCE_DIR}/third_party/godot-cpp/CMakeLists.txt")
    message(FATAL_ERROR
        "godot-cpp is not initialized. Add a Godot 4.7-compatible pinned revision under "
        "third_party/godot-cpp before enabling STARFALL_BUILD_GODOT_BRIDGE."
    )
endif()

add_subdirectory(
    "${PROJECT_SOURCE_DIR}/third_party/godot-cpp"
    "${CMAKE_BINARY_DIR}/third_party/godot-cpp"
)

add_library(starfall_godot_bridge SHARED
    src/register_types.cpp
)

target_link_libraries(starfall_godot_bridge
    PRIVATE
        godot-cpp
        starfall::sim_core
)

target_compile_features(starfall_godot_bridge PRIVATE cxx_std_20)
