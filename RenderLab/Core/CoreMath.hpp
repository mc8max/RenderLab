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
