#include "starfall/sim/ballistics.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <utility>

namespace starfall::sim {
namespace {

constexpr double distance_epsilon = 1.0e-9;

[[nodiscard]] bool is_finite(Vec2 value) noexcept {
    return std::isfinite(value.x) && std::isfinite(value.y);
}

[[nodiscard]] bool is_valid(const SpawnProjectileCommand& command) noexcept {
    return is_finite(command.position)
        && is_finite(command.velocity)
        && std::isfinite(command.lifetime_seconds)
        && command.lifetime_seconds > 0.0
        && std::isfinite(command.gravity_scale)
        && command.gravity_scale >= 0.0;
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
            const Vec2 acceleration = gravity_.acceleration_at(projectile->position)
                * projectile->gravity_scale;
            projectile->position += projectile->velocity * step_time
                + acceleration * (0.5 * step_time * step_time);
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
