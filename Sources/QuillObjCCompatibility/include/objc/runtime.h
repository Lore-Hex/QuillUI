#ifndef QUILL_OBJC_RUNTIME_H
#define QUILL_OBJC_RUNTIME_H

#include <Foundation/Foundation.h>

typedef struct objc_object *id;
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef struct objc_property *objc_property_t;
typedef struct objc_method *Method;

struct objc_method_description {
    SEL name;
    char *types;
};

static inline const char *sel_getName(SEL selector) {
    (void)selector;
    return "";
}

static inline Class objc_lookUpClass(const char *name) {
    (void)name;
    return Nil;
}

static inline Method class_getClassMethod(Class cls, SEL name) {
    (void)cls;
    (void)name;
    return NULL;
}

static inline const char *method_getTypeEncoding(Method method) {
    (void)method;
    return NULL;
}

static inline struct objc_method_description protocol_getMethodDescription(
    Protocol *protocol,
    SEL selector,
    BOOL isRequiredMethod,
    BOOL isInstanceMethod
) {
    (void)protocol;
    (void)selector;
    (void)isRequiredMethod;
    (void)isInstanceMethod;
    struct objc_method_description description = { NULL, NULL };
    return description;
}

static inline objc_property_t *class_copyPropertyList(Class cls, unsigned int *outCount) {
    (void)cls;
    if (outCount != NULL) {
        *outCount = 0;
    }
    return NULL;
}

static inline const char *property_getName(objc_property_t property) {
    (void)property;
    return "";
}

#endif
