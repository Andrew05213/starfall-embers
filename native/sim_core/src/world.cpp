#include "starfall/sim/world.hpp"

#include <stdexcept>

namespace starfall::sim {

World::World(SimulationConfig config) : config_(config) {
    if (config_.ticks_per_second == 0) {
        throw std::invalid_argument("ticks_per_second must be greater than zero");
    }
    if (config_.chunk_size == 0) {
        throw std::invalid_argument("chunk_size must be greater than zero");
    }
}

void World::step() noexcept {
    ++tick_;
}

const SimulationConfig& World::config() const noexcept {
    return config_;
}

std::uint64_t World::tick() const noexcept {
    return tick_;
}

} // namespace starfall::sim
