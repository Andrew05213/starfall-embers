#include "starfall/sim/ballistics.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <optional>
#include <stdexcept>
#include <utility>

namespace starfall::sim {
namespace {

constexpr double distance_epsilon = 1.0e-9;
constexpr double hit_epsilon = 1.0e-6;
constexpr double terrain_sample_step = 0.8;
constexpr std::uint8_t material_mask = 0x0f;

[[nodiscard]] bool is_finite(Vec2 value) noexcept {
    return std::isfinite(value.x) && std::isfinite(value.y);
}

[[nodiscard]] bool is_valid(const SpawnProjectileCommand& command) noexcept {
    return is_finite(command.position)
        && is_finite(command.velocity)
        && std::isfinite(command.lifetime_seconds)
        && command.lifetime_seconds > 0.0
        && std::isfinite(command.gravity_scale)
        && command.gravity_scale >= 0.0
        && std::isfinite(command.collision_radius)
        && command.collision_radius >= 0.0;
}

struct CollisionHit final {
    double fraction = std::numeric_limits<double>::infinity();
    std::uint64_t collider_id = 0;
    bool terrain = false;
};

[[nodiscard]] std::optional<double> sweep_circle(
    Vec2 from,
    Vec2 to,
    Vec2 center,
    double radius
) noexcept {
    const Vec2 direction = to - from;
    const Vec2 offset = from - center;
    const double a = direction.x * direction.x + direction.y * direction.y;
    const double c = offset.x * offset.x + offset.y * offset.y - radius * radius;
    if (c <= 0.0) {
        return 0.0;
    }
    if (a <= distance_epsilon * distance_epsilon) {
        return std::nullopt;
    }
    const double b = 2.0 * (offset.x * direction.x + offset.y * direction.y);
    const double discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0.0) {
        return std::nullopt;
    }
    const double fraction = (-b - std::sqrt(discriminant)) / (2.0 * a);
    if (fraction < 0.0 || fraction > 1.0) {
        return std::nullopt;
    }
    return fraction;
}

[[nodiscard]] std::optional<double> sweep_box(
    Vec2 from,
    Vec2 to,
    Vec2 center,
    Vec2 half_extents,
    double projectile_radius
) noexcept {
    const Vec2 minimum{
        center.x - half_extents.x - projectile_radius,
        center.y - half_extents.y - projectile_radius,
    };
    const Vec2 maximum{
        center.x + half_extents.x + projectile_radius,
        center.y + half_extents.y + projectile_radius,
    };
    const Vec2 direction = to - from;
    double minimum_fraction = 0.0;
    double maximum_fraction = 1.0;
    for (int axis = 0; axis < 2; ++axis) {
        const double start = axis == 0 ? from.x : from.y;
        const double delta = axis == 0 ? direction.x : direction.y;
        const double axis_minimum = axis == 0 ? minimum.x : minimum.y;
        const double axis_maximum = axis == 0 ? maximum.x : maximum.y;
        if (std::abs(delta) <= hit_epsilon) {
            if (start < axis_minimum || start > axis_maximum) {
                return std::nullopt;
            }
            continue;
        }
        double first = (axis_minimum - start) / delta;
        double second = (axis_maximum - start) / delta;
        if (first > second) {
            std::swap(first, second);
        }
        minimum_fraction = std::max(minimum_fraction, first);
        maximum_fraction = std::min(maximum_fraction, second);
        if (minimum_fraction > maximum_fraction) {
            return std::nullopt;
        }
    }
    if (maximum_fraction < 0.0 || minimum_fraction > 1.0) {
        return std::nullopt;
    }
    return std::clamp(minimum_fraction, 0.0, 1.0);
}

[[nodiscard]] bool terrain_is_solid(
    const TerrainCollisionGrid& terrain,
    Vec2 point
) noexcept {
    if (terrain.width == 0 || terrain.height == 0 || terrain.cell_size <= 0.0) {
        return false;
    }
    const auto x = static_cast<std::int64_t>(
        std::floor((point.x - terrain.origin.x) / terrain.cell_size)
    );
    const auto y = static_cast<std::int64_t>(
        std::floor((point.y - terrain.origin.y) / terrain.cell_size)
    );
    if (x < 0 || y < 0
        || x >= static_cast<std::int64_t>(terrain.width)
        || y >= static_cast<std::int64_t>(terrain.height)) {
        return false;
    }
    const auto index = static_cast<std::size_t>(y) * terrain.width
        + static_cast<std::size_t>(x);
    if (index >= terrain.cells.size()) {
        return false;
    }
    const auto material = terrain.cells[index] & material_mask;
    return material == 1 || material == 2 || material == 9;
}

[[nodiscard]] double sweep_terrain(
    Vec2 from,
    Vec2 to,
    double radius,
    const TerrainCollisionGrid& terrain
) noexcept {
    const Vec2 delta = to - from;
    const double distance = std::sqrt(delta.x * delta.x + delta.y * delta.y);
    const auto step_count = std::max<std::uint64_t>(
        1,
        static_cast<std::uint64_t>(std::ceil(distance / terrain_sample_step))
    );
    const Vec2 offsets[] = {
        {},
        {radius, 0.0},
        {-radius, 0.0},
        {0.0, radius},
        {0.0, -radius},
    };
    for (std::uint64_t step = 1; step <= step_count; ++step) {
        const double fraction = static_cast<double>(step) / static_cast<double>(step_count);
        const Vec2 center = from + delta * fraction;
        for (const auto offset : offsets) {
            if (terrain_is_solid(terrain, center + offset)) {
                return fraction;
            }
        }
    }
    return std::numeric_limits<double>::infinity();
}

[[nodiscard]] CollisionHit find_earliest_hit(
    Vec2 from,
    Vec2 to,
    double projectile_radius,
    const CollisionWorldSnapshot& world
) noexcept {
    CollisionHit best;
    for (const auto& collider : world.colliders) {
        if (collider.collider_id == 0 || !is_finite(collider.center)
            || !is_finite(collider.half_extents)) {
            continue;
        }
        std::optional<double> fraction;
        if (collider.shape == CollisionShape::circle && collider.half_extents.x >= 0.0) {
            fraction = sweep_circle(
                from,
                to,
                collider.center,
                collider.half_extents.x + projectile_radius
            );
        } else if (collider.shape == CollisionShape::axis_aligned_box
            && collider.half_extents.x >= 0.0 && collider.half_extents.y >= 0.0) {
            fraction = sweep_box(
                from,
                to,
                collider.center,
                collider.half_extents,
                projectile_radius
            );
        }
        if (!fraction.has_value()) {
            continue;
        }
        if (*fraction < best.fraction - hit_epsilon
            || (std::abs(*fraction - best.fraction) <= hit_epsilon
                && collider.collider_id < best.collider_id)) {
            best = {
                .fraction = *fraction,
                .collider_id = collider.collider_id,
                .terrain = false,
            };
        }
    }
    const double terrain_fraction = sweep_terrain(
        from,
        to,
        projectile_radius,
        world.terrain
    );
    if (terrain_fraction < best.fraction - hit_epsilon) {
        best = {
            .fraction = terrain_fraction,
            .collider_id = 0,
            .terrain = true,
        };
    }
    return best;
}

} // namespace

