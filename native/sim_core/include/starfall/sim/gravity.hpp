#pragma once

#include "starfall/sim/vector2.hpp"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace starfall::sim {

inline constexpr std::uint32_t gravity_transport_dto_version = 1;
using GravitySourceId = std::uint64_t;

struct PrimaryGravity final {
    Vec2 center{320.0, 10'020.0};
    double surface_radius = 10'000.0;
    double surface_acceleration = 320.0;

    [[nodiscard]] Vec2 acceleration_at(Vec2 position) const noexcept;
    [[nodiscard]] double magnitude_at_distance(double distance) const noexcept;
};

enum class GravityFieldKind : std::uint8_t {
    radial_falloff = 0,
    uniform_vector = 1,
};

enum class GravitySourceCommandKind : std::uint8_t {
    add = 0,
    update = 1,
    remove = 2,
};

struct LocalGravitySource final {
    GravitySourceId source_id = 0;
    GravityFieldKind kind = GravityFieldKind::radial_falloff;
    Vec2 center{};
    Vec2 vector{};
    double strength = 0.0;
    double radius = 1.0;
    std::uint64_t expires_at_tick = 0;
};

struct GravitySourceCommand final {
    GravitySourceCommandKind kind = GravitySourceCommandKind::add;
    std::uint64_t request_id = 0;
    LocalGravitySource source{};
    GravitySourceId source_id = 0;
};

struct GravitySourceCommandBatch final {
    std::uint32_t version = gravity_transport_dto_version;
    std::vector<GravitySourceCommand> commands;
};

struct GravitySample final {
    Vec2 acceleration{};
    double magnitude = 0.0;
    GravitySourceId dominant_source_id = 0;
};

/// Engine-independent gravity authority for native entities. MaterialWorld
/// remains a separate GDScript reference until its own migration.
class GravityField final {
public:
    explicit GravityField(
        std::uint32_t ticks_per_second = 30,
        PrimaryGravity primary = {}
    );

    void validate_command_batch(const GravitySourceCommandBatch& batch) const;
    void apply(GravitySourceCommandBatch batch);
    void advance_tick() noexcept;

    [[nodiscard]] std::uint32_t ticks_per_second() const noexcept;
    [[nodiscard]] std::uint64_t tick() const noexcept;
    [[nodiscard]] const PrimaryGravity& primary() const noexcept;
    [[nodiscard]] const std::vector<LocalGravitySource>& sources() const noexcept;
    [[nodiscard]] std::size_t source_count() const noexcept;
    [[nodiscard]] GravitySample sample(Vec2 position) const noexcept;
    [[nodiscard]] std::vector<GravitySample> sample_batch(
        const std::vector<Vec2>& positions
    ) const;
    [[nodiscard]] std::uint64_t checksum() const noexcept;

private:
    static void validate_primary(const PrimaryGravity& primary);
    static void validate_source(const LocalGravitySource& source);
    void expire_sources() noexcept;

    std::uint32_t ticks_per_second_ = 30;
    std::uint64_t tick_ = 0;
    PrimaryGravity primary_{};
    std::vector<LocalGravitySource> sources_{};
};

} // namespace starfall::sim
