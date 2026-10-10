/* Minimal value-only Wayland/EGL bridge. No UI tree or layout runtime lives here. */
#include "WaylandBridge.h"

#ifdef WB_NATIVE
#include "xdg-shell-client-protocol.h"
#include <wayland-client.h>
#include <wayland-egl.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <errno.h>
#include <math.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

enum { WB_BATCH_RECTS = 1024, WB_VERTEX_FLOATS = 11 };
struct Host {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct xdg_wm_base *shell;
    struct wl_surface *surface;
    struct xdg_surface *xdg_surface;
    struct xdg_toplevel *toplevel;
    struct wl_seat *seat;
    struct wl_pointer *pointer;
    struct wl_keyboard *keyboard;
    struct wl_callback *frame_callback;
    struct wl_egl_window *window;
    EGLDisplay egl_display;
    EGLContext egl_context;
    EGLSurface egl_surface;
    GLuint program, vertex_buffer;
    GLint resolution_location;
    /* C-owned bounded staging memory; no reference into a Swift frame survives a call. */
    GLfloat vertices[WB_BATCH_RECTS * 6 * WB_VERTEX_FLOATS];
    size_t staged_rects;
    WBInput input;
    int running, configured, frame_ready, render_active;
};
static struct Host *active_host;

static double monotonic_seconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
}
static void shell_ping(void *data, struct xdg_wm_base *shell, uint32_t serial) {
    (void)data; xdg_wm_base_pong(shell, serial);
}
static const struct xdg_wm_base_listener shell_listener = { .ping = shell_ping };
static void surface_configure(void *data, struct xdg_surface *surface, uint32_t serial) {
    struct Host *host = data;
    xdg_surface_ack_configure(surface, serial);
    host->configured = 1;
}
static const struct xdg_surface_listener surface_listener = { .configure = surface_configure };
static void toplevel_configure(void *data, struct xdg_toplevel *toplevel,
                               int32_t width, int32_t height, struct wl_array *states) {
    (void)toplevel; (void)states;
    struct Host *host = data;
    if (width > 0) host->input.width = width;
    if (height > 0) host->input.height = height;
    if (host->window)
        wl_egl_window_resize(host->window, host->input.width, host->input.height, 0, 0);
}
static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
    (void)toplevel; ((struct Host *)data)->running = 0;
}
static const struct xdg_toplevel_listener toplevel_listener = {
    .configure = toplevel_configure, .close = toplevel_close
};
static void pointer_enter(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y) {
    (void)pointer; (void)serial; (void)surface;
    struct Host *host = data;
    host->input.pointer_inside = 1;
    host->input.pointer_x = (float)wl_fixed_to_double(x);
    host->input.pointer_y = (float)wl_fixed_to_double(y);
}
static void pointer_leave(void *data, struct wl_pointer *pointer, uint32_t serial,
                          struct wl_surface *surface) {
    (void)pointer; (void)serial; (void)surface;
    struct Host *host = data;
    host->input.pointer_inside = 0;
    host->input.primary_released |= host->input.primary_down;
    host->input.primary_down = 0;
}
static void pointer_motion(void *data, struct wl_pointer *pointer, uint32_t time,
                           wl_fixed_t x, wl_fixed_t y) {
    (void)pointer; (void)time;
    struct Host *host = data;
    host->input.pointer_x = (float)wl_fixed_to_double(x);
    host->input.pointer_y = (float)wl_fixed_to_double(y);
}
static void pointer_button(void *data, struct wl_pointer *pointer, uint32_t serial,
                           uint32_t time, uint32_t button, uint32_t state) {
    (void)pointer; (void)serial; (void)time;
    struct Host *host = data;
    if (button != 0x110) return; /* Linux BTN_LEFT, Wayland's specified evdev codes. */
    int down = state == WL_POINTER_BUTTON_STATE_PRESSED;
    if (down && !host->input.primary_down) host->input.primary_pressed = 1;
    if (!down && host->input.primary_down) host->input.primary_released = 1;
    host->input.primary_down = (uint8_t)down;
}
static void pointer_axis(void *data, struct wl_pointer *pointer, uint32_t time,
                         uint32_t axis, wl_fixed_t value) {
    (void)pointer; (void)time;
    struct Host *host = data;
    if (axis == WL_POINTER_AXIS_VERTICAL_SCROLL)
        host->input.scroll_y += (float)wl_fixed_to_double(value);
    else if (axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL)
        host->input.scroll_x += (float)wl_fixed_to_double(value);
}
/* Bind wl_seat at version 4: only the five original pointer events can arrive. */
static const struct wl_pointer_listener pointer_listener = {
    .enter = pointer_enter, .leave = pointer_leave, .motion = pointer_motion,
    .button = pointer_button, .axis = pointer_axis
};
static void keyboard_keymap(void *data, struct wl_keyboard *keyboard,
                            uint32_t format, int fd, uint32_t size) {
    (void)data; (void)keyboard; (void)format; (void)size;
    /* No text input in this MVP. Shortcuts use the protocol's physical key codes. */
    if (fd >= 0) close(fd);
}
static void keyboard_enter(void *data, struct wl_keyboard *keyboard, uint32_t serial,
                           struct wl_surface *surface, struct wl_array *keys) {
    (void)data; (void)keyboard; (void)serial; (void)surface; (void)keys;
}
static void keyboard_leave(void *data, struct wl_keyboard *keyboard, uint32_t serial,
                           struct wl_surface *surface) {
    (void)keyboard; (void)serial; (void)surface;
    struct Host *host = data;
    host->input.tab_pressed = host->input.enter_pressed = host->input.escape_pressed = 0;
}
static void keyboard_key(void *data, struct wl_keyboard *keyboard, uint32_t serial,
                         uint32_t time, uint32_t key, uint32_t state) {
    (void)keyboard; (void)serial; (void)time;
    if (state != WL_KEYBOARD_KEY_STATE_PRESSED) return;
    struct Host *host = data;
    if (key == 15) host->input.tab_pressed = 1;
    if (key == 28 || key == 57) host->input.enter_pressed = 1;
    if (key == 1) host->input.escape_pressed = 1;
}
static void keyboard_modifiers(void *data, struct wl_keyboard *keyboard,
                               uint32_t serial, uint32_t depressed, uint32_t latched,
                               uint32_t locked, uint32_t group) {
    (void)data; (void)keyboard; (void)serial; (void)depressed;
    (void)latched; (void)locked; (void)group;
}
static void keyboard_repeat_info(void *data, struct wl_keyboard *keyboard,
                                  int32_t rate, int32_t delay) {
    (void)data; (void)keyboard; (void)rate; (void)delay;
    /* Activation is edge-triggered; no key-repeat timer in this MVP. */
}
static const struct wl_keyboard_listener keyboard_listener = {
    .keymap = keyboard_keymap, .enter = keyboard_enter, .leave = keyboard_leave,
    .key = keyboard_key, .modifiers = keyboard_modifiers, .repeat_info = keyboard_repeat_info
};
static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t capabilities) {
    struct Host *host = data;
    if ((capabilities & WL_SEAT_CAPABILITY_POINTER) && !host->pointer) {
        host->pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(host->pointer, &pointer_listener, host);
    } else if (!(capabilities & WL_SEAT_CAPABILITY_POINTER) && host->pointer) {
        wl_pointer_release(host->pointer); host->pointer = NULL;
        host->input.pointer_inside = host->input.primary_down = 0;
        host->input.primary_released = 1;
    }
    if ((capabilities & WL_SEAT_CAPABILITY_KEYBOARD) && !host->keyboard) {
        host->keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(host->keyboard, &keyboard_listener, host);
    } else if (!(capabilities & WL_SEAT_CAPABILITY_KEYBOARD) && host->keyboard) {
        wl_keyboard_release(host->keyboard); host->keyboard = NULL;
    }
}
static void seat_name(void *data, struct wl_seat *seat, const char *name) {
    (void)data; (void)seat; (void)name;
}
static const struct wl_seat_listener seat_listener = {
    .capabilities = seat_capabilities, .name = seat_name
};
static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    struct Host *host = data;
    if (strcmp(interface, "wl_compositor") == 0)
        host->compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 1);
    else if (strcmp(interface, "xdg_wm_base") == 0) {
        host->shell = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(host->shell, &shell_listener, host);
    } else if (strcmp(interface, "wl_seat") == 0 && !host->seat && version >= 4) {
        host->seat = wl_registry_bind(registry, name, &wl_seat_interface, 4);
        wl_seat_add_listener(host->seat, &seat_listener, host);
    }
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = {
    .global = registry_global, .global_remove = registry_remove
};
static void frame_done(void *data, struct wl_callback *callback, uint32_t time) {
    (void)time;
    struct Host *host = data;
    wl_callback_destroy(callback);
    host->frame_callback = NULL;
    host->frame_ready = 1;
}
static const struct wl_callback_listener frame_listener = { .done = frame_done };

