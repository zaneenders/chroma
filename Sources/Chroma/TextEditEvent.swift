/// One editing-mode input event: what the keyboard becomes while a text
/// field owns it.
///
/// While a ``TextField`` holds the cursor in insert mode
/// (``Interaction/isTextEditing``), the backend stops translating keys into
/// ``UICommand`` navigation and emits these instead — the same way vim
/// swaps its keymap between normal and insert mode. Events carry no device
/// information, so any backend (keyboard today, an on-screen IME tomorrow)
/// can produce them.
///
/// Text is edited as graphemes: the caret offset counts `Character`s, and
/// ``insert(_:)`` may carry several at once (key repeat, paste).
public enum TextEditEvent: Equatable, Sendable {
  /// Insert text at the caret, advancing it past the inserted text.
  case insert(String)
  /// Delete the grapheme before the caret, if any.
  case backspace
  /// Delete the grapheme after the caret, if any.
  case deleteForward
  /// Move the caret one grapheme left, clamped at the start.
  case moveCaretLeft
  /// Move the caret one grapheme right, clamped at the end.
  case moveCaretRight
  /// Move the caret to the start of the text.
  case moveCaretToStart
  /// Move the caret to the end of the text.
  case moveCaretToEnd
  /// Leave insert mode (escape, or return on a single-line field).
  case endEditing
}
