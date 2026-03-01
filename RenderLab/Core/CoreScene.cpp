//
//  CoreScene.cpp
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 1/3/26.
//

#include "CoreScene.h"

namespace {
CoreSceneObject makeInvalidObject() {
    CoreSceneObject object{};
    object.visible = 0;
    return object;
}

void reserve(CoreScene* scene, uint32_t newCapacity) {
    if (!scene || newCapacity <= scene->capacity) return;

    CoreSceneObject* newObjects = new CoreSceneObject[newCapacity];
    for (uint32_t i = 0; i < scene->count; ++i) {
        newObjects[i] = scene->objects[i];
    }

    delete[] scene->objects;
    scene->objects = newObjects;
    scene->capacity = newCapacity;
}
} // namespace

coremath::Mat4 CoreTransform_toMat4(const CoreTransform& t) {
    using namespace coremath;
    const Mat4 translationM = translation(t.position);
    const Mat4 rotationM = rotationZ(t.rotation.z) * rotationY(t.rotation.y) * rotationX(t.rotation.x);
    const Mat4 scaleM = scale(t.scale);
    return translationM * rotationM * scaleM;
}

void CoreScene_init(CoreScene* scene, uint32_t capacity) {
    if (!scene) return;

    scene->objects = nullptr;
    scene->count = 0;
    scene->capacity = 0;

    if (capacity == 0) return;
    reserve(scene, capacity);
}

void CoreScene_shutdown(CoreScene* scene) {
    if (!scene) return;
    delete[] scene->objects;
    scene->objects = nullptr;
    scene->count = 0;
    scene->capacity = 0;
}

CoreObjectID CoreScene_add(CoreScene* scene, CoreMeshID meshID, CoreMaterialID materialID) {
    if (!scene) return 0;
    if (scene->count == UINT32_MAX) return 0;

    if (scene->count >= scene->capacity) {
        const uint32_t newCapacity = (scene->capacity == 0u) ? 1u : scene->capacity * 2u;
        if (newCapacity <= scene->capacity) return 0;
        reserve(scene, newCapacity);
    }

    const CoreObjectID objectID = scene->count + 1u;

    CoreSceneObject object{};
    object.oID = objectID;
    object.meshID = meshID;
    object.materialID = materialID;
    object.t = CoreTransform{};
    object.visible = 1;

    scene->objects[scene->count] = object;
    ++scene->count;
    return objectID;
}

CoreSceneObject CoreScene_find(CoreScene* scene, CoreObjectID objectID) {
    const CoreSceneObject* object = CoreScene_findConst(scene, objectID);
    if (!object) return makeInvalidObject();
    return *object;
}

CoreSceneObject* CoreScene_findMutable(CoreScene* scene, CoreObjectID objectID) {
    if (!scene || objectID == 0) return nullptr;
    for (uint32_t i = 0; i < scene->count; ++i) {
        if (scene->objects[i].oID == objectID) {
            return &scene->objects[i];
        }
    }
    return nullptr;
}

const CoreSceneObject* CoreScene_findConst(const CoreScene* scene, CoreObjectID objectID) {
    if (!scene || objectID == 0) return nullptr;
    for (uint32_t i = 0; i < scene->count; ++i) {
        if (scene->objects[i].oID == objectID) {
            return &scene->objects[i];
        }
    }
    return nullptr;
}
