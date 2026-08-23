#ifndef CHROMA_XKB_KEYBOARD_H
#define CHROMA_XKB_KEYBOARD_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct chroma_xkb_keyboard chroma_xkb_keyboard;

chroma_xkb_keyboard *chroma_xkb_keyboard_create(int32_t fd, uint32_t size);
void chroma_xkb_keyboard_destroy(chroma_xkb_keyboard *keyboard);
void chroma_xkb_keyboard_update_mask(
    chroma_xkb_keyboard *keyboard,
    uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group);
uint32_t chroma_xkb_keyboard_keysym(chroma_xkb_keyboard *keyboard, uint32_t wayland_key);
int32_t chroma_xkb_keyboard_key_repeats(
    chroma_xkb_keyboard *keyboard, uint32_t wayland_key);
int32_t chroma_xkb_keyboard_utf8(
    chroma_xkb_keyboard *keyboard, uint32_t wayland_key, char *buffer, int32_t capacity);
int32_t chroma_xkb_keyboard_modifier_active(chroma_xkb_keyboard *keyboard, const char *name);

#ifdef __cplusplus
}
#endif

#endif
