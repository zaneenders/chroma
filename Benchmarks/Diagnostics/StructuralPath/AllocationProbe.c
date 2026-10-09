// Linux/glibc diagnostic interposer. Never preload this into a timing run.
// Counts intercepted calls, not every ARC operation (e.g. runtime-internal calls
// and retain_n/release_n are outside this boundary). Bytes are requested bytes,
// including realloc requests, not peak or resident memory. Startup is included.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);

static _Atomic uint64_t mallocs, callocs, reallocs, bytes, retains, releases;

void *malloc(size_t size) {
  atomic_fetch_add_explicit(&mallocs, 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&bytes, size, memory_order_relaxed);
  return __libc_malloc(size);
}

void *calloc(size_t count, size_t size) {
  atomic_fetch_add_explicit(&callocs, 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&bytes, count * size, memory_order_relaxed);
  return __libc_calloc(count, size);
}

void *realloc(void *pointer, size_t size) {
  atomic_fetch_add_explicit(&reallocs, 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&bytes, size, memory_order_relaxed);
  return __libc_realloc(pointer, size);
}

typedef void *__attribute__((swiftcall)) (*RetainFunction)(void *);
typedef void __attribute__((swiftcall)) (*ReleaseFunction)(void *);

__attribute__((swiftcall)) void *swift_retain(void *pointer) {
  static _Atomic(RetainFunction) original;
  RetainFunction function = atomic_load_explicit(&original, memory_order_acquire);
  if (!function) {
    function = (RetainFunction)dlsym(RTLD_NEXT, "swift_retain");
    if (!function) _exit(127);
    atomic_store_explicit(&original, function, memory_order_release);
  }
  atomic_fetch_add_explicit(&retains, 1, memory_order_relaxed);
  return function(pointer);
}

__attribute__((swiftcall)) void swift_release(void *pointer) {
  static _Atomic(ReleaseFunction) original;
  ReleaseFunction function = atomic_load_explicit(&original, memory_order_acquire);
  if (!function) {
    function = (ReleaseFunction)dlsym(RTLD_NEXT, "swift_release");
    if (!function) _exit(127);
    atomic_store_explicit(&original, function, memory_order_release);
  }
  atomic_fetch_add_explicit(&releases, 1, memory_order_relaxed);
  function(pointer);
}

__attribute__((destructor)) static void report(void) {
  fprintf(stderr,
          "allocations: malloc=%lu calloc=%lu realloc=%lu requestedBytes=%lu "
          "swift_retain=%lu swift_release=%lu\n",
          mallocs, callocs, reallocs, bytes, retains, releases);
}