/* An intentionally narrow ES2 rectangle shader. Pixel-space mapping follows
 * the existing Wayland backend; no existing UI/runtime dependency is linked. */
static const char *vertex_source =
    "attribute vec2 position; attribute vec2 localPosition; attribute vec2 size;"
    "attribute vec4 color; attribute float radius; uniform vec2 resolution;"
    "varying vec2 vLocal; varying vec2 vSize; varying vec4 vColor; varying float vRadius;"
    "void main() { vLocal = localPosition; vSize = size; vColor = color; vRadius = radius;"
    "gl_Position = vec4(position.x / resolution.x * 2.0 - 1.0,"
    "1.0 - position.y / resolution.y * 2.0, 0.0, 1.0); }";
static const char *fragment_source =
    "precision highp float; varying vec2 vLocal; varying vec2 vSize;"
    "varying vec4 vColor; varying float vRadius; void main() {"
    "vec2 halfSize = vSize * 0.5;"
    "float r = min(max(vRadius, 0.0), min(halfSize.x, halfSize.y));"
    "vec2 q = abs(vLocal - halfSize) - halfSize + vec2(r);"
    "float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;"
    "float coverage = 1.0 - smoothstep(-0.75, 0.75, distance);"
    "gl_FragColor = vec4(vColor.rgb, vColor.a * coverage); }";
