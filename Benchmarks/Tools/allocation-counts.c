// Linux/glibc-only, process-wide call/requested-byte counts, not live heap size.
// Run separately from timings: cc -O2 -shared -fPIC -o allocation-counts.so allocation-counts.c
// LD_PRELOAD="$PWD/allocation-counts.so" ./LayoutBenchmark > result.json 2> allocation.json
#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void *__libc_memalign(size_t, size_t);
extern void __libc_free(void *);

enum { MALLOC, CALLOC, REALLOC, ALIGNED, KINDS };
static _Atomic unsigned long long calls[KINDS], requested[KINDS];
static void record(int kind, size_t size) {
  atomic_fetch_add_explicit(&calls[kind], 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&requested[kind], size, memory_order_relaxed);
}
void *malloc(size_t size) { record(MALLOC, size); return __libc_malloc(size); }
void *calloc(size_t n, size_t size) {
  record(CALLOC, n <= SIZE_MAX / (size ? size : 1) ? n * size : 0);
  return __libc_calloc(n, size);
}
void *realloc(void *p, size_t size) { record(REALLOC, size); return __libc_realloc(p, size); }
void free(void *p) { __libc_free(p); }
void *aligned_alloc(size_t align, size_t size) {
  record(ALIGNED, size); return __libc_memalign(align, size);
}
void *memalign(size_t align, size_t size) {
  record(ALIGNED, size); return __libc_memalign(align, size);
}
int posix_memalign(void **p, size_t align, size_t size) {
  if (align < sizeof(void *) || (align & (align - 1))) return EINVAL;
  record(ALIGNED, size);
  const int saved_errno = errno;
  void *result = __libc_memalign(align, size);
  errno = saved_errno;
  if (!result) return ENOMEM;
  *p = result;
  return 0;
}
__attribute__((destructor)) static void report(void) {
  unsigned long long c[KINDS], b[KINDS], total = 0, bytes = 0;
  for (int i = 0; i < KINDS; ++i) {
    c[i] = atomic_load_explicit(&calls[i], memory_order_relaxed);
    b[i] = atomic_load_explicit(&requested[i], memory_order_relaxed);
    total += c[i]; bytes += b[i];
  }
  char output[512];
  int size = snprintf(output, sizeof output,
    "{\"malloc\":%llu,\"calloc\":%llu,\"realloc\":%llu,\"aligned\":%llu,\"total_calls\":%llu,\"requested_bytes\":%llu}\n",
    c[MALLOC], c[CALLOC], c[REALLOC], c[ALIGNED], total, bytes);
  if (size > 0 && size < (int) sizeof output) (void)write(STDERR_FILENO, output, (size_t)size);
}
