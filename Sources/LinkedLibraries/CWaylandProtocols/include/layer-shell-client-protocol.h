#ifndef WLR_LAYER_SHELL_UNSTABLE_V1_CLIENT_PROTOCOL_H
#define WLR_LAYER_SHELL_UNSTABLE_V1_CLIENT_PROTOCOL_H

#include "wayland-client.h"
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Copyright © 2017 Drew DeVault
 *
 * Permission to use, copy, modify, distribute, and sell this
 * software and its documentation for any purpose is hereby granted
 * without fee, provided that the above copyright notice appear in
 * all copies and that both that copyright notice and this permission
 * notice appear in supporting documentation, and that the name of
 * the copyright holders not be used in advertising or publicity
 * pertaining to distribution of the software without specific,
 * written prior permission.  The copyright holders make no
 * representations about the suitability of this software for any
 * purpose.  It is provided "as is" without express or implied
 * warranty.
 *
 * THE COPYRIGHT HOLDERS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
 * SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
 * FITNESS, IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
 * AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
 * ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
 * THIS SOFTWARE.
 */
struct wl_output;
struct wl_surface;
struct xdg_popup;
struct zwlr_layer_shell_v1;
struct zwlr_layer_surface_v1;

#ifndef ZWLR_LAYER_SHELL_V1_INTERFACE
#define ZWLR_LAYER_SHELL_V1_INTERFACE
extern const struct wl_interface zwlr_layer_shell_v1_interface;
#endif
#ifndef ZWLR_LAYER_SURFACE_V1_INTERFACE
#define ZWLR_LAYER_SURFACE_V1_INTERFACE
extern const struct wl_interface zwlr_layer_surface_v1_interface;
#endif

#ifndef ZWLR_LAYER_SHELL_V1_ERROR_ENUM
#define ZWLR_LAYER_SHELL_V1_ERROR_ENUM
enum zwlr_layer_shell_v1_error {
  ZWLR_LAYER_SHELL_V1_ERROR_ROLE = 0,
  ZWLR_LAYER_SHELL_V1_ERROR_INVALID_LAYER = 1,
  ZWLR_LAYER_SHELL_V1_ERROR_ALREADY_CONSTRUCTED = 2,
};
#endif

#ifndef ZWLR_LAYER_SHELL_V1_LAYER_ENUM
#define ZWLR_LAYER_SHELL_V1_LAYER_ENUM
enum zwlr_layer_shell_v1_layer {
  ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND = 0,
  ZWLR_LAYER_SHELL_V1_LAYER_BOTTOM = 1,
  ZWLR_LAYER_SHELL_V1_LAYER_TOP = 2,
  ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY = 3,
};
#endif

#define ZWLR_LAYER_SHELL_V1_GET_LAYER_SURFACE 0
#define ZWLR_LAYER_SHELL_V1_DESTROY 1

#define ZWLR_LAYER_SHELL_V1_GET_LAYER_SURFACE_SINCE_VERSION 1
#define ZWLR_LAYER_SHELL_V1_DESTROY_SINCE_VERSION 3

static inline void zwlr_layer_shell_v1_set_user_data(
    struct zwlr_layer_shell_v1 *zwlr_layer_shell_v1, void *user_data) {
  wl_proxy_set_user_data((struct wl_proxy *)zwlr_layer_shell_v1, user_data);
}

static inline void *zwlr_layer_shell_v1_get_user_data(
    struct zwlr_layer_shell_v1 *zwlr_layer_shell_v1) {
  return wl_proxy_get_user_data((struct wl_proxy *)zwlr_layer_shell_v1);
}

static inline uint32_t zwlr_layer_shell_v1_get_version(
    struct zwlr_layer_shell_v1 *zwlr_layer_shell_v1) {
  return wl_proxy_get_version((struct wl_proxy *)zwlr_layer_shell_v1);
}

static inline struct zwlr_layer_surface_v1 *
zwlr_layer_shell_v1_get_layer_surface(
    struct zwlr_layer_shell_v1 *zwlr_layer_shell_v1, struct wl_surface *surface,
    struct wl_output *output, uint32_t layer, const char *namespace) {
  struct wl_proxy *id;

  id = wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_shell_v1,
      ZWLR_LAYER_SHELL_V1_GET_LAYER_SURFACE, &zwlr_layer_surface_v1_interface,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_shell_v1), 0, NULL,
      surface, output, layer, namespace);

  return (struct zwlr_layer_surface_v1 *)id;
}

static inline void
zwlr_layer_shell_v1_destroy(struct zwlr_layer_shell_v1 *zwlr_layer_shell_v1) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_shell_v1, ZWLR_LAYER_SHELL_V1_DESTROY, NULL,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_shell_v1),
      WL_MARSHAL_FLAG_DESTROY);
}

#ifndef ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ENUM
#define ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ENUM
enum zwlr_layer_surface_v1_keyboard_interactivity {
  ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE = 0,
  ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE = 1,
  ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND = 2,
};
#define ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND_SINCE_VERSION 4
#endif

#ifndef ZWLR_LAYER_SURFACE_V1_ERROR_ENUM
#define ZWLR_LAYER_SURFACE_V1_ERROR_ENUM
enum zwlr_layer_surface_v1_error {
  ZWLR_LAYER_SURFACE_V1_ERROR_INVALID_SURFACE_STATE = 0,
  ZWLR_LAYER_SURFACE_V1_ERROR_INVALID_SIZE = 1,
  ZWLR_LAYER_SURFACE_V1_ERROR_INVALID_ANCHOR = 2,
  ZWLR_LAYER_SURFACE_V1_ERROR_INVALID_KEYBOARD_INTERACTIVITY = 3,
  ZWLR_LAYER_SURFACE_V1_ERROR_INVALID_EXCLUSIVE_EDGE = 4,
};
#endif

