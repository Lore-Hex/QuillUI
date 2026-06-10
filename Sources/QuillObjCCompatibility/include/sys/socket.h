#ifndef QUILL_OBJC_SYS_SOCKET_H
#define QUILL_OBJC_SYS_SOCKET_H

#include_next <sys/socket.h>

#ifndef SO_NOSIGPIPE
#define SO_NOSIGPIPE 0x1022
#endif

#if defined(__linux__) && !defined(sin_len)
#define sin_len sin_zero[0]
#endif

#if defined(__linux__) && !defined(sin6_len)
#define sin6_len sin6_flowinfo
#endif

#endif
