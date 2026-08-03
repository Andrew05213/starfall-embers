#include "starfall/sim/gravity.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <stdexcept>

namespace starfall::sim {
namespace {

constexpr double distance_epsilon = 1.0e-9;
constexpr std::uint64_t fnv_offset = 1469598103934665603ULL;
constexpr std::uint64_t fnv_prime = 1099511628211ULL;

[[nodiscard]] bool is_finite(Vec2 value) noexcept {
    return std::isfinite(value.x) && std::isfinite(value.y);
}

[[nodiscard]] double length_squared(Vec2 value) noexcept {
    return value.x * value.x + value.y * value.y;
}

[[nodiscard]] std::uint64_t bits(double value) noexcept {
    std::uint64_t result = 0;
    static_assert(sizeof(result) == sizeof(value));
    std::memcpy(&result, &value, sizeof(result));
    return result;
}

void hash_bytes(std::uint64_t& hash, const void* data, std::size_t size) noexcept {
    const auto* bytes = static_cast<const std::uint8_t*>(data);
    for (std::size_t index = 0; index < size; ++index) {
        hash ^= bytes[index];
        hash *= fnv_prime;
    }
}

template <typename T>
void hash_value(std::uint64_t& hash, T value) noexcept {
    hash_bytes(hash, &value, sizeof(value));
}

[[nodiscard]] Vec2 local_acceleration(const LocalGravitySource& source, Vec2 position) noexcept {
    const Vec2 delta = source.center - position;
    if (source.kind == GravityFieldKind::uniform_vector) {
        if (length_squared(delta) > source.radius * source.radius) {
            return {};
        }
        return source.vector;
    }

    const double distance_squared = length_squared(delta);
    if (distance_squared <= distance_epsilon * distance_epsilon) {
        return {};
    }
    const double distance = std::sqrt(distance_squared);
    if (distance >= source.radius) {
        return {};
    }
    const double falloff = 1.0 - distance / source.radius;
    return delta * (source.strength * falloff / distance);
}

} // namespace

Vec2 PrimaryGravity::acceleration_at(Vec2 position) const noexcept {
    if (!is_finite(position) || !is_finite(center)) {
        return {};
    }
    const Vec2 delta = center - position;
    const double distance_squared = length_squared(delta);
    if (distance_squared <= distance_epsilon * distance_epsilon) {
        return {};
    }
    const double distance = std::sqrt(distance_squared);
    const double magnitude = magnitude_at_distance(distance);
    return delta * (magnitude / distance);
}

double PrimaryGravity::magnitude_at_distance(double distance) const noexcept {
    if (!std::isfinite(distance)
        || !std::isfinite(surface_radius)
        || surface_radius <= 0.0
        || !std::isfinite(surface_acceleration)
        || surface_acceleration < 0.0) {
        return 0.0;
    }
    const double radial_distance = std::abs(distance);
    if (radial_distance <= surface_radius) {
        return surface_acceleration * radial_distance / surface_radius;
    }
    const double radius_ratio = surface_radius / radial_distance;
    return surface_acceleration * radius_ratio * radius_ratio;
}

GravityField::GravityField(std::uint32_t ticks_per_second, PrimaryGravity primary)
    : ticks_per_second_(ticks_per_second),
      primary_(primary) {
    if (ticks_per_second_ == 0) {
        throw std::invalid_argument("gravity ticks_per_second must be greater than zero");
    }
    validate_primary(primary_);
}

void GravityField::validate_primary(const PrimaryGravity& primary) {
    if (!is_finite(primary.center)
        || !std::isfinite(primary.surface_radius)
        || primary.surface_radius <= 0.0
        || !std::isfinite(primary.surface_acceleration)
        || primary.surface_acceleration < 0.0) {
        throw std::invalid_argument("primary gravity configuration is invalid");
    }
}

void GravityField::validate_source(const LocalGravitySource& source) {
    if (source.source_id == 0
        || (source.kind != GravityFieldKind::radial_falloff
            && source.kind != GravityFieldKind::uniform_vector)
        || !is_finite(source.center)
        || !is_finite(source.vector)
        || !std::isfinite(source.strength)
        || source.strength < 0.0
        || !std::isfinite(source.radius)
        || source.radius <= 0.0) {
        throw std::invalid_argument("local gravity source is invalid");
    }
}

void GravityField::validate_command_batch(const GravitySourceCommandBatch& batch) const {
    if (batch.version != gravity_transport_dto_version) {
        throw std::invalid_argument("unsupported gravity transport DTO version");
    }
    std::vector<GravitySourceId> added;
    added.reserve(batch.commands.size());
    for (const auto& command : batch.commands) {
        if (command.kind == GravitySourceCommandKind::add) {
            validate_source(command.source);
            if (std::find(added.begin(), added.end(), command.source.source_id) != added.end()) {
                throw std::invalid_argument("duplicate local gravity source in batch");
            }
            added.push_back(command.source.source_id);
        } else if (command.kind == GravitySourceCommandKind::update) {
            validate_source(command.source);
            if (command.source.source_id != command.source_id || command.source_id == 0) {
                throw std::invalid_argument("gravity update source ID mismatch");
            }
        } else if (command.kind == GravitySourceCommandKind::remove) {
            if (command.source_id == 0) {
                throw std::invalid_argument("gravity remove source ID is invalid");
            }
        } else {
            throw std::invalid_argument("unknown gravity source command");
        }
    }
}

void GravityField::apply(GravitySourceCommandBatch batch) {
    validate_command_batch(batch);
    auto next_sources = sources_;
    for (const auto& command : batch.commands) {
        const auto id = command.kind == GravitySourceCommandKind::add
            ? command.source.source_id
            : command.source_id;
        const auto found = std::find_if(
            next_sources.begin(),
            next_sources.end(),
            [id](const LocalGravitySource& source) { return source.source_id == id; }
        );
        if (command.kind == GravitySourceCommandKind::add) {
            if (found != next_sources.end()) {
                throw std::invalid_argument("local gravity source already exists");
            }
            next_sources.push_back(command.source);
        } else if (command.kind == GravitySourceCommandKind::update) {
            if (found == next_sources.end()) {
                throw std::invalid_argument("local gravity source does not exist");
            }
            *found = command.source;
        } else {
            if (found == next_sources.end()) {
                throw std::invalid_argument("local gravity source does not exist");
            }
            next_sources.erase(found);
        }
    }
    std::sort(
        next_sources.begin(),
        next_sources.end(),
        [](const LocalGravitySource& left, const LocalGravitySource& right) {
            return left.source_id < right.source_id;
        }
    );
    sources_ = std::move(next_sources);
}

void GravityField::advance_tick() noexcept {
    ++tick_;
    sources_.erase(
        std::remove_if(
            sources_.begin(),
            sources_.end(),
            [this](const LocalGravitySource& source) {
                return source.expires_at_tick != 0 && source.expires_at_tick <= tick_;
            }
        ),
        sources_.end()
    );
}

std::uint32_t GravityField::ticks_per_second() const noexcept {
    return ticks_per_second_;
}

std::uint64_t GravityField::tick() const noexcept {
    return tick_;
}

const PrimaryGravity& GravityField::primary() const noexcept {
    return primary_;
}

const std::vector<LocalGravitySource>& GravityField::sources() const noexcept {
    return sources_;
}

std::size_t GravityField::source_count() const noexcept {
    return sources_.size();
}

GravitySample GravityField::sample(Vec2 position) const noexcept {
    GravitySample result;
    const Vec2 primary_acceleration = primary_.acceleration_at(position);
    result.acceleration = primary_acceleration;
    double dominant_magnitude = std::sqrt(length_squared(primary_acceleration));
    result.magnitude = dominant_magnitude;
    for (const auto& source : sources_) {
        const Vec2 contribution = local_acceleration(source, position);
        const double contribution_magnitude = std::sqrt(length_squared(contribution));
        result.acceleration += contribution;
        if (contribution_magnitude > dominant_magnitude) {
            dominant_magnitude = contribution_magnitude;
            result.dominant_source_id = source.source_id;
        }
    }
    result.magnitude = std::sqrt(length_squared(result.acceleration));
    return result;
}

std::vector<GravitySample> GravityField::sample_batch(
    const std::vector<Vec2>& positions
) const {
    std::vector<GravitySample> result;
    result.reserve(positions.size());
    for (const auto position : positions) {
        result.push_back(sample(position));
    }
    return result;
}

std::uint64_t GravityField::checksum() const noexcept {
    std::uint64_t hash = fnv_offset;
    hash_value(hash, gravity_transport_dto_version);
    hash_value(hash, ticks_per_second_);
    hash_value(hash, tick_);
    hash_value(hash, bits(primary_.center.x));
    hash_value(hash, bits(primary_.center.y));
    hash_value(hash, bits(primary_.surface_radius));
    hash_value(hash, bits(primary_.surface_acceleration));
    for (const auto& source : sources_) {
        hash_value(hash, source.source_id);
        hash_value(hash, static_cast<std::uint8_t>(source.kind));
        hash_value(hash, bits(source.center.x));
        hash_value(hash, bits(source.center.y));
        hash_value(hash, bits(source.vector.x));
        hash_value(hash, bits(source.vector.y));
        hash_value(hash, bits(source.strength));
        hash_value(hash, bits(source.radius));
        hash_value(hash, source.expires_at_tick);
    }
    return hash;
}

} // namespace starfall::sim