#ifndef ZWLR_LAYER_SURFACE_V1_ANCHOR_ENUM
#define ZWLR_LAYER_SURFACE_V1_ANCHOR_ENUM
enum zwlr_layer_surface_v1_anchor {
  ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP = 1,
  ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM = 2,
  ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT = 4,
  ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT = 8,
};
#endif

struct zwlr_layer_surface_v1_listener {
  void (*configure)(void *data,
                    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1,
                    uint32_t serial, uint32_t width, uint32_t height);
  void (*closed)(void *data,
                 struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1);
};

static inline int zwlr_layer_surface_v1_add_listener(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1,
    const struct zwlr_layer_surface_v1_listener *listener, void *data) {
  return wl_proxy_add_listener((struct wl_proxy *)zwlr_layer_surface_v1,
                               (void (**)(void))listener, data);
}

#define ZWLR_LAYER_SURFACE_V1_SET_SIZE 0
#define ZWLR_LAYER_SURFACE_V1_SET_ANCHOR 1
#define ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_ZONE 2
#define ZWLR_LAYER_SURFACE_V1_SET_MARGIN 3
#define ZWLR_LAYER_SURFACE_V1_SET_KEYBOARD_INTERACTIVITY 4
#define ZWLR_LAYER_SURFACE_V1_GET_POPUP 5
#define ZWLR_LAYER_SURFACE_V1_ACK_CONFIGURE 6
#define ZWLR_LAYER_SURFACE_V1_DESTROY 7
#define ZWLR_LAYER_SURFACE_V1_SET_LAYER 8
#define ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_EDGE 9

#define ZWLR_LAYER_SURFACE_V1_CONFIGURE_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_CLOSED_SINCE_VERSION 1

#define ZWLR_LAYER_SURFACE_V1_SET_SIZE_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_SET_ANCHOR_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_ZONE_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_SET_MARGIN_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_SET_KEYBOARD_INTERACTIVITY_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_GET_POPUP_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_ACK_CONFIGURE_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_DESTROY_SINCE_VERSION 1
#define ZWLR_LAYER_SURFACE_V1_SET_LAYER_SINCE_VERSION 2
#define ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_EDGE_SINCE_VERSION 5

static inline void zwlr_layer_surface_v1_set_user_data(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, void *user_data) {
  wl_proxy_set_user_data((struct wl_proxy *)zwlr_layer_surface_v1, user_data);
}

static inline void *zwlr_layer_surface_v1_get_user_data(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1) {
  return wl_proxy_get_user_data((struct wl_proxy *)zwlr_layer_surface_v1);
}

static inline uint32_t zwlr_layer_surface_v1_get_version(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1) {
  return wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1);
}

static inline void zwlr_layer_surface_v1_set_size(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, uint32_t width,
    uint32_t height) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1, ZWLR_LAYER_SURFACE_V1_SET_SIZE,
      NULL, wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0,
      width, height);
}

static inline void zwlr_layer_surface_v1_set_anchor(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, uint32_t anchor) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1,
      ZWLR_LAYER_SURFACE_V1_SET_ANCHOR, NULL,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0,
      anchor);
}

static inline void zwlr_layer_surface_v1_set_exclusive_zone(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, int32_t zone) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1,
      ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_ZONE, NULL,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0, zone);
}

static inline void zwlr_layer_surface_v1_set_margin(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, int32_t top,
    int32_t right, int32_t bottom, int32_t left) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1,
      ZWLR_LAYER_SURFACE_V1_SET_MARGIN, NULL,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0, top,
      right, bottom, left);
}

static inline void zwlr_layer_surface_v1_set_keyboard_interactivity(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1,
    uint32_t keyboard_interactivity) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1,
      ZWLR_LAYER_SURFACE_V1_SET_KEYBOARD_INTERACTIVITY, NULL,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0,
      keyboard_interactivity);
}

static inline void zwlr_layer_surface_v1_get_popup(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1,
    struct xdg_popup *popup) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1, ZWLR_LAYER_SURFACE_V1_GET_POPUP,
      NULL, wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0,
      popup);
}

static inline void zwlr_layer_surface_v1_ack_configure(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, uint32_t serial) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1,
      ZWLR_LAYER_SURFACE_V1_ACK_CONFIGURE, NULL,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0,
      serial);
}

static inline void zwlr_layer_surface_v1_destroy(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1, ZWLR_LAYER_SURFACE_V1_DESTROY,
      NULL, wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1),
      WL_MARSHAL_FLAG_DESTROY);
}

static inline void zwlr_layer_surface_v1_set_layer(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, uint32_t layer) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1, ZWLR_LAYER_SURFACE_V1_SET_LAYER,
      NULL, wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0,
      layer);
}

static inline void zwlr_layer_surface_v1_set_exclusive_edge(
    struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1, uint32_t edge) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)zwlr_layer_surface_v1,
      ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_EDGE, NULL,
      wl_proxy_get_version((struct wl_proxy *)zwlr_layer_surface_v1), 0, edge);
}

#ifdef __cplusplus
}
#endif

#endif
