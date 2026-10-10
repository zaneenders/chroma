#ifndef ALLOCATION_COUNTER_H
#define ALLOCATION_COUNTER_H

#include <stdint.h>

typedef struct {
    uint64_t malloc_calls;
    uint64_t calloc_calls;
    uint64_t realloc_calls;
    uint64_t aligned_alloc_calls;
    uint64_t posix_memalign_calls;
    uint64_t free_calls;
} allocation_counts;

/* Current thread only. start resets and enables; stop disables; read is passive.
 * Call outside signal handlers, and do not nest measured regions. */
void allocation_counter_start(void);
void allocation_counter_stop(void);
allocation_counts allocation_counter_read(void);
/* 0=malloc, 1=calloc, 2=realloc, 3=aligned_alloc, 4=posix_memalign, 5=free.
 * An out-of-range index returns 0. Suitable for a primitive dlsym function ABI. */
uint64_t allocation_counter_value(unsigned index);

#endif