double PrimaryGravity::magnitude_at_distance(double distance) const noexcept {
    if (!std::isfinite(distance)
        || !std::isfinite(surface_radius)
        || !std::isfinite(surface_acceleration)
        || surface_radius <= 0.0
        || surface_acceleration <= 0.0) {
        return 0.0;
    }

    const double radial_distance = std::abs(distance);
    if (radial_distance <= surface_radius) {
        return surface_acceleration * radial_distance / surface_radius;
    }
    const double radius_ratio = surface_radius / radial_distance;
    return surface_acceleration * radius_ratio * radius_ratio;
}

Vec2 PrimaryGravity::acceleration_at(Vec2 position) const noexcept {
    if (!is_finite(position) || !is_finite(center)) {
        return {};
    }
    const Vec2 delta = center - position;
    const double distance_squared = delta.x * delta.x + delta.y * delta.y;
    if (distance_squared <= distance_epsilon * distance_epsilon) {
        return {};
    }
    const double distance = std::sqrt(distance_squared);
    const double magnitude = magnitude_at_distance(distance);
    return delta * (magnitude / distance);
}

BallisticSystem::BallisticSystem(
    std::uint32_t ticks_per_second,
    PrimaryGravity gravity
) : ticks_per_second_(ticks_per_second),
    gravity_(gravity) {
    if (ticks_per_second_ == 0) {
        throw std::invalid_argument("ticks_per_second must be greater than zero");
    }
    if (!is_finite(gravity_.center)
        || !std::isfinite(gravity_.surface_radius)
        || gravity_.surface_radius <= 0.0
        || !std::isfinite(gravity_.surface_acceleration)
        || gravity_.surface_acceleration < 0.0) {
        throw std::invalid_argument("primary gravity configuration is invalid");
    }
    fixed_step_seconds_ = 1.0 / static_cast<double>(ticks_per_second_);
    rebuild_state_batch();
}

void BallisticSystem::submit(ProjectileCommandBatch commands) {
    if (!pending_commands_.spawns.empty() || !pending_commands_.retires.empty()) {
        throw std::logic_error("a projectile command batch is already pending");
    }
    pending_commands_ = std::move(commands);
}

void BallisticSystem::set_collision_world(CollisionWorldSnapshot snapshot) {
    collision_world_ = std::move(snapshot);
}

void BallisticSystem::step() {
    ++tick_;
    event_batch_.tick = tick_;
    event_batch_.events.clear();

    process_retires();
    process_spawns();
    pending_commands_ = {};
    integrate_projectiles();
    rebuild_state_batch();
}

