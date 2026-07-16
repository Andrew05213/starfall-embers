#pragma once

#include <cstdint>

namespace starfall::sim {

struct SimulationConfig final {
    std::uint32_t ticks_per_second = 30;
    std::uint32_t chunk_size = 64;
};

class World final {
public:
    explicit World(SimulationConfig config = {});

    void step() noexcept;

    [[nodiscard]] const SimulationConfig& config() const noexcept;
    [[nodiscard]] std::uint64_t tick() const noexcept;

private:
    SimulationConfig config_;
    std::uint64_t tick_ = 0;
};

} // namespace starfall::sim
