#ifndef WAYLAND_BRIDGE_H
#define WAYLAND_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Value-only input snapshot. The pointer passed to a frame callback is valid
 * only for that callback. Coordinates and dimensions are surface pixels. */
typedef struct {
    int32_t width, height;
    double time_seconds;
    float pointer_x, pointer_y, scroll_x, scroll_y;
    uint8_t pointer_inside;
    uint8_t primary_down, primary_pressed, primary_released;
    uint8_t tab_pressed, enter_pressed, escape_pressed;
} WBInput;

typedef struct {
    int32_t width, height;
    int32_t max_frames; /* 0 runs until the window closes. */
    const char *title;
    const char *screenshot_path; /* Optional P6 PPM, captured on the last frame. */
} WBConfig;

typedef void (*WBFrameCallback)(void *context, const WBInput *input);

/* Runs synchronously on the calling thread. Returns zero on clean exit.
 * Config strings need to remain valid until this function returns.
 * A single window and renderer is supported at a time. */
int32_t wb_run(const WBConfig *config, WBFrameCallback frame, void *context);

/* Only valid inside the frame callback. All values are synchronously copied
 * to GL uniforms; the bridge never retains a Swift draw-record pointer. */
void wb_draw_rect(float x, float y, float width, float height,
                  float r, float g, float b, float a, float radius);

/* Reports whether this build contains the native Wayland renderer. */
int32_t wb_native_available(void);

#ifdef __cplusplus
}
#endif
#endif
