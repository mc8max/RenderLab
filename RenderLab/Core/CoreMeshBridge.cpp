//
//  CoreMeshBridge.cpp
//  RenderLab
//
//  C bridge mesh generation and release APIs.
//

#include "CoreBridge.h"

void coreMakeTriangle(CoreVertex** outVertices, int32_t* outVertexCount,
                      uint16_t** outIndices, int32_t* outIndexCount) {
    if (!outVertices || !outVertexCount || !outIndices || !outIndexCount) return;

    *outVertexCount = 3;
    *outIndexCount = 3;

    CoreVertex* v = new CoreVertex[*outVertexCount];
    uint16_t* i = new uint16_t[*outIndexCount];

    // CCW triangle in clip-friendly space
    v[0] = {{-0.6f, -0.4f, 0.0f}, {1.0f, 0.2f, 0.2f}};
    v[1] = {{0.0f, 0.6f, 0.0f}, {0.2f, 1.0f, 0.2f}};
    v[2] = {{0.6f, -0.4f, 0.0f}, {0.2f, 0.4f, 1.0f}};

    i[0] = 0;
    i[1] = 1;
    i[2] = 2;

    *outVertices = v;
    *outIndices = i;
}

void coreMakeCube(CoreVertex** outVertices, int32_t* outVertexCount,
                  uint16_t** outIndices, int32_t* outIndexCount) {
    if (!outVertices || !outVertexCount || !outIndices || !outIndexCount) return;

    // 6 faces * 4 verts each = 24 (duplicate corners per face is intentional)
    *outVertexCount = 24;
    *outIndexCount = 36; // 6 faces * 2 tris * 3

    CoreVertex* v = new CoreVertex[*outVertexCount];
    uint16_t* i = new uint16_t[*outIndexCount];

    const float s = 0.5f;

    // Face colors (easy to debug)
    const float red[3] = {1.0f, 0.2f, 0.2f};
    const float green[3] = {0.2f, 1.0f, 0.2f};
    const float blue[3] = {0.2f, 0.4f, 1.0f};
    const float yellow[3] = {1.0f, 1.0f, 0.2f};
    const float mag[3] = {1.0f, 0.2f, 1.0f};
    const float cyan[3] = {0.2f, 1.0f, 1.0f};

    auto setV = [&](int idx, float x, float y, float z, const float c[3]) {
        v[idx].position[0] = x;
        v[idx].position[1] = y;
        v[idx].position[2] = z;
        v[idx].color[0] = c[0];
        v[idx].color[1] = c[1];
        v[idx].color[2] = c[2];
    };

    // Indices below assume CCW winding when viewed from outside the cube.
    // Face 0: +Z (front) - cyan
    setV(0, -s, -s, s, cyan);
    setV(1, s, -s, s, cyan);
    setV(2, s, s, s, cyan);
    setV(3, -s, s, s, cyan);

    // Face 1: -Z (back) - red
    setV(4, s, -s, -s, red);
    setV(5, -s, -s, -s, red);
    setV(6, -s, s, -s, red);
    setV(7, s, s, -s, red);

    // Face 2: -X (left) - green
    setV(8, -s, -s, -s, green);
    setV(9, -s, -s, s, green);
    setV(10, -s, s, s, green);
    setV(11, -s, s, -s, green);

    // Face 3: +X (right) - blue
    setV(12, s, -s, s, blue);
    setV(13, s, -s, -s, blue);
    setV(14, s, s, -s, blue);
    setV(15, s, s, s, blue);

    // Face 4: +Y (top) - yellow
    setV(16, -s, s, s, yellow);
    setV(17, s, s, s, yellow);
    setV(18, s, s, -s, yellow);
    setV(19, -s, s, -s, yellow);

    // Face 5: -Y (bottom) - magenta
    setV(20, -s, -s, -s, mag);
    setV(21, s, -s, -s, mag);
    setV(22, s, -s, s, mag);
    setV(23, -s, -s, s, mag);

    uint16_t idx[36] = {
        // +Z
        0, 1, 2, 0, 2, 3,
        // -Z
        4, 5, 6, 4, 6, 7,
        // -X
        8, 9, 10, 8, 10, 11,
        // +X
        12, 13, 14, 12, 14, 15,
        // +Y
        16, 17, 18, 16, 18, 19,
        // -Y
        20, 21, 22, 20, 22, 23};

    for (int k = 0; k < 36; ++k) i[k] = idx[k];

    *outVertices = v;
    *outIndices = i;
}

void coreFreeMesh(CoreVertex* vertices, uint16_t* indices) {
    delete[] vertices;
    delete[] indices;
}
