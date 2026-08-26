#include "xkb_keyboard.h"

#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-compose.h>

struct chroma_xkb_keyboard {
  struct xkb_context *context;
  struct xkb_keymap *keymap;
  struct xkb_state *state;
  struct xkb_compose_table *compose_table;
  struct xkb_compose_state *compose_state;
};

static const char *compose_locale(void) {
  const char *locale = getenv("LC_ALL");
  if (locale != NULL && locale[0] != '\0') return locale;
  locale = getenv("LC_CTYPE");
  if (locale != NULL && locale[0] != '\0') return locale;
  locale = getenv("LANG");
  return locale != NULL && locale[0] != '\0' ? locale : "C";
}

chroma_xkb_keyboard *chroma_xkb_keyboard_create(int32_t fd, uint32_t size) {
  void *mapping = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (mapping == MAP_FAILED) return NULL;

  chroma_xkb_keyboard *keyboard = calloc(1, sizeof(*keyboard));
  if (keyboard == NULL) {
    munmap(mapping, size);
    return NULL;
  }
  keyboard->context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  if (keyboard->context != NULL) {
    keyboard->keymap = xkb_keymap_new_from_string(
        keyboard->context, mapping, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
  }
  munmap(mapping, size);
  if (keyboard->keymap != NULL) {
    keyboard->state = xkb_state_new(keyboard->keymap);
  }
  if (keyboard->state == NULL) {
    chroma_xkb_keyboard_destroy(keyboard);
    return NULL;
  }
  keyboard->compose_table = xkb_compose_table_new_from_locale(
      keyboard->context, compose_locale(), XKB_COMPOSE_COMPILE_NO_FLAGS);
  if (keyboard->compose_table != NULL) {
    keyboard->compose_state = xkb_compose_state_new(
        keyboard->compose_table, XKB_COMPOSE_STATE_NO_FLAGS);
  }
  return keyboard;
}

void chroma_xkb_keyboard_destroy(chroma_xkb_keyboard *keyboard) {
  if (keyboard == NULL) return;
  xkb_compose_state_unref(keyboard->compose_state);
  xkb_compose_table_unref(keyboard->compose_table);
  xkb_state_unref(keyboard->state);
  xkb_keymap_unref(keyboard->keymap);
  xkb_context_unref(keyboard->context);
  free(keyboard);
}

void chroma_xkb_keyboard_update_mask(
    chroma_xkb_keyboard *keyboard,
    uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {
  if (keyboard == NULL) return;
  xkb_state_update_mask(keyboard->state, depressed, latched, locked, 0, 0, group);
}

uint32_t chroma_xkb_keyboard_keysym(chroma_xkb_keyboard *keyboard, uint32_t wayland_key) {
  if (keyboard == NULL) return 0;
  return xkb_state_key_get_one_sym(keyboard->state, wayland_key + 8);
}

int32_t chroma_xkb_keyboard_key_repeats(
    chroma_xkb_keyboard *keyboard, uint32_t wayland_key) {
  if (keyboard == NULL) return 0;
  return xkb_keymap_key_repeats(keyboard->keymap, wayland_key + 8) > 0;
}

int32_t chroma_xkb_keyboard_utf8(
    chroma_xkb_keyboard *keyboard, uint32_t wayland_key, char *buffer, int32_t capacity) {
  if (keyboard == NULL || buffer == NULL || capacity <= 0) return 0;

  if (keyboard->compose_state != NULL) {
    xkb_keysym_t symbol = xkb_state_key_get_one_sym(keyboard->state, wayland_key + 8);
    if (xkb_compose_state_feed(keyboard->compose_state, symbol) == XKB_COMPOSE_FEED_ACCEPTED) {
      switch (xkb_compose_state_get_status(keyboard->compose_state)) {
        case XKB_COMPOSE_COMPOSING:
          return 0;
        case XKB_COMPOSE_COMPOSED: {
          int32_t count = (int32_t)xkb_compose_state_get_utf8(
              keyboard->compose_state, buffer, (size_t)capacity);
          xkb_compose_state_reset(keyboard->compose_state);
          return count;
        }
        case XKB_COMPOSE_CANCELLED:
          xkb_compose_state_reset(keyboard->compose_state);
          break;
        case XKB_COMPOSE_NOTHING:
          break;
      }
    }
  }

  return xkb_state_key_get_utf8(keyboard->state, wayland_key + 8, buffer, (size_t)capacity);
}

void chroma_xkb_keyboard_reset_compose(chroma_xkb_keyboard *keyboard) {
  if (keyboard != NULL && keyboard->compose_state != NULL) {
    xkb_compose_state_reset(keyboard->compose_state);
  }
}

int32_t chroma_xkb_keyboard_modifier_active(chroma_xkb_keyboard *keyboard, const char *name) {
  if (keyboard == NULL) return 0;
  return xkb_state_mod_name_is_active(keyboard->state, name, XKB_STATE_MODS_EFFECTIVE) > 0;
}
