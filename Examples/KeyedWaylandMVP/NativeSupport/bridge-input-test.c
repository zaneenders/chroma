/* Unit tests of listener-to-snapshot translation, not compositor integration.
 * Include the implementation to exercise the exact production handlers. */
#include "../Sources/WaylandBridge/WaylandBridge.c"
#include <assert.h>

int main(void) {
    struct Host host = {0};
    pointer_enter(&host, NULL, 0, NULL, wl_fixed_from_int(120), wl_fixed_from_int(80));
    assert(host.input.pointer_inside && host.input.pointer_x == 120 && host.input.pointer_y == 80);
    pointer_motion(&host, NULL, 0, wl_fixed_from_double(140.5), wl_fixed_from_double(90.25));
    assert(host.input.pointer_x == 140.5 && host.input.pointer_y == 90.25);
    pointer_button(&host, NULL, 0, 0, 0x111, WL_POINTER_BUTTON_STATE_PRESSED);
    assert(!host.input.primary_down && !host.input.primary_pressed);
    pointer_button(&host, NULL, 0, 0, 0x110, WL_POINTER_BUTTON_STATE_PRESSED);
    assert(host.input.primary_down && host.input.primary_pressed && !host.input.primary_released);
    host.input.primary_pressed = 0;
    pointer_button(&host, NULL, 0, 0, 0x110, WL_POINTER_BUTTON_STATE_PRESSED);
    assert(!host.input.primary_pressed); /* Ignore duplicate press state. */
    pointer_button(&host, NULL, 0, 0, 0x110, WL_POINTER_BUTTON_STATE_RELEASED);
    assert(!host.input.primary_down && host.input.primary_released);
    pointer_axis(&host, NULL, 0, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(12));
    pointer_axis(&host, NULL, 0, WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(-4));
    pointer_axis(&host, NULL, 0, WL_POINTER_AXIS_HORIZONTAL_SCROLL, wl_fixed_from_int(3));
    assert(host.input.scroll_y == 8 && host.input.scroll_x == 3);
    keyboard_key(&host, NULL, 0, 0, 15, WL_KEYBOARD_KEY_STATE_RELEASED);
    assert(!host.input.tab_pressed);
    keyboard_key(&host, NULL, 0, 0, 15, WL_KEYBOARD_KEY_STATE_PRESSED);
    keyboard_key(&host, NULL, 0, 0, 28, WL_KEYBOARD_KEY_STATE_PRESSED);
    keyboard_key(&host, NULL, 0, 0, 1, WL_KEYBOARD_KEY_STATE_PRESSED);
    assert(host.input.tab_pressed && host.input.enter_pressed && host.input.escape_pressed);
    keyboard_leave(&host, NULL, 0, NULL);
    assert(!host.input.tab_pressed && !host.input.enter_pressed && !host.input.escape_pressed);
    keyboard_key(&host, NULL, 0, 0, 57, WL_KEYBOARD_KEY_STATE_PRESSED);
    assert(host.input.enter_pressed);
    host.input.primary_down = 1; host.input.primary_released = 0;
    pointer_leave(&host, NULL, 0, NULL);
    assert(!host.input.pointer_inside && !host.input.primary_down && host.input.primary_released);
    puts("Bridge input handler tests passed (synthetic listener calls; no Wayland delivery).");
    return 0;
}
