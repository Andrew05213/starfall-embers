add_executable(starfall_native_ballistics_benchmark
    native_ballistics_benchmark.cpp
)

target_link_libraries(starfall_native_ballistics_benchmark
    PRIVATE
        starfall::sim_core
)

target_compile_features(starfall_native_ballistics_benchmark PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(starfall_native_ballistics_benchmark PRIVATE /W4 /permissive-)
else()
    target_compile_options(starfall_native_ballistics_benchmark PRIVATE -Wall -Wextra -Wpedantic)
endif()

add_executable(starfall_native_chunk_benchmark
    native_chunk_benchmark.cpp
)

target_link_libraries(starfall_native_chunk_benchmark
    PRIVATE
        starfall::sim_core
)

target_compile_features(starfall_native_chunk_benchmark PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(starfall_native_chunk_benchmark PRIVATE /W4 /permissive-)
else()
    target_compile_options(starfall_native_chunk_benchmark PRIVATE -Wall -Wextra -Wpedantic)
endif()

add_executable(starfall_native_gravity_benchmark
    native_gravity_benchmark.cpp
)

target_link_libraries(starfall_native_gravity_benchmark
    PRIVATE
        starfall::sim_core
)

target_compile_features(starfall_native_gravity_benchmark PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(starfall_native_gravity_benchmark PRIVATE /W4 /permissive-)
else()
    target_compile_options(starfall_native_gravity_benchmark PRIVATE -Wall -Wextra -Wpedantic)
endif()
