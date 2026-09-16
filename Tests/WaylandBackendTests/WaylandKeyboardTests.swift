import Chroma
import Foundation
import Glibc
import Testing

@testable import WaylandBackend

@MainActor
struct WaylandKeyboardTests {
  private func keyboard() throws -> WaylandKeyboard {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keymap = """
      xkb_keymap {
        xkb_keycodes { include "evdev+aliases(qwerty)" };
        xkb_types { include "complete" };
        xkb_compatibility { include "complete" };
        xkb_symbols { include "pc+us+inet(evdev)" };
      };
      """ + "\0"
    try Data(keymap.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let fd = url.path.withCString { unsafe open($0, O_RDONLY) }
    #expect(fd >= 0)
    let keyboard = WaylandKeyboard()
    keyboard.installKeymap(fd: fd, size: UInt32(keymap.utf8.count))
    keyboard.setKeyBindings(
      KeyBindings {
        bind("a", modifiers: .control, to: .editing(.selectAll))
        bind("c", modifiers: .control, to: .editing(.copy))
        bind("v", modifiers: .control, to: .editing(.paste))
      })
    keyboard.updateModifiers(depressed: 4, latched: 0, locked: 0, group: 0)
    return keyboard
  }

  @Test func superASelectsAllInsteadOfInsertingText() throws {
    let keyboard = try keyboard()
    defer { keyboard.cleanup() }
    keyboard.setKeyBindings(
      KeyBindings {
        bind("a", modifiers: .superKey, to: .editing(.selectAll))
      })
    keyboard.updateModifiers(depressed: 64, latched: 0, locked: 0, group: 0)
    keyboard.keyPressed(30, editing: true, editingSession: 1, now: 0)
    var commands: [Command] = []
    var events: [TextEditEvent] = []
    keyboard.drain(editingSession: 1, commands: &commands, textEvents: &events)
    #expect(events == [.selectAll])
  }

  @Test func selectAllOutsideEditorCallsSelectionHandler() throws {
    let keyboard = try keyboard()
    defer { keyboard.cleanup() }
    var selected = false
    keyboard.onSelectAll = {
      selected = true
      return true
    }
    keyboard.keyPressed(30, editing: false, editingSession: 0, now: 0)
    var commands: [Command] = []
    var events: [TextEditEvent] = []
    keyboard.drain(editingSession: 0, commands: &commands, textEvents: &events)
    #expect(selected)
    #expect(events.isEmpty)
  }

  @Test func editorSelectAllCopyAndPasteShortcuts() throws {
    let keyboard = try keyboard()
    defer { keyboard.cleanup() }
    var copied = false
    var selectedOutsideEditor = false
    keyboard.onSelectAll = {
      selectedOutsideEditor = true
      return true
    }
    keyboard.onCopy = { copied = true }
    keyboard.onPaste = { id in keyboard.completePaste(id: id, text: "pasted") }
    keyboard.keyPressed(30, editing: true, editingSession: 1, now: 0)
    keyboard.keyPressed(46, editing: true, editingSession: 1, now: 0)
    keyboard.keyPressed(47, editing: true, editingSession: 1, now: 0)
    var commands: [Command] = []
    var events: [TextEditEvent] = []
    keyboard.drain(editingSession: 1, commands: &commands, textEvents: &events)
    #expect(!selectedOutsideEditor)
    #expect(copied)
    #expect(events == [.selectAll, .insert("pasted")])
  }
}
