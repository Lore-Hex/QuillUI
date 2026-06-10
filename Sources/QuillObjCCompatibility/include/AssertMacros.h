#ifndef QUILL_OBJC_ASSERTMACROS_H
#define QUILL_OBJC_ASSERTMACROS_H

#ifndef QUILL_ASSERT_CONCAT_INNER
#define QUILL_ASSERT_CONCAT_INNER(lhs, rhs) lhs##rhs
#endif

#ifndef QUILL_ASSERT_CONCAT
#define QUILL_ASSERT_CONCAT(lhs, rhs) QUILL_ASSERT_CONCAT_INNER(lhs, rhs)
#endif

#ifndef __Check_Compile_Time
#define __Check_Compile_Time(expression) \
    typedef char QUILL_ASSERT_CONCAT(__quill_compile_time_assert_, __LINE__)[(expression) ? 1 : -1]
#endif

#ifndef check
#define check(assertion) do { (void)sizeof(assertion); } while (0)
#endif

#ifndef require
#define require(assertion, exceptionLabel) do { if (!(assertion)) { goto exceptionLabel; } } while (0)
#endif

#ifndef require_action
#define require_action(assertion, exceptionLabel, action) do { if (!(assertion)) { action; goto exceptionLabel; } } while (0)
#endif

#ifndef require_noerr
#define require_noerr(errorCode, exceptionLabel) do { if ((errorCode) != 0) { goto exceptionLabel; } } while (0)
#endif

#ifndef require_noerr_action
#define require_noerr_action(errorCode, exceptionLabel, action) do { if ((errorCode) != 0) { action; goto exceptionLabel; } } while (0)
#endif

#endif
