#include "starfall/sim/gravity.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <vector>

namespace {

using starfall::sim::GravityField;
using starfall::sim::GravityFieldKind;
using starfall::sim::GravitySourceCommand;
using starfall::sim::GravitySourceCommandBatch;
using starfall::sim::GravitySourceCommandKind;
using starfall::sim::PrimaryGravity;
using starfall::sim::Vec2;

constexpr std::uint32_t world_size = 1024;
constexpr std::size_t local_source_count = 32;
constexpr std::size_t query_count = 4'096;
constexpr std::size_t ticks = 300;
constexpr double frame_budget_ms = 1000.0 / 30.0;

[[nodiscard]] std::uint64_t next_random(std::uint64_t& state) noexcept {
    state = state * 6364136223846793005ULL + 1442695040888963407ULL;
    return state;
}

[[nodiscard]] double percentile95(std::vector<double> samples) {
    std::sort(samples.begin(), samples.end());
    const auto index = std::max<std::size_t>(
        0,
        static_cast<std::size_t>(samples.size() * 95U / 100U) - 1
    );
    return samples[index];
}

[[nodiscard]] bool samples_equal(
    const std::vector<starfall::sim::GravitySample>& left,
    const std::vector<starfall::sim::GravitySample>& right
) noexcept {
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t index = 0; index < left.size(); ++index) {
        if (left[index].acceleration.x != right[index].acceleration.x
            || left[index].acceleration.y != right[index].acceleration.y
            || left[index].magnitude != right[index].magnitude
            || left[index].dominant_source_id != right[index].dominant_source_id
            || left[index].zero_gravity != right[index].zero_gravity) {
            return false;
        }
    }
    return true;
}

GravitySourceCommandBatch make_sources() {
    GravitySourceCommandBatch batch;
    batch.commands.reserve(local_source_count);
    for (std::size_t index = 0; index < local_source_count; ++index) {
        const auto id = static_cast<std::uint64_t>(index + 1);
        const auto x = 128.0 + static_cast<double>((index * 197U) % 768U);
        const auto y = 128.0 + static_cast<double>((index * 311U) % 768U);
        const bool uniform = index % 2U == 1U;
        batch.commands.push_back({
            .kind = GravitySourceCommandKind::add,
            .request_id = id,
            .source = {
                .source_id = id,
                .kind = uniform
                    ? GravityFieldKind::uniform_vector
                    : GravityFieldKind::radial_falloff,
                .center = {x, y},
                .vector = uniform ? Vec2{0.0, 24.0 + static_cast<double>(index)} : Vec2{},
                .strength = uniform ? 0.0 : 180.0 + static_cast<double>(index),
                .radius = 96.0 + static_cast<double>(index % 5U) * 16.0,
            },
        });
    }
    return batch;
}

std::vector<Vec2> make_queries() {
    std::vector<Vec2> queries;
    queries.reserve(query_count);
    std::uint64_t state = 0x50442026ULL;
    for (std::size_t index = 0; index < query_count; ++index) {
        const auto x = static_cast<double>(next_random(state) % world_size);
        const auto y = static_cast<double>(next_random(state) % world_size);
        queries.push_back({x, y});
    }
    return queries;
}

} // namespace

int main() {
    using Clock = std::chrono::steady_clock;
    const PrimaryGravity primary{
        .center = {512.0, 512.0},
        .surface_radius = 400.0,
        .surface_acceleration = 320.0,
    };
    GravityField native(30, primary);
    GravityField replay(30, primary);
    const auto sources = make_sources();
    native.apply(sources);
    replay.apply(sources);
    const auto queries = make_queries();

    std::vector<double> tick_ms;
    tick_ms.reserve(ticks);
    std::uint64_t request_payload_bytes = 0;
    std::uint64_t response_payload_bytes = 0;
    std::uint64_t sampled_values = 0;
    bool deterministic = true;
    double checksum_guard = 0.0;

    for (std::size_t tick = 0; tick < ticks; ++tick) {
        const auto started = Clock::now();
        native.advance_tick();
        replay.advance_tick();
        const auto native_samples = native.sample_batch(queries);
        const auto replay_samples = replay.sample_batch(queries);
        const auto finished = Clock::now();
        tick_ms.push_back(std::chrono::duration<double, std::milli>(finished - started).count());

        request_payload_bytes += static_cast<std::uint64_t>(query_count) * 24U;
        // request_id + tick + acceleration + magnitude + dominant source + flags.
        response_payload_bytes += static_cast<std::uint64_t>(query_count) * 56U;
        sampled_values += native_samples.size();
        deterministic = deterministic
            && samples_equal(native_samples, replay_samples)
            && native.checksum() == replay.checksum();
        for (const auto& sample : native_samples) {
            checksum_guard += sample.acceleration.x + sample.acceleration.y;
        }
    }

    const auto average_ms = std::accumulate(tick_ms.begin(), tick_ms.end(), 0.0)
        / static_cast<double>(ticks);
    const auto p95_ms = percentile95(tick_ms);
    const auto max_ms = *std::max_element(tick_ms.begin(), tick_ms.end());
    const auto final_checksum = native.checksum();
    const auto replay_checksum = replay.checksum();

    std::cout << std::fixed << std::setprecision(3)
              << "native gravity benchmark\n"
              << "world: " << world_size << 'x' << world_size << '\n'
              << "local gravity sources: " << local_source_count << '\n'
              << "queries per tick: " << query_count << '\n'
              << "ticks: " << ticks << '\n'
              << "sampled values: " << sampled_values << '\n'
              << "request payload bytes: " << request_payload_bytes << '\n'
              << "response payload bytes: " << response_payload_bytes << '\n'
              << "tick average ms: " << average_ms << '\n'
              << "tick p95 ms: " << p95_ms << '\n'
              << "tick max ms: " << max_ms << '\n'
              << "30 Hz frame budget ms: " << frame_budget_ms << '\n'
              << "p95 budget utilization: " << (p95_ms / frame_budget_ms * 100.0) << "%\n"
              << "native checksum: " << final_checksum << '\n'
              << "replay checksum: " << replay_checksum << '\n'
              << "checksum replay: " << (deterministic ? "PASS" : "FAIL") << '\n'
              << "checksum guard: " << checksum_guard << '\n'
              << "frame budget: " << (p95_ms <= frame_budget_ms ? "PASS" : "OVER") << '\n';
    return deterministic ? 0 : 1;
}
