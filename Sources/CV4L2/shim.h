/* CV4L2 — [system] C shim over the Video4Linux2 kernel UAPI (#515).
 *
 * Swift cannot call variadic ioctl(2), and the VIDIOC_* request codes are
 * function-like macros (_IOR/_IOW/_IOWR expansions) that the Clang importer
 * does not surface. Each capture ioctl the QuillV4L2Camera backend needs is
 * therefore wrapped in a named, non-variadic static-inline function. Every
 * wrapper retries on EINTR and returns the raw ioctl result: 0 on success,
 * -1 with errno set on failure.
 *
 * Self-contained on purpose: only kernel/libc headers, no QuillUI headers.
 */

#ifndef QUILL_CV4L2_SHIM_H
#define QUILL_CV4L2_SHIM_H

#ifdef __linux__

#include <errno.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>

static inline int quill_v4l2_ioctl_retry(int fd, unsigned long request, void *argument) {
    int result;
    do {
        result = ioctl(fd, request, argument);
    } while (result == -1 && errno == EINTR);
    return result;
}

/* VIDIOC_QUERYCAP — driver/card identity + capability bits. */
static inline int quill_v4l2_querycap(int fd, struct v4l2_capability *capability) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_QUERYCAP, capability);
}

/* VIDIOC_ENUM_FMT — enumerate pixel formats (caller sets .type and bumps .index). */
static inline int quill_v4l2_enum_fmt(int fd, struct v4l2_fmtdesc *format_description) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_ENUM_FMT, format_description);
}

/* VIDIOC_ENUM_FRAMESIZES — enumerate frame sizes for one pixel format. */
static inline int quill_v4l2_enum_framesizes(int fd, struct v4l2_frmsizeenum *frame_size) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_ENUM_FRAMESIZES, frame_size);
}

/* VIDIOC_S_FMT — request a capture format; the driver may adjust it in place. */
static inline int quill_v4l2_s_fmt(int fd, struct v4l2_format *format) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_S_FMT, format);
}

/* VIDIOC_G_FMT — read back the format the driver actually granted. */
static inline int quill_v4l2_g_fmt(int fd, struct v4l2_format *format) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_G_FMT, format);
}

/* VIDIOC_S_PARM — request a frame interval (best effort across drivers). */
static inline int quill_v4l2_s_parm(int fd, struct v4l2_streamparm *stream_parameters) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_S_PARM, stream_parameters);
}

/* VIDIOC_REQBUFS — allocate the kernel's mmap buffer ring. */
static inline int quill_v4l2_reqbufs(int fd, struct v4l2_requestbuffers *request_buffers) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_REQBUFS, request_buffers);
}

/* VIDIOC_QUERYBUF — fetch one ring buffer's mmap offset + length. */
static inline int quill_v4l2_querybuf(int fd, struct v4l2_buffer *buffer) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_QUERYBUF, buffer);
}

/* VIDIOC_QBUF — hand a buffer (back) to the driver for filling. */
static inline int quill_v4l2_qbuf(int fd, struct v4l2_buffer *buffer) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_QBUF, buffer);
}

/* VIDIOC_DQBUF — dequeue a filled buffer (EAGAIN when none ready on O_NONBLOCK fds). */
static inline int quill_v4l2_dqbuf(int fd, struct v4l2_buffer *buffer) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_DQBUF, buffer);
}

/* VIDIOC_STREAMON — start streaming I/O; *buffer_type is a v4l2_buf_type value. */
static inline int quill_v4l2_streamon(int fd, const int *buffer_type) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_STREAMON, (void *)buffer_type);
}

/* VIDIOC_STREAMOFF — stop streaming and dequeue everything in flight. */
static inline int quill_v4l2_streamoff(int fd, const int *buffer_type) {
    return quill_v4l2_ioctl_retry(fd, VIDIOC_STREAMOFF, (void *)buffer_type);
}

#endif /* __linux__ */

#endif /* QUILL_CV4L2_SHIM_H */
