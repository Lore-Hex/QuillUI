#ifndef QUILL_OBJC_OPENGL_GL_H
#define QUILL_OBJC_OPENGL_GL_H

#include <stdint.h>
#include <stddef.h>

typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef void GLvoid;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef float GLclampf;
typedef double GLdouble;
typedef char GLchar;

typedef uint32_t CGDirectDisplayID;
typedef uint32_t CGOpenGLDisplayMask;
typedef int CGLPixelFormatAttribute;
typedef void *CGLPixelFormatObj;
typedef void *CGLContextObj;

enum {
    GL_FALSE = 0,
    GL_TRUE = 1,
    GL_VERTEX_SHADER = 0x8B31,
    GL_FRAGMENT_SHADER = 0x8B30,
    GL_INFO_LOG_LENGTH = 0x8B84,
    GL_COMPILE_STATUS = 0x8B81,
    GL_LINK_STATUS = 0x8B82,
    GL_FRAMEBUFFER = 0x8D40,
    GL_COLOR_ATTACHMENT0 = 0x8CE0,
    GL_TEXTURE_2D = 0x0DE1,
    GL_TEXTURE0 = 0x84C0,
    GL_TEXTURE2 = 0x84C2,
    GL_TEXTURE_MIN_FILTER = 0x2801,
    GL_TEXTURE_MAG_FILTER = 0x2800,
    GL_TEXTURE_WRAP_S = 0x2802,
    GL_TEXTURE_WRAP_T = 0x2803,
    GL_LINEAR = 0x2601,
    GL_CLAMP_TO_EDGE = 0x812F,
    GL_UNPACK_ROW_LENGTH = 0x0CF2,
    GL_RGBA = 0x1908,
    GL_BGRA = 0x80E1,
    GL_UNSIGNED_BYTE = 0x1401,
    GL_FLOAT = 0x1406,
    GL_TRIANGLE_STRIP = 0x0005,
    GL_DEPTH_TEST = 0x0B71,
};

enum {
    kCGLPFAColorSize = 8,
    kCGLPFAAlphaSize = 11,
    kCGLPFAAccelerated = 73,
    kCGLPFADoubleBuffer = 5,
    kCGLPFASampleBuffers = 55,
    kCGLPFASamples = 56,
    kCGLPFAAllowOfflineRenderers = 96,
};

static inline CGDirectDisplayID CGMainDisplayID(void) { return 0; }
static inline CGOpenGLDisplayMask CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID display) { (void)display; return 0; }

static inline int CGLChoosePixelFormat(const CGLPixelFormatAttribute *attributes, CGLPixelFormatObj *pixelFormat, GLint *numberOfPixelFormats) {
    (void)attributes;
    if (pixelFormat != NULL) {
        *pixelFormat = (CGLPixelFormatObj)1;
    }
    if (numberOfPixelFormats != NULL) {
        *numberOfPixelFormats = 1;
    }
    return 0;
}

static inline int CGLCreateContext(CGLPixelFormatObj pixelFormat, CGLContextObj share, CGLContextObj *context) {
    (void)pixelFormat;
    (void)share;
    if (context != NULL) {
        *context = (CGLContextObj)1;
    }
    return 0;
}

static inline void CGLDestroyPixelFormat(CGLPixelFormatObj pixelFormat) { (void)pixelFormat; }
static inline int CGLSetCurrentContext(CGLContextObj context) { (void)context; return 0; }
static inline CGLContextObj CGLGetCurrentContext(void) { return NULL; }
static inline CGLContextObj CGLRetainContext(CGLContextObj context) { return context; }
static inline void CGLReleaseContext(CGLContextObj context) { (void)context; }
static inline int CGLLockContext(CGLContextObj context) { (void)context; return 0; }
static inline int CGLUnlockContext(CGLContextObj context) { (void)context; return 0; }
static inline CGLPixelFormatObj CGLGetPixelFormat(CGLContextObj context) { (void)context; return NULL; }

