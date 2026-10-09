// Linux user-CPU instruction-pointer sampler for a disposable benchmark process.
// Uses SIGVTALRM/ITIMER_VIRTUAL; do not preload into programs using that timer.
// Sampling and allocation interception are separate from release timing trials.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <ucontext.h>
#include <unistd.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2 && ATOMIC_LONG_LOCK_FREE == 2,
               "The signal handler requires lock-free counters and addresses");
#define CAPACITY 65536
static _Atomic unsigned count;
static _Atomic uintptr_t addresses[CAPACITY];

static void capture(int signal, siginfo_t *info, void *context) {
  (void)signal;
  (void)info;
  unsigned index = atomic_fetch_add_explicit(&count, 1, memory_order_relaxed);
  if (index >= CAPACITY) return;
#if defined(__x86_64__)
  uintptr_t address = (uintptr_t)((ucontext_t *)context)->uc_mcontext.gregs[REG_RIP];
#elif defined(__aarch64__)
  uintptr_t address = (uintptr_t)((ucontext_t *)context)->uc_mcontext.pc;
#else
#error Unsupported architecture
#endif
  atomic_store_explicit(&addresses[index], address, memory_order_relaxed);
}

__attribute__((constructor)) static void start(void) {
  struct sigaction action = {0};
  action.sa_sigaction = capture;
  action.sa_flags = SA_SIGINFO;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGVTALRM, &action, NULL) != 0) _exit(127);
  struct itimerval timer = {.it_interval = {0, 1000}, .it_value = {0, 1000}};
  if (setitimer(ITIMER_VIRTUAL, &timer, NULL) != 0) _exit(127);
}

__attribute__((destructor)) static void report(void) {
  struct itimerval timer = {0};
  setitimer(ITIMER_VIRTUAL, &timer, NULL);
  const char *path = getenv("CHROMA_CPU_SAMPLE_OUTPUT");
  if (!path) return;
  FILE *file = fopen(path, "w");
  if (!file) return;
  unsigned total = atomic_load_explicit(&count, memory_order_relaxed);
  unsigned recorded = total < CAPACITY ? total : CAPACITY;
  fprintf(stderr, "cpu samples: recorded=%u capacityDropped=%u\n", recorded, total - recorded);
  for (unsigned index = 0; index < recorded; index++) {
    uintptr_t address = atomic_load_explicit(&addresses[index], memory_order_relaxed);
    Dl_info info;
    if (dladdr((void *)address, &info) && info.dli_fname) {
      fprintf(file, "%s\t%lx\t%s\n", info.dli_fname,
              address - (uintptr_t)info.dli_fbase, info.dli_sname ? info.dli_sname : "");
    }
  }
  fclose(file);
}
