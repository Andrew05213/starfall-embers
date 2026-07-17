add_executable(starfall_native_chunk_benchmark
    native_chunk_benchmark.cpp
)

target_link_libraries(starfall_native_chunk_benchmark PRIVATE starfall::sim_core)
