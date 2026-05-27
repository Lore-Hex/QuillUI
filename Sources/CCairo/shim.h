#if __has_include(<cairo.h>)
#include <cairo.h>
#elif __has_include(<cairo/cairo.h>)
#include <cairo/cairo.h>
#else
#error "Cairo headers not found. Install libcairo2-dev or cairo."
#endif
