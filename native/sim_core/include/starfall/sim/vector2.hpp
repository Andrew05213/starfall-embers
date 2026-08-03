#pragma once

namespace starfall::sim {

struct Vec2 final {
    double x = 0.0;
    double y = 0.0;

    [[nodiscard]] constexpr Vec2 operator+(const Vec2& other) const noexcept {
        return {x + other.x, y + other.y};
    }

    [[nodiscard]] constexpr Vec2 operator-(const Vec2& other) const noexcept {
        return {x - other.x, y - other.y};
    }

    [[nodiscard]] constexpr Vec2 operator*(double scalar) const noexcept {
        return {x * scalar, y * scalar};
    }

    constexpr Vec2& operator+=(const Vec2& other) noexcept {
        x += other.x;
        y += other.y;
        return *this;
    }
};

[[nodiscard]] constexpr Vec2 operator*(double scalar, Vec2 value) noexcept {
    return value * scalar;
}

} // namespace starfall::sim
