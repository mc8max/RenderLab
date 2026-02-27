//
//  CoreMath.hpp
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

#pragma once
#include <cmath>

namespace coremath {

static constexpr float kDegToRad = 3.14159265358979323846f / 180.0f;

struct Vec3 {
    float x, y, z;
};
inline float dot(const Vec3& a, const Vec3& b);
inline Vec3 operator-(const Vec3& a, const Vec3& b);

inline Vec3 operator+(const Vec3& a, const Vec3& b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline Vec3 operator-(const Vec3& v) { return {-v.x, -v.y, -v.z}; }
inline Vec3 operator*(const Vec3& v, float s) { return {v.x * s, v.y * s, v.z * s}; }
inline Vec3 operator*(float s, const Vec3& v) { return v * s; }
inline Vec3 operator/(const Vec3& v, float s) { const float inv = 1.0f / s; return {v.x * inv, v.y * inv, v.z * inv}; }
inline Vec3& operator+=(Vec3& a, const Vec3& b) { a.x += b.x; a.y += b.y; a.z += b.z; return a; }
inline Vec3& operator-=(Vec3& a, const Vec3& b) { a.x -= b.x; a.y -= b.y; a.z -= b.z; return a; }
inline Vec3& operator*=(Vec3& v, float s) { v.x *= s; v.y *= s; v.z *= s; return v; }
inline Vec3& operator/=(Vec3& v, float s) { const float inv = 1.0f / s; v.x *= inv; v.y *= inv; v.z *= inv; return v; }
inline float length(const Vec3& v) { return std::sqrt(dot(v, v)); }
inline float distance(const Vec3& a, const Vec3& b) { return length(a - b); }
inline Vec3 clamp(const Vec3& v, float minVal, float maxVal) { return { std::fmax(minVal, std::fmin(v.x, maxVal)), std::fmax(minVal, std::fmin(v.y, maxVal)), std::fmax(minVal, std::fmin(v.z, maxVal)) }; }
inline Vec3 min(const Vec3& a, const Vec3& b) { return { std::fmin(a.x, b.x), std::fmin(a.y, b.y), std::fmin(a.z, b.z) }; }
inline Vec3 max(const Vec3& a, const Vec3& b) { return { std::fmax(a.x, b.x), std::fmax(a.y, b.y), std::fmax(a.z, b.z) }; }
inline Vec3 lerp(const Vec3& a, const Vec3& b, float t) { return a + (b - a) * t; }
inline Vec3 reflect(const Vec3& I, const Vec3& N) { // Reflect incident vector I around normal N (assumes N normalized)
    return I - N * (2.0f * dot(I, N));
}

inline Vec3 operator-(const Vec3& a, const Vec3& b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }

inline Vec3 cross(const Vec3& a, const Vec3& b) {
    return { a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x };
}

inline float dot(const Vec3& a, const Vec3& b) { return a.x*b.x + a.y*b.y + a.z*b.z; }

inline Vec3 normalize(const Vec3& v) {
    const float len = std::sqrt(dot(v,v));
    if (len <= 0.0f) return {0,0,0};
    const float inv = 1.0f / len;
    return { v.x*inv, v.y*inv, v.z*inv };
}

// Column-major 4x4 matrix: m[column][row]
struct Mat4 {
    float m[4][4];
};

inline Mat4 identity() {
    Mat4 r{};
    r.m[0][0] = 1; r.m[1][1] = 1; r.m[2][2] = 1; r.m[3][3] = 1;
    return r;
}

inline Mat4 mul(const Mat4& a, const Mat4& b) {
    Mat4 r{};
    for (int c = 0; c < 4; ++c) {
        for (int rrow = 0; rrow < 4; ++rrow) {
            float s = 0.0f;
            for (int k = 0; k < 4; ++k) {
                s += a.m[k][rrow] * b.m[c][k];
            }
            r.m[c][rrow] = s;
        }
    }
    return r;
}

inline Mat4 operator*(const Mat4& a, const Mat4& b) { return mul(a,b); }

inline Mat4 translation(const Vec3& t) {
    Mat4 r = identity();
    r.m[3][0] = t.x;
    r.m[3][1] = t.y;
    r.m[3][2] = t.z;
    return r;
}

inline Mat4 rotationX(float rad) {
    Mat4 r = identity();
    const float c = std::cos(rad);
    const float s = std::sin(rad);
    r.m[1][1] = c;  r.m[2][1] = -s;
    r.m[1][2] = s;  r.m[2][2] = c;
    return r;
}

inline Mat4 rotationY(float rad) {
    Mat4 r = identity();
    const float c = std::cos(rad);
    const float s = std::sin(rad);
    r.m[0][0] = c;  r.m[2][0] = s;
    r.m[0][2] = -s; r.m[2][2] = c;
    return r;
}

inline Mat4 rotationZ(float rad) {
    Mat4 r = identity();
    const float c = std::cos(rad);
    const float s = std::sin(rad);
    r.m[0][0] = c;  r.m[1][0] = -s;
    r.m[0][1] = s;  r.m[1][1] = c;
    return r;
}

inline Mat4 scale(const Vec3& s) {
    Mat4 r{};
    r.m[0][0] = s.x; r.m[1][1] = s.y; r.m[2][2] = s.z; r.m[3][3] = 1.0f;
    return r;
}

inline Mat4 transpose(const Mat4& a) {
    Mat4 r{};
    for (int c = 0; c < 4; ++c) {
        for (int rrow = 0; rrow < 4; ++rrow) {
            r.m[c][rrow] = a.m[rrow][c];
        }
    }
    return r;
}

inline Vec3 transformPoint(const Mat4& m, const Vec3& p) {
    // Assumes w=1
    float x = m.m[0][0]*p.x + m.m[1][0]*p.y + m.m[2][0]*p.z + m.m[3][0];
    float y = m.m[0][1]*p.x + m.m[1][1]*p.y + m.m[2][1]*p.z + m.m[3][1];
    float z = m.m[0][2]*p.x + m.m[1][2]*p.y + m.m[2][2]*p.z + m.m[3][2];
    float w = m.m[0][3]*p.x + m.m[1][3]*p.y + m.m[2][3]*p.z + m.m[3][3];
    if (w != 0.0f) {
        float invW = 1.0f / w;
        return { x * invW, y * invW, z * invW };
    }
    return { x, y, z };
}

inline Vec3 transformVector(const Mat4& m, const Vec3& v) {
    // Assumes w=0 (no translation)
    float x = m.m[0][0]*v.x + m.m[1][0]*v.y + m.m[2][0]*v.z;
    float y = m.m[0][1]*v.x + m.m[1][1]*v.y + m.m[2][1]*v.z;
    float z = m.m[0][2]*v.x + m.m[1][2]*v.y + m.m[2][2]*v.z;
    return { x, y, z };
}

inline Vec3 operator*(const Mat4& m, const Vec3& p) { return transformPoint(m, p); }

inline float determinant(const Mat4& a) {
    const float a00 = a.m[0][0], a01 = a.m[0][1], a02 = a.m[0][2], a03 = a.m[0][3];
    const float a10 = a.m[1][0], a11 = a.m[1][1], a12 = a.m[1][2], a13 = a.m[1][3];
    const float a20 = a.m[2][0], a21 = a.m[2][1], a22 = a.m[2][2], a23 = a.m[2][3];
    const float a30 = a.m[3][0], a31 = a.m[3][1], a32 = a.m[3][2], a33 = a.m[3][3];

    const float b00 = a00 * a11 - a01 * a10;
    const float b01 = a00 * a12 - a02 * a10;
    const float b02 = a00 * a13 - a03 * a10;
    const float b03 = a01 * a12 - a02 * a11;
    const float b04 = a01 * a13 - a03 * a11;
    const float b05 = a02 * a13 - a03 * a12;
    const float b06 = a20 * a31 - a21 * a30;
    const float b07 = a20 * a32 - a22 * a30;
    const float b08 = a20 * a33 - a23 * a30;
    const float b09 = a21 * a32 - a22 * a31;
    const float b10 = a21 * a33 - a23 * a31;
    const float b11 = a22 * a33 - a23 * a32;

    return b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
}

inline Mat4 inverse(const Mat4& a) {
    const float a00 = a.m[0][0], a01 = a.m[0][1], a02 = a.m[0][2], a03 = a.m[0][3];
    const float a10 = a.m[1][0], a11 = a.m[1][1], a12 = a.m[1][2], a13 = a.m[1][3];
    const float a20 = a.m[2][0], a21 = a.m[2][1], a22 = a.m[2][2], a23 = a.m[2][3];
    const float a30 = a.m[3][0], a31 = a.m[3][1], a32 = a.m[3][2], a33 = a.m[3][3];

    const float b00 = a00 * a11 - a01 * a10;
    const float b01 = a00 * a12 - a02 * a10;
    const float b02 = a00 * a13 - a03 * a10;
    const float b03 = a01 * a12 - a02 * a11;
    const float b04 = a01 * a13 - a03 * a11;
    const float b05 = a02 * a13 - a03 * a12;
    const float b06 = a20 * a31 - a21 * a30;
    const float b07 = a20 * a32 - a22 * a30;
    const float b08 = a20 * a33 - a23 * a30;
    const float b09 = a21 * a32 - a22 * a31;
    const float b10 = a21 * a33 - a23 * a31;
    const float b11 = a22 * a33 - a23 * a32;

    const float det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
    Mat4 inv{};
    if (std::fabs(det) <= 0.0f) {
        return inv; // returns zero matrix if non-invertible
    }
    const float invDet = 1.0f / det;

    inv.m[0][0] = (+ a11 * b11 - a12 * b10 + a13 * b09) * invDet;
    inv.m[0][1] = (- a01 * b11 + a02 * b10 - a03 * b09) * invDet;
    inv.m[0][2] = (+ a31 * b05 - a32 * b04 + a33 * b03) * invDet;
    inv.m[0][3] = (- a21 * b05 + a22 * b04 - a23 * b03) * invDet;

    inv.m[1][0] = (- a10 * b11 + a12 * b08 - a13 * b07) * invDet;
    inv.m[1][1] = (+ a00 * b11 - a02 * b08 + a03 * b07) * invDet;
    inv.m[1][2] = (- a30 * b05 + a32 * b02 - a33 * b01) * invDet;
    inv.m[1][3] = (+ a20 * b05 - a22 * b02 + a23 * b01) * invDet;

    inv.m[2][0] = (+ a10 * b10 - a11 * b08 + a13 * b06) * invDet;
    inv.m[2][1] = (- a00 * b10 + a01 * b08 - a03 * b06) * invDet;
    inv.m[2][2] = (+ a30 * b04 - a31 * b02 + a33 * b00) * invDet;
    inv.m[2][3] = (- a20 * b04 + a21 * b02 - a23 * b00) * invDet;

    inv.m[3][0] = (- a10 * b09 + a11 * b07 - a12 * b06) * invDet;
    inv.m[3][1] = (+ a00 * b09 - a01 * b07 + a02 * b06) * invDet;
    inv.m[3][2] = (- a30 * b03 + a31 * b01 - a32 * b00) * invDet;
    inv.m[3][3] = (+ a20 * b03 - a21 * b01 + a22 * b00) * invDet;

    return inv;
}

inline Mat4 perspective(float fovyRad, float aspect, float zNear, float zFar) {
    // Right-handed, Metal-style clip space z in [0, 1]
    const float f = 1.0f / std::tan(fovyRad * 0.5f);

    Mat4 r{};
    r.m[0][0] = f / aspect;
    r.m[1][1] = f;

    // RH, z_view is negative in front of camera (with lookAt as implemented)
    r.m[2][2] = zFar / (zNear - zFar);
    r.m[2][3] = -1.0f;
    r.m[3][2] = (zFar * zNear) / (zNear - zFar);

    return r;
}

inline Mat4 lookAt(const Vec3& eye, const Vec3& center, const Vec3& up) {
    // Right-handed lookAt
    const Vec3 fwd = normalize(center - eye);
    const Vec3 right = normalize(cross(fwd, up));
    const Vec3 u = cross(right, fwd);

    Mat4 r = identity();
    r.m[0][0] = right.x; r.m[0][1] = u.x; r.m[0][2] = -fwd.x;
    r.m[1][0] = right.y; r.m[1][1] = u.y; r.m[1][2] = -fwd.y;
    r.m[2][0] = right.z; r.m[2][1] = u.z; r.m[2][2] = -fwd.z;

    r.m[3][0] = -dot(right, eye);
    r.m[3][1] = -dot(u, eye);
    r.m[3][2] = dot(fwd, eye);
    return r;
}

} // namespace coremath


