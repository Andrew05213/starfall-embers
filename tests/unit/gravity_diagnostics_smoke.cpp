#include "starfall/sim/gravity.hpp"

#include <cassert>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace {

using namespace starfall::sim;

GravitySourceCommandBatch make_sources() {
    GravitySourceCommandBatch batch;
    for (std::uint64_t id = 1; id <= 32; ++id) {
        const bool uniform = id % 2 == 0;
        batch.commands.push_back({
            .kind = GravitySourceCommandKind::add,
            .request_id = id,
            .source = {
                .source_id = id,
                .kind = uniform
                    ? GravityFieldKind::uniform_vector
                    : GravityFieldKind::radial_falloff,
                .center = {static_cast<double>(id * 20), static_cast<double>(id * 13)},
                .vector = uniform ? Vec2{0.0, 12.0} : Vec2{},
                .strength = uniform ? 0.0 : 100.0,
                .radius = 96.0,
            },
        });
    }
    return batch;
}

void test_large_query_batch_is_deterministic() {
    GravityField first(30, PrimaryGravity{
        .center = {512.0, 512.0},
        .surface_radius = 400.0,
        .surface_acceleration = 320.0,
    });
    GravityField second = first;
    const auto commands = make_sources();
    first.apply(commands);
    second.apply(commands);

    std::vector<Vec2> positions;
    positions.reserve(4'096);
    for (std::size_t index = 0; index < 4'096; ++index) {
        positions.push_back({
            static_cast<double>((index * 37U) % 1'024U),
            static_cast<double>((index * 61U) % 1'024U),
        });
    }
    for (int tick = 0; tick < 3; ++tick) {
        first.advance_tick();
        second.advance_tick();
        const auto first_samples = first.sample_batch(positions);
        const auto second_samples = second.sample_batch(positions);
        assert(first_samples.size() == positions.size());
        assert(first_samples.size() == second_samples.size());
        for (std::size_t index = 0; index < first_samples.size(); ++index) {
            assert(first_samples[index].acceleration.x == second_samples[index].acceleration.x);
            assert(first_samples[index].acceleration.y == second_samples[index].acceleration.y);
            assert(first_samples[index].magnitude == second_samples[index].magnitude);
            assert(first_samples[index].dominant_source_id
                == second_samples[index].dominant_source_id);
        }
        assert(first.checksum() == second.checksum());
    }
}

} // namespace

int main() {
    test_large_query_batch_is_deterministic();
    return 0;
}
