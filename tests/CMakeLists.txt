add_executable(starfall_world_smoke
    unit/world_smoke.cpp
)

target_link_libraries(starfall_world_smoke PRIVATE starfall::sim_core)

add_test(NAME starfall.world_smoke COMMAND starfall_world_smoke)

add_executable(starfall_ballistics_smoke
    unit/ballistics_smoke.cpp
)

target_link_libraries(starfall_ballistics_smoke PRIVATE starfall::sim_core)

add_test(NAME starfall.ballistics_smoke COMMAND starfall_ballistics_smoke)

add_executable(starfall_simulation_host_smoke
    unit/simulation_host_smoke.cpp
)

target_link_libraries(starfall_simulation_host_smoke PRIVATE starfall::sim_core)

add_test(NAME starfall.simulation_host_smoke COMMAND starfall_simulation_host_smoke)
