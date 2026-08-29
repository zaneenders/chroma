#ifndef CHROMA_WAYLAND_SUPPORT_H
#define CHROMA_WAYLAND_SUPPORT_H

#include <stddef.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Writes to a pipe without allowing a closed reader to terminate the process. */
ssize_t chroma_write_no_sigpipe(int fd, const void *buffer, size_t count);

#ifdef __cplusplus
}
#endif

#endif