std::uint32_t BallisticSystem::ticks_per_second() const noexcept {
    return ticks_per_second_;
}

double BallisticSystem::fixed_step_seconds() const noexcept {
    return fixed_step_seconds_;
}

std::uint64_t BallisticSystem::tick() const noexcept {
    return tick_;
}

const PrimaryGravity& BallisticSystem::gravity() const noexcept {
    return gravity_;
}

const ProjectileStateBatch& BallisticSystem::states() const noexcept {
    return state_batch_;
}

const ProjectileEventBatch& BallisticSystem::events() const noexcept {
    return event_batch_;
}

void BallisticSystem::process_retires() {
    for (const auto& command : pending_commands_.retires) {
        const auto projectile = std::find_if(
            active_projectiles_.begin(),
            active_projectiles_.end(),
            [&command](const ProjectileState& state) {
                return state.projectile_id == command.projectile_id;
            }
        );
        if (projectile == active_projectiles_.end()) {
            continue;
        }
        event_batch_.events.push_back({
            .kind = command.reason == RetireReason::impact
                ? ProjectileEventKind::retired_on_impact
                : ProjectileEventKind::retired_external,
            .projectile_id = projectile->projectile_id,
            .request_id = projectile->request_id,
            .tick = tick_,
            .position = projectile->position,
            .velocity = projectile->velocity,
        });
        active_projectiles_.erase(projectile);
    }
}

void BallisticSystem::process_spawns() {
    for (const auto& command : pending_commands_.spawns) {
        if (!is_valid(command)) {
            event_batch_.events.push_back({
                .kind = ProjectileEventKind::rejected,
                .request_id = command.request_id,
                .tick = tick_,
                .position = command.position,
                .velocity = command.velocity,
            });
            continue;
        }
        const auto id = next_projectile_id_++;
        active_projectiles_.push_back({
            .projectile_id = id,
            .request_id = command.request_id,
            .previous_position = command.position,
            .position = command.position,
            .velocity = command.velocity,
            .age_seconds = 0.0,
            .lifetime_seconds = command.lifetime_seconds,
            .gravity_scale = command.gravity_scale,
            .collision_radius = command.collision_radius,
        });
        event_batch_.events.push_back({
            .kind = ProjectileEventKind::spawned,
            .projectile_id = id,
            .request_id = command.request_id,
            .tick = tick_,
            .position = command.position,
            .velocity = command.velocity,
        });
    }
}

void BallisticSystem::integrate_projectiles() {
    auto projectile = active_projectiles_.begin();
    while (projectile != active_projectiles_.end()) {
        const double remaining_lifetime = projectile->lifetime_seconds - projectile->age_seconds;
        const double step_time = std::min(fixed_step_seconds_, std::max(remaining_lifetime, 0.0));
        projectile->previous_position = projectile->position;
        if (step_time > 0.0) {
            const Vec2 from = projectile->position;
            const Vec2 acceleration = gravity_.acceleration_at(projectile->position)
                * projectile->gravity_scale;
            const Vec2 to = projectile->position + projectile->velocity * step_time
                + acceleration * (0.5 * step_time * step_time);
            const auto hit = find_earliest_hit(
                from,
                to,
                projectile->collision_radius,
                collision_world_
            );
            if (std::isfinite(hit.fraction)) {
                const double fraction = std::clamp(hit.fraction, 0.0, 1.0);
                projectile->position = from + (to - from) * fraction;
                projectile->velocity += acceleration * (step_time * fraction);
                projectile->age_seconds += step_time * fraction;
                event_batch_.events.push_back({
                    .kind = hit.terrain
                        ? ProjectileEventKind::hit_terrain
                        : ProjectileEventKind::hit_entity,
                    .projectile_id = projectile->projectile_id,
                    .request_id = projectile->request_id,
                    .tick = tick_,
                    .collider_id = hit.collider_id,
                    .position = projectile->position,
                    .velocity = projectile->velocity,
                });
                projectile = active_projectiles_.erase(projectile);
                continue;
            }
            projectile->position = to;
            projectile->velocity += acceleration * step_time;
            projectile->age_seconds += step_time;
        }

        if (projectile->age_seconds + std::numeric_limits<double>::epsilon()
            >= projectile->lifetime_seconds) {
            event_batch_.events.push_back({
                .kind = ProjectileEventKind::expired,
                .projectile_id = projectile->projectile_id,
                .request_id = projectile->request_id,
                .tick = tick_,
                .position = projectile->position,
                .velocity = projectile->velocity,
            });
            projectile = active_projectiles_.erase(projectile);
        } else {
            ++projectile;
        }
    }
}

void BallisticSystem::rebuild_state_batch() {
    state_batch_.tick = tick_;
    state_batch_.projectiles = active_projectiles_;
}

} // namespace starfall::sim
