#define _GNU_SOURCE
#include "allocation_counter.h"
#include <dlfcn.h>
#include <errno.h>
#include <stddef.h>
#include <unistd.h>

/* Deliberately glibc-only: these entry points avoid dlsym/malloc recursion. */
extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void *__libc_memalign(size_t, size_t);
extern void __libc_free(void *);

/* Static TLS: touching the counter never requires a dynamic TLS allocation.
 * The preload must be loaded at startup; do not dlopen it after threads start. */
static __thread allocation_counts counts __attribute__((tls_model("initial-exec")));
static __thread unsigned enabled __attribute__((tls_model("initial-exec")));
static __thread unsigned depth __attribute__((tls_model("initial-exec")));
static void *(*real_aligned_alloc)(size_t, size_t);
static int (*real_posix_memalign)(void **, size_t, size_t);

__attribute__((constructor)) static void resolve_aligned_functions(void) {
    real_aligned_alloc = (void *(*)(size_t, size_t))dlsym(RTLD_NEXT, "aligned_alloc");
    real_posix_memalign = (int (*)(void **, size_t, size_t))dlsym(RTLD_NEXT, "posix_memalign");
    if (!real_aligned_alloc || !real_posix_memalign) _exit(127);
}

void allocation_counter_start(void) {
    enabled = 0;
    counts = (allocation_counts){0};
    enabled = 1;
}
void allocation_counter_stop(void) { enabled = 0; }
allocation_counts allocation_counter_read(void) { return counts; }
uint64_t allocation_counter_value(unsigned index) {
    switch (index) {
        case 0: return counts.malloc_calls;
        case 1: return counts.calloc_calls;
        case 2: return counts.realloc_calls;
        case 3: return counts.aligned_alloc_calls;
        case 4: return counts.posix_memalign_calls;
        case 5: return counts.free_calls;
        default: return 0;
    }
}

/* Count outermost intercepted calls, including failed calls and free(NULL).
 * Suppress nested calls made by an intercepted allocator's implementation. */
#define ENTER(field) do { if (enabled && depth == 0) ++counts.field; ++depth; } while (0)
#define LEAVE() (--depth)

void *malloc(size_t size) {
    ENTER(malloc_calls);
    void *p = __libc_malloc(size);
    LEAVE();
    return p;
}
void *calloc(size_t n, size_t size) {
    ENTER(calloc_calls);
    void *p = __libc_calloc(n, size);
    LEAVE();
    return p;
}
void *realloc(void *old, size_t size) {
    ENTER(realloc_calls);
    void *p = __libc_realloc(old, size);
    LEAVE();
    return p;
}
void free(void *p) {
    ENTER(free_calls);
    __libc_free(p);
    LEAVE();
}
void *aligned_alloc(size_t alignment, size_t size) {
    ENTER(aligned_alloc_calls);
    void *p;
    if (real_aligned_alloc) {
        p = real_aligned_alloc(alignment, size);
    } else if (alignment == 0 || (alignment & (alignment - 1)) != 0) {
        /* Only an early-loader fallback before our constructor has run. */
        errno = EINVAL;
        p = NULL;
    } else {
        p = __libc_memalign(alignment, size);
    }
    LEAVE();
    return p;
}
int posix_memalign(void **out, size_t alignment, size_t size) {
    ENTER(posix_memalign_calls);
    int result;
    if (real_posix_memalign) {
        result = real_posix_memalign(out, alignment, size);
    } else if (alignment < sizeof(void *) || (alignment & (alignment - 1)) != 0) {
        result = EINVAL;
    } else {
        int saved_errno = errno;
        void *p = __libc_memalign(alignment, size);
        result = p ? 0 : ENOMEM;
        if (p) *out = p;
        errno = saved_errno;
    }
    LEAVE();
    return result;
}
