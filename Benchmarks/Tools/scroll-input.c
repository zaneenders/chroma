#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "virtual-pointer.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct wl_seat *seat;

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
  (void)data;
  if (strcmp(interface, "zwlr_virtual_pointer_manager_v1") == 0)
    manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface,
                               version < 2 ? version : 2);
  else if (strcmp(interface, "wl_seat") == 0)
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
}

static void removed(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data; (void)registry; (void)name;
}

static double now(void) {
  struct timespec time;
  if (clock_gettime(CLOCK_MONOTONIC, &time) < 0) { perror("clock_gettime"); exit(1); }
  return (double)time.tv_sec + (double)time.tv_nsec / 1e9;
}

static double number(const char *argument) {
  char *end;
  errno = 0;
  const double value = strtod(argument, &end);
  if (errno || end == argument || *end || !isfinite(value)) {
    fprintf(stderr, "Invalid gesture parameters\n"); exit(1);
  }
  return value;
}

static void wait_until(double deadline) {
  struct timespec time = {.tv_sec = (time_t)deadline,
                         .tv_nsec = (long)((deadline - floor(deadline)) * 1e9)};
  int result;
  do { result = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &time, NULL); } while (result == EINTR);
  if (result != 0) { errno = result; perror("clock_nanosleep"); exit(1); }
}

int main(int argc, char **argv) {
  if (argc != 6) {
    fprintf(stderr, "Usage: scroll-input vertical|diagonal finger|wheel SECONDS EVENT_HZ DELTA\n");
    return 1;
  }
  const int diagonal = strcmp(argv[1], "diagonal") == 0;
  const int finger = strcmp(argv[2], "finger") == 0;
  const double seconds = number(argv[3]), hz = number(argv[4]), delta = number(argv[5]);
  if ((!diagonal && strcmp(argv[1], "vertical") != 0) ||
      (!finger && strcmp(argv[2], "wheel") != 0) ||
      seconds <= 0 || seconds > 60 || hz < 1 || hz > 1000 || delta == 0 || fabs(delta) > 100) {
    fprintf(stderr, "Invalid gesture parameters\n"); return 1;
  }
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) { fprintf(stderr, "Cannot connect to Wayland\n"); return 1; }
  struct wl_registry *registry = wl_display_get_registry(display);
  const struct wl_registry_listener listener = {.global = global, .global_remove = removed};
  wl_registry_add_listener(registry, &listener, NULL);
  if (wl_display_roundtrip(display) < 0 || !manager || !seat) {
    fprintf(stderr, "Compositor needs wl_seat and wlr virtual-pointer support\n"); return 1;
  }
  struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
  zwlr_virtual_pointer_v1_motion_absolute(pointer, (uint32_t)(now() * 1000), 240, 450, 1440, 900);
  zwlr_virtual_pointer_v1_frame(pointer);
  if (wl_display_roundtrip(display) < 0) return 1;
  wait_until(now() + 0.1);
  const double start = now();
  double maximum_lateness = 0;
  const int count = (int)ceil(seconds * hz);
  for (int event = 0; event < count; ++event) {
    const double deadline = start + event / hz;
    wait_until(deadline);
    const double receipt = now();
    maximum_lateness = fmax(maximum_lateness, receipt - deadline);
    const uint32_t milliseconds = (uint32_t)(receipt * 1000);
    // Change direction before reaching an endpoint, without changing input cadence.
    const double direction = ((int)(event / hz / 2) % 2 == 0) ? 1 : -1;
    zwlr_virtual_pointer_v1_axis_source(pointer, finger ? WL_POINTER_AXIS_SOURCE_FINGER : WL_POINTER_AXIS_SOURCE_WHEEL);
    zwlr_virtual_pointer_v1_axis(pointer, milliseconds, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(delta * direction));
    if (diagonal)
      zwlr_virtual_pointer_v1_axis(pointer, milliseconds, WL_POINTER_AXIS_HORIZONTAL_SCROLL, wl_fixed_from_double(delta * direction));
    zwlr_virtual_pointer_v1_frame(pointer);
    if (wl_display_flush(display) < 0) { perror("wl_display_flush"); return 1; }
  }
  const double released = now();
  if (finger) {
    zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_FINGER);
    zwlr_virtual_pointer_v1_axis_stop(pointer, (uint32_t)(released * 1000), WL_POINTER_AXIS_VERTICAL_SCROLL);
    if (diagonal)
      zwlr_virtual_pointer_v1_axis_stop(pointer, (uint32_t)(released * 1000), WL_POINTER_AXIS_HORIZONTAL_SCROLL);
    zwlr_virtual_pointer_v1_frame(pointer);
  }
  if (wl_display_roundtrip(display) < 0) return 1;
  // Removing the device immediately can send leave and cancel released momentum.
  wait_until(now() + 2);
  printf("{\"direction\":\"%s\",\"source\":\"%s\",\"events\":%d,\"eventHz\":%.3f,\"delta\":%.3f,"
         "\"started\":%.9f,\"released\":%.9f,\"maximumLatenessMs\":%.3f}\n",
         argv[1], argv[2], count, hz, delta, start, released, maximum_lateness * 1000);
  zwlr_virtual_pointer_v1_destroy(pointer);
  zwlr_virtual_pointer_manager_v1_destroy(manager);
  wl_seat_destroy(seat);
  wl_registry_destroy(registry);
  wl_display_flush(display);
  wl_display_disconnect(display);
  return 0;
}
