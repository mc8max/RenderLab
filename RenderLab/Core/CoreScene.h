//
//  CoreScene.h
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 1/3/26.
//

#pragma once
#include <cstdint>
#include "CoreMath.hpp"

struct CoreTransform {
    coremath::Vec3 position {0, 0, 0};
    coremath::Vec3 rotation {0, 0, 0};
    coremath::Vec3 scale {1, 1, 1};
};

coremath::Mat4 CoreTransform_toMat4(const CoreTransform& t);

using CoreObjectID = uint32_t;
using CoreMeshID = uint32_t;
using CoreMaterialID = uint32_t;

struct CoreSceneObject {
    CoreObjectID oID;
    CoreMeshID meshID;
    CoreMaterialID materialID;
    CoreTransform t;
    uint32_t visible; // 0 or 1 (C-Friendly)
};

struct CoreScene {
    CoreSceneObject* objects = nullptr;
    uint32_t count = 0;
    uint32_t capacity = 0;
};

// functions()
void CoreScene_init(CoreScene* scene, uint32_t capacity);
void CoreScene_shutdown(CoreScene* scene);
CoreObjectID CoreScene_add(CoreScene* scene, CoreMeshID meshID, CoreMaterialID materialID);
CoreSceneObject CoreScene_find(CoreScene* scene, CoreObjectID objectID);
CoreSceneObject* CoreScene_findMutable(CoreScene* scene, CoreObjectID objectID);
const CoreSceneObject* CoreScene_findConst(const CoreScene* scene, CoreObjectID objectID);