static inline GLuint glCreateProgram(void) { return 1; }
static inline GLuint glCreateShader(GLenum type) { (void)type; return 1; }
static inline void glShaderSource(GLuint shader, GLsizei count, const GLchar **string, const GLint *length) { (void)shader; (void)count; (void)string; (void)length; }
static inline void glCompileShader(GLuint shader) { (void)shader; }
static inline void glGetShaderiv(GLuint shader, GLenum pname, GLint *params) { (void)shader; (void)pname; if (params != NULL) { *params = GL_TRUE; } }
static inline void glGetShaderInfoLog(GLuint shader, GLsizei maxLength, GLsizei *length, GLchar *infoLog) {
    (void)shader;
    if (length != NULL) { *length = 0; }
    if (maxLength > 0 && infoLog != NULL) { infoLog[0] = '\0'; }
}
static inline void glAttachShader(GLuint program, GLuint shader) { (void)program; (void)shader; }
static inline void glBindAttribLocation(GLuint program, GLuint index, const GLchar *name) { (void)program; (void)index; (void)name; }
static inline void glLinkProgram(GLuint program) { (void)program; }
static inline void glGetProgramiv(GLuint program, GLenum pname, GLint *params) { (void)program; (void)pname; if (params != NULL) { *params = GL_TRUE; } }
static inline void glGetProgramInfoLog(GLuint program, GLsizei maxLength, GLsizei *length, GLchar *infoLog) {
    (void)program;
    if (length != NULL) { *length = 0; }
    if (maxLength > 0 && infoLog != NULL) { infoLog[0] = '\0'; }
}
static inline GLint glGetUniformLocation(GLuint program, const GLchar *name) { (void)program; (void)name; return 0; }
static inline void glDeleteShader(GLuint shader) { (void)shader; }
static inline void glDeleteProgram(GLuint program) { (void)program; }
static inline void glBindFramebuffer(GLenum target, GLuint framebuffer) { (void)target; (void)framebuffer; }
static inline void glViewport(GLint x, GLint y, GLsizei width, GLsizei height) { (void)x; (void)y; (void)width; (void)height; }
static inline void glUseProgram(GLuint program) { (void)program; }
static inline void glActiveTexture(GLenum texture) { (void)texture; }
static inline void glBindTexture(GLenum target, GLuint texture) { (void)target; (void)texture; }
static inline void glTexParameteri(GLenum target, GLenum pname, GLint param) { (void)target; (void)pname; (void)param; }
static inline void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) { (void)target; (void)attachment; (void)textarget; (void)texture; (void)level; }
static inline void glPixelStorei(GLenum pname, GLint param) { (void)pname; (void)param; }
static inline void glTexImage2D(GLenum target, GLint level, GLint internalFormat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid *pixels) {
    (void)target; (void)level; (void)internalFormat; (void)width; (void)height; (void)border; (void)format; (void)type; (void)pixels;
}
static inline void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid *pointer) {
    (void)index; (void)size; (void)type; (void)normalized; (void)stride; (void)pointer;
}
static inline void glEnableVertexAttribArray(GLuint index) { (void)index; }
static inline void glUniform1i(GLint location, GLint v0) { (void)location; (void)v0; }
static inline void glUniform1f(GLint location, GLfloat v0) { (void)location; (void)v0; }
static inline void glDrawArrays(GLenum mode, GLint first, GLsizei count) { (void)mode; (void)first; (void)count; }
static inline void glFlush(void) {}
static inline void glDisable(GLenum cap) { (void)cap; }
static inline void glGenFramebuffers(GLsizei n, GLuint *framebuffers) {
    for (GLsizei index = 0; index < n; index++) {
        framebuffers[index] = (GLuint)(index + 1);
    }
}
static inline void glDeleteFramebuffers(GLsizei n, const GLuint *framebuffers) { (void)n; (void)framebuffers; }

#endif
