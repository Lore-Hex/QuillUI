#ifndef QUILL_OBJC_COMPATIBILITY_PRELUDE_H
#define QUILL_OBJC_COMPATIBILITY_PRELUDE_H

#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#include <string.h>
#ifdef __OBJC__
#include <AppKit/AppKit.h>
#include <ImageIO/ImageIO.h>
#include <CoreVideo/CoreVideo.h>
#include <AVFoundation/AVFoundation.h>
#include <Security/Security.h>
#endif

#ifdef __cplusplus
#include <algorithm>
#include <string>
#include <vector>
#include <pthread.h>
#include <wchar.h>
#endif

#endif
