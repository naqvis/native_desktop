#include <objc/message.h>
#include <objc/runtime.h>

extern void *objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void *pool);

void *native_desktop_objc_get_class(const char *name) {
    return (void *)objc_getClass(name);
}

void *native_desktop_objc_selector(const char *name) {
    return sel_registerName(name);
}

void *native_desktop_objc_message_send(void) {
    return (void *)objc_msgSend;
}

void *native_desktop_objc_pool_push(void) {
    return objc_autoreleasePoolPush();
}

void native_desktop_objc_pool_pop(void *pool) {
    objc_autoreleasePoolPop(pool);
}

void *native_desktop_objc_allocate_class_pair(void *superclass, const char *name, size_t extra_bytes) {
    return objc_allocateClassPair((Class)superclass, name, extra_bytes);
}

void native_desktop_objc_register_class_pair(void *cls) {
    objc_registerClassPair((Class)cls);
}

signed char native_desktop_objc_add_method(void *cls, void *selector, void *implementation, const char *types) {
    return class_addMethod((Class)cls, (SEL)selector, (IMP)implementation, types);
}

void *native_desktop_objc_object_get_class(void *object) {
    return object_getClass((id)object);
}

void *native_desktop_objc_object_set_class(void *object, void *cls) {
    return object_setClass((id)object, (Class)cls);
}
