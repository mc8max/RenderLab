//
//  CoreSceneBridge.cpp
//  RenderLab
//
//  C bridge scene ownership and object operations.
//

#include "CoreBridge.h"
#include "CoreScene.h"
#include <new>

struct CoreSceneHandle {
    CoreScene scene;
};

namespace {
CoreSceneTransform toBridgeTransform(const CoreTransform& t) {
    CoreSceneTransform out{};
    out.position[0] = t.position.x;
    out.position[1] = t.position.y;
    out.position[2] = t.position.z;
    out.rotation[0] = t.rotation.x;
    out.rotation[1] = t.rotation.y;
    out.rotation[2] = t.rotation.z;
    out.scale[0] = t.scale.x;
    out.scale[1] = t.scale.y;
    out.scale[2] = t.scale.z;
    return out;
}

CoreTransform fromBridgeTransform(const CoreSceneTransform& t) {
    CoreTransform out{};
    out.position = {t.position[0], t.position[1], t.position[2]};
    out.rotation = {t.rotation[0], t.rotation[1], t.rotation[2]};
    out.scale = {t.scale[0], t.scale[1], t.scale[2]};
    return out;
}

void fillBridgeObjectData(const CoreSceneObject& object, CoreSceneObjectData* outObject) {
    if (!outObject) return;
    outObject->objectID = object.oID;
    outObject->meshID = object.meshID;
    outObject->materialID = object.materialID;
    outObject->transform = toBridgeTransform(object.t);
    outObject->visible = object.visible;
}
} // namespace

CoreSceneHandle* coreSceneCreate(uint32_t initialCapacity) {
    CoreSceneHandle* handle = new (std::nothrow) CoreSceneHandle{};
    if (!handle) return nullptr;
    CoreScene_init(&handle->scene, initialCapacity);
    return handle;
}

void coreSceneDestroy(CoreSceneHandle* scene) {
    if (!scene) return;
    CoreScene_shutdown(&scene->scene);
    delete scene;
}

uint32_t coreSceneAdd(CoreSceneHandle* scene, uint32_t meshID, uint32_t materialID) {
    if (!scene) return 0;
    return CoreScene_add(&scene->scene, meshID, materialID);
}

uint32_t coreSceneCount(const CoreSceneHandle* scene) {
    if (!scene) return 0;
    return scene->scene.count;
}

int32_t coreSceneFind(const CoreSceneHandle* scene, uint32_t objectID, CoreSceneObjectData* outObject) {
    if (!scene || !outObject) return 0;
    const CoreSceneObject* object = CoreScene_findConst(&scene->scene, objectID);
    if (!object) return 0;

    fillBridgeObjectData(*object, outObject);
    return 1;
}

int32_t coreSceneGetByIndex(const CoreSceneHandle* scene, uint32_t index, CoreSceneObjectData* outObject) {
    if (!scene || !outObject) return 0;
    if (index >= scene->scene.count) return 0;

    fillBridgeObjectData(scene->scene.objects[index], outObject);
    return 1;
}

int32_t coreSceneSetTransform(CoreSceneHandle* scene, uint32_t objectID, const CoreSceneTransform* transform) {
    if (!scene || !transform) return 0;
    CoreSceneObject* object = CoreScene_findMutable(&scene->scene, objectID);
    if (!object) return 0;

    object->t = fromBridgeTransform(*transform);
    return 1;
}

int32_t coreSceneSetVisible(CoreSceneHandle* scene, uint32_t objectID, uint32_t visible) {
    if (!scene) return 0;
    CoreSceneObject* object = CoreScene_findMutable(&scene->scene, objectID);
    if (!object) return 0;

    object->visible = visible ? 1u : 0u;
    return 1;
}
