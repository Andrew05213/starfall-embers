add_library(starfall_sim_core STATIC
    src/ballistics.cpp
    src/simulation_host.cpp
    src/world.cpp
)

add_library(starfall::sim_core ALIAS starfall_sim_core)

set_target_properties(starfall_sim_core PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(starfall_sim_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(starfall_sim_core PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(starfall_sim_core PRIVATE /W4 /permissive-)
else()
    target_compile_options(starfall_sim_core PRIVATE -Wall -Wextra -Wpedantic)
endif()
