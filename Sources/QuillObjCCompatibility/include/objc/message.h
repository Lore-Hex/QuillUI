#ifndef QUILL_OBJC_MESSAGE_H
#define QUILL_OBJC_MESSAGE_H

#include <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

id objc_msgSend(id self, SEL op, ...);

#ifdef __cplusplus
}
#endif

#endif
