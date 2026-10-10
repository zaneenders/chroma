#define _POSIX_C_SOURCE 200112L
#include "allocation_counter.h"
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

static void *background(void *unused) {
    (void)unused;
    allocation_counter_start();
    void *p = malloc(19);
    assert(p);
    free(p);
    allocation_counter_stop();
    allocation_counts c = allocation_counter_read();
    assert(c.malloc_calls == 1 && c.free_calls == 1);
    return NULL;
}

int main(void) {
    void *outside = malloc(7);
    assert(outside);
    free(outside);
    allocation_counter_start();
    void *a = malloc(17);
    void *b = calloc(3, 11);
    a = realloc(a, 91);
    void *c = aligned_alloc(64, 128);
    void *d = NULL;
    int result = posix_memalign(&d, 64, 137);
    assert(a && b && c && d && result == 0);
    free(a); free(b); free(c); free(d);
    allocation_counter_stop();
    allocation_counts n = allocation_counter_read();
    printf("C routes: malloc=%lu calloc=%lu realloc=%lu aligned_alloc=%lu posix_memalign=%lu free=%lu\n",
           n.malloc_calls, n.calloc_calls, n.realloc_calls,
           n.aligned_alloc_calls, n.posix_memalign_calls, n.free_calls);
    assert(n.malloc_calls == 1 && n.calloc_calls == 1 && n.realloc_calls == 1);
    assert(n.aligned_alloc_calls == 1 && n.posix_memalign_calls == 1 && n.free_calls == 4);
    for (unsigned i = 0; i < 5; ++i) assert(allocation_counter_value(i) == 1);
    assert(allocation_counter_value(5) == 4 && allocation_counter_value(6) == 0);
    /* Each thread owns its own window and counters. Thread creation is outside. */
    pthread_t thread;
    assert(pthread_create(&thread, NULL, background, NULL) == 0);
    assert(pthread_join(thread, NULL) == 0);
    n = allocation_counter_read();
    assert(n.malloc_calls == 1 && n.free_calls == 4);
    allocation_counter_start();
    allocation_counter_stop();
    n = allocation_counter_read();
    assert(n.malloc_calls == 0 && n.calloc_calls == 0 && n.realloc_calls == 0);
    assert(n.aligned_alloc_calls == 0 && n.posix_memalign_calls == 0 && n.free_calls == 0);
    puts("C gate/reset/thread-isolation checks passed");
}
