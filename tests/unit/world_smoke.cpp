#include "starfall/sim/world.hpp"

#include <cassert>

int main() {
    starfall::sim::World world;

    assert(world.config().ticks_per_second == 30);
    assert(world.config().chunk_size == 64);
    assert(world.tick() == 0);

    world.step();
    assert(world.tick() == 1);

    return 0;
}
