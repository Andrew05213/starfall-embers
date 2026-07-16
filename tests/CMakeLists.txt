add_executable(starfall_world_smoke
    unit/world_smoke.cpp
)

target_link_libraries(starfall_world_smoke PRIVATE starfall::sim_core)

add_test(NAME starfall.world_smoke COMMAND starfall_world_smoke)
