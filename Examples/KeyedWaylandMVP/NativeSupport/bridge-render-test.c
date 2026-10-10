/* Tests the exact renderer in an EGL pbuffer; no Wayland presentation claimed. */
#include "../Sources/WaylandBridge/WaylandBridge.c"
#include <assert.h>

int main(void) {
    struct Host host = {0};
    host.input.width = host.input.height = 16;
    host.egl_display = EGL_NO_DISPLAY; host.egl_context = EGL_NO_CONTEXT;
    host.egl_surface = EGL_NO_SURFACE;
    assert(setup_egl(&host, 1));
    active_host = &host; host.render_active = 1;
    glViewport(0, 0, 16, 16);
    glUniform2f(host.resolution_location, 16, 16);
    glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    wb_draw_rect(2, 2, 12, 12, 1, 0, 0, 0.5f, 4);
    wb_flush();
    unsigned char pixel[4];
    glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    assert(glGetError() == GL_NO_ERROR);
    assert(pixel[0] >= 127 && pixel[0] <= 129);
    assert(pixel[1] == 0 && pixel[2] == 0);
    assert(pixel[3] == 255); /* Source alpha must not be squared. */
    unsigned char pixels[16 * 16 * 4];
    glReadPixels(0, 0, 16, 16, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    for (size_t i = 3; i < sizeof(pixels); i += 4) assert(pixels[i] == 255);
    for (int i = 0; i < WB_BATCH_RECTS + 1; ++i)
        wb_draw_rect(2, 2, 12, 12, 0, 0, 0.8f, 0.25f, 0);
    assert(host.staged_rects == 1); /* Full fixed batch already uploaded. */
    wb_flush(); assert(host.staged_rects == 0);
    glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    assert(glGetError() == GL_NO_ERROR);
    assert(pixel[2] >= 201 && pixel[2] <= 205 && pixel[3] == 255);
    host.render_active = 0; active_host = NULL; cleanup(&host);
    puts("EGL renderer assertions passed: half-alpha composition, opaque AA edges, and 1025-quad batch rollover.");
    return 0;
}