static GLuint compile_shader(GLenum kind, const char *source) {
    GLuint shader = glCreateShader(kind);
    glShaderSource(shader, 1, &source, NULL); glCompileShader(shader);
    GLint success = 0; glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        char log[2048]; glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        fprintf(stderr, "Shader compilation failed: %s\n", log);
        glDeleteShader(shader); return 0;
    }
    return shader;
}
static int setup_egl(struct Host *host, int surfaceless) {
    if (surfaceless) {
        PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform =
            (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
        if (!get_platform) return 0;
        host->egl_display = get_platform(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
    } else {
        host->egl_display = eglGetDisplay((EGLNativeDisplayType)host->display);
    }
    if (host->egl_display == EGL_NO_DISPLAY || !eglInitialize(host->egl_display, NULL, NULL))
        return 0;
    if (!eglBindAPI(EGL_OPENGL_ES_API)) return 0;
    const EGLint attributes[] = { EGL_SURFACE_TYPE, surfaceless ? EGL_PBUFFER_BIT : EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE };
    EGLConfig config; EGLint count = 0;
    if (!eglChooseConfig(host->egl_display, attributes, &config, 1, &count) || count != 1)
        return 0;
    const EGLint context_attributes[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    host->egl_context = eglCreateContext(host->egl_display, config, EGL_NO_CONTEXT, context_attributes);
    if (host->egl_context == EGL_NO_CONTEXT) return 0;
    if (surfaceless) {
        const EGLint pbuffer_attributes[] = {
            EGL_WIDTH, host->input.width, EGL_HEIGHT, host->input.height, EGL_NONE
        };
        host->egl_surface = eglCreatePbufferSurface(host->egl_display, config, pbuffer_attributes);
    } else {
        host->window = wl_egl_window_create(host->surface, host->input.width, host->input.height);
        if (!host->window) return 0;
        host->egl_surface = eglCreateWindowSurface(host->egl_display, config,
                                                  (EGLNativeWindowType)host->window, NULL);
    }
    if (host->egl_surface == EGL_NO_SURFACE ||
        !eglMakeCurrent(host->egl_display, host->egl_surface, host->egl_surface, host->egl_context))
        return 0;
    eglSwapInterval(host->egl_display, 0);
    GLuint vertex = compile_shader(GL_VERTEX_SHADER, vertex_source);
    GLuint fragment = compile_shader(GL_FRAGMENT_SHADER, fragment_source);
    if (!vertex || !fragment) {
        if (vertex) glDeleteShader(vertex);
        if (fragment) glDeleteShader(fragment);
        return 0;
    }
    host->program = glCreateProgram();
    glAttachShader(host->program, vertex); glAttachShader(host->program, fragment);
    glBindAttribLocation(host->program, 0, "position");
    glBindAttribLocation(host->program, 1, "localPosition");
    glBindAttribLocation(host->program, 2, "size");
    glBindAttribLocation(host->program, 3, "color");
    glBindAttribLocation(host->program, 4, "radius");
    glLinkProgram(host->program);
    glDeleteShader(vertex); glDeleteShader(fragment);
    GLint linked = 0; glGetProgramiv(host->program, GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[2048]; glGetProgramInfoLog(host->program, sizeof(log), NULL, log);
        fprintf(stderr, "Shader linking failed: %s\n", log); return 0;
    }
    host->resolution_location = glGetUniformLocation(host->program, "resolution");
    glGenBuffers(1, &host->vertex_buffer); glBindBuffer(GL_ARRAY_BUFFER, host->vertex_buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(host->vertices), NULL, GL_STREAM_DRAW);
    glUseProgram(host->program);
    const int lengths[] = {2, 2, 2, 4, 1};
    const size_t offsets[] = {0, 2, 4, 6, 10};
    for (GLuint i = 0; i < 5; ++i) {
        glEnableVertexAttribArray(i);
        glVertexAttribPointer(i, lengths[i], GL_FLOAT, GL_FALSE,
                              WB_VERTEX_FLOATS * sizeof(GLfloat),
                              (const void *)(offsets[i] * sizeof(GLfloat)));
    }
    glEnable(GL_BLEND);
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    fprintf(stderr, "%s EGL renderer: %s | %s\n", surfaceless ? "Surfaceless" : "Wayland", glGetString(GL_RENDERER), glGetString(GL_VERSION));
    return glGetError() == GL_NO_ERROR;
}

static void flush_rects(struct Host *host) {
    if (!host->staged_rects) return;
    size_t vertex_count = host->staged_rects * 6;
    glBufferData(GL_ARRAY_BUFFER, vertex_count * WB_VERTEX_FLOATS * sizeof(GLfloat),
                 host->vertices, GL_STREAM_DRAW);
    glDrawArrays(GL_TRIANGLES, 0, (GLsizei)vertex_count);
    host->staged_rects = 0;
}
void wb_draw_rect(float x, float y, float width, float height,
                  float r, float g, float b, float a, float radius) {
    struct Host *host = active_host;
    if (!host || !host->render_active || width <= 0 || height <= 0 ||
        !isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        !isfinite(r) || !isfinite(g) || !isfinite(b) || !isfinite(a) || !isfinite(radius)) return;
    if (host->staged_rects == WB_BATCH_RECTS) flush_rects(host);
    static const float corners[6][2] = {{0,0}, {1,0}, {0,1}, {0,1}, {1,0}, {1,1}};
    GLfloat *vertex = host->vertices + host->staged_rects * 6 * WB_VERTEX_FLOATS;
    for (int i = 0; i < 6; ++i) {
        float lx = corners[i][0] * width, ly = corners[i][1] * height;
        const GLfloat values[WB_VERTEX_FLOATS] = {x+lx, y+ly, lx, ly, width, height, r,g,b,a, radius};
        memcpy(vertex, values, sizeof(values)); vertex += WB_VERTEX_FLOATS;
    }
    ++host->staged_rects;
}
void wb_flush(void) {
    if (active_host && active_host->render_active) flush_rects(active_host);
}

static int screenshot(struct Host *host, const char *path) {
    size_t width = (size_t)host->input.width, height = (size_t)host->input.height;
    if (!width || !height || width > SIZE_MAX / 4 / height) return 0;
    unsigned char *pixels = malloc(width * height * 4);
    if (!pixels) return 0;
    glReadPixels(0, 0, (GLsizei)width, (GLsizei)height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    if (glGetError() != GL_NO_ERROR) { free(pixels); return 0; }
    FILE *file = fopen(path, "wb");
    if (!file) { perror(path); free(pixels); return 0; }
    int success = fprintf(file, "P6\n%zu %zu\n255\n", width, height) > 0;
    for (size_t row = height; row > 0 && success; --row)
        for (size_t column = 0; column < width && success; ++column)
            success = fwrite(pixels + ((row - 1) * width + column) * 4, 1, 3, file) == 3;
    if (fclose(file) != 0) success = 0;
    free(pixels); return success;
}
static void cleanup(struct Host *host) {
    if (host->egl_display != EGL_NO_DISPLAY) {
        if (host->program) glDeleteProgram(host->program);
        if (host->vertex_buffer) glDeleteBuffers(1, &host->vertex_buffer);
        eglMakeCurrent(host->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (host->egl_surface != EGL_NO_SURFACE) eglDestroySurface(host->egl_display, host->egl_surface);
        if (host->egl_context != EGL_NO_CONTEXT) eglDestroyContext(host->egl_display, host->egl_context);
        eglTerminate(host->egl_display);
    }
    if (host->window) wl_egl_window_destroy(host->window);
    if (host->frame_callback) wl_callback_destroy(host->frame_callback);
    if (host->keyboard) wl_keyboard_release(host->keyboard);
    if (host->pointer) wl_pointer_release(host->pointer);
    if (host->seat) wl_seat_destroy(host->seat);
    if (host->toplevel) xdg_toplevel_destroy(host->toplevel);
    if (host->xdg_surface) xdg_surface_destroy(host->xdg_surface);
    if (host->surface) wl_surface_destroy(host->surface);
    if (host->shell) xdg_wm_base_destroy(host->shell);
    if (host->compositor) wl_compositor_destroy(host->compositor);
    if (host->registry) wl_registry_destroy(host->registry);
    if (host->display) wl_display_disconnect(host->display);
}
int32_t wb_native_available(void) { return 1; }
int32_t wb_run(const WBConfig *config, WBFrameCallback frame, void *context) {
    if (!config || !frame || active_host || config->max_frames < 0 ||
        config->width <= 0 || config->height <= 0) return 2;
    struct Host host = {0};
    host.input.width = config->width; host.input.height = config->height;
    host.running = host.frame_ready = 1;
    host.egl_display = EGL_NO_DISPLAY; host.egl_context = EGL_NO_CONTEXT;
    host.egl_surface = EGL_NO_SURFACE;
    int result = 1;
    host.display = wl_display_connect(NULL);
    if (!host.display) { fprintf(stderr, "Cannot connect to Wayland. Set WAYLAND_DISPLAY and XDG_RUNTIME_DIR.\n"); goto finish; }
    host.registry = wl_display_get_registry(host.display);
    wl_registry_add_listener(host.registry, &registry_listener, &host);
    if (wl_display_roundtrip(host.display) < 0 || !host.compositor || !host.shell) {
        fprintf(stderr, "Wayland compositor must support wl_compositor and xdg_wm_base.\n"); goto finish;
    }
    host.surface = wl_compositor_create_surface(host.compositor);
    host.xdg_surface = xdg_wm_base_get_xdg_surface(host.shell, host.surface);
    xdg_surface_add_listener(host.xdg_surface, &surface_listener, &host);
    host.toplevel = xdg_surface_get_toplevel(host.xdg_surface);
    xdg_toplevel_add_listener(host.toplevel, &toplevel_listener, &host);
    xdg_toplevel_set_title(host.toplevel, config->title ? config->title : "Keyed UI Demo");
    xdg_toplevel_set_app_id(host.toplevel, "org.example.keyed-ui-demo");
    xdg_toplevel_set_min_size(host.toplevel, 760, 640);
    wl_surface_commit(host.surface);
    while (!host.configured && host.running)
        if (wl_display_dispatch(host.display) < 0) goto finish;
    if (!host.running) { result = 0; goto finish; }
    if (!setup_egl(&host, 0)) { fprintf(stderr, "EGL setup failed: 0x%x\n", eglGetError()); goto finish; }
    active_host = &host;
    double started = monotonic_seconds();
    int frame_count = 0;
    while (host.running) {
        if (host.frame_ready) {
            host.frame_ready = 0;
            glViewport(0, 0, host.input.width, host.input.height);
            glClearColor(0.04f, 0.05f, 0.07f, 1.0f); glClear(GL_COLOR_BUFFER_BIT);
            glUseProgram(host.program);
            glUniform2f(host.resolution_location, (float)host.input.width, (float)host.input.height);
            host.input.time_seconds = monotonic_seconds() - started;
            host.render_active = 1; frame(context, &host.input);
            flush_rects(&host); host.render_active = 0;
            if (host.input.escape_pressed) host.running = 0;
            ++frame_count;
            if (glGetError() != GL_NO_ERROR) { fprintf(stderr, "OpenGL rendering failed.\n"); goto finish; }
            int last_frame = config->max_frames > 0 && frame_count >= config->max_frames;
            if (last_frame && config->screenshot_path && !screenshot(&host, config->screenshot_path)) {
                fprintf(stderr, "Screenshot capture failed.\n"); goto finish;
            }
            host.input.primary_pressed = host.input.primary_released = 0;
            host.input.tab_pressed = host.input.enter_pressed = host.input.escape_pressed = 0;
            host.input.scroll_x = host.input.scroll_y = 0;
            host.frame_callback = wl_surface_frame(host.surface);
            wl_callback_add_listener(host.frame_callback, &frame_listener, &host);
            if (!eglSwapBuffers(host.egl_display, host.egl_surface)) {
                fprintf(stderr, "eglSwapBuffers failed: 0x%x\n", eglGetError()); goto finish;
            }
            if (last_frame || !host.running) break;
        }
        /* Dispatch both input and compositor frame callbacks without busy-spinning. */
        if (wl_display_dispatch(host.display) < 0) goto finish;
    }
    fprintf(stderr, "Rendered %d Wayland frame%s at %dx%d.\n", frame_count,
            frame_count == 1 ? "" : "s", host.input.width, host.input.height);
    result = 0;
finish:
    active_host = NULL; cleanup(&host); return result;
}
int32_t wb_run_surfaceless(const WBConfig *config, WBFrameCallback frame, void *context) {
    if (!config || !frame || active_host || config->max_frames < 1 ||
        config->width <= 0 || config->height <= 0) return 2;
    struct Host host = {0};
    host.input.width = config->width; host.input.height = config->height;
    host.egl_display = EGL_NO_DISPLAY; host.egl_context = EGL_NO_CONTEXT;
    host.egl_surface = EGL_NO_SURFACE;
    int result = 1;
    if (!setup_egl(&host, 1)) {
        fprintf(stderr, "Surfaceless EGL setup failed: 0x%x\n", eglGetError()); goto finish;
    }
    active_host = &host;
    glViewport(0, 0, host.input.width, host.input.height);
    glUniform2f(host.resolution_location, (float)host.input.width, (float)host.input.height);
    for (int i = 0; i < config->max_frames; ++i) {
        glClearColor(0.04f, 0.05f, 0.07f, 1.0f); glClear(GL_COLOR_BUFFER_BIT);
        host.input.time_seconds = (double)i / 60.0;
        host.render_active = 1; frame(context, &host.input);
        flush_rects(&host); host.render_active = 0;
        glFinish();
        if (glGetError() != GL_NO_ERROR) {
            fprintf(stderr, "Surfaceless OpenGL rendering failed.\n"); goto finish;
        }
    }
    if (config->screenshot_path && !screenshot(&host, config->screenshot_path)) {
        fprintf(stderr, "Surfaceless screenshot capture failed.\n"); goto finish;
    }
    fprintf(stderr, "Rendered %d EGL surfaceless frames at %dx%d (no Wayland presentation).\n",
            config->max_frames, host.input.width, host.input.height);
    result = 0;
finish:
    active_host = NULL; cleanup(&host); return result;
}

#else
#include <stdio.h>
int32_t wb_run_surfaceless(const WBConfig *config, WBFrameCallback frame, void *context) {
    return wb_run(config, frame, context);
}
int32_t wb_native_available(void) { return 0; }
void wb_flush(void) {}
void wb_draw_rect(float x, float y, float width, float height,
                  float r, float g, float b, float a, float radius) {
    (void)x; (void)y; (void)width; (void)height; (void)r; (void)g; (void)b; (void)a; (void)radius;
}
int32_t wb_run(const WBConfig *config, WBFrameCallback frame, void *context) {
    (void)config; (void)frame; (void)context;
    fprintf(stderr, "Native Wayland support was not compiled. See NativeSupport/README.md.\n");
    return 2;
}
#endif
