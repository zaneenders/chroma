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
    let bindings = KeyBindings {
      bind("a", modifiers: .control, to: .editing(.selectAll))
      bind("c", modifiers: .control, to: .editing(.copy))
      bind("v", modifiers: .control, to: .editing(.paste))
    }
    keyboard.resolve = { bindings.resolve($0, isTextEditing: $1) }
    keyboard.updateModifiers(depressed: 4, latched: 0, locked: 0, group: 0)
    return keyboard
  }

  @Test func superASelectsAllInsteadOfInsertingText() throws {
    let keyboard = try keyboard()
    defer { keyboard.cleanup() }
    let bindings = KeyBindings {
      bind("a", modifiers: .superKey, to: .editing(.selectAll))
    }
    keyboard.resolve = { bindings.resolve($0, isTextEditing: $1) }
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
  @Test func delayedRepeatsDeliverEveryEventBeforeTheNextFrame() throws {
    let keyboard = try keyboard()
    defer { keyboard.cleanup() }
    keyboard.updateModifiers(depressed: 0, latched: 0, locked: 0, group: 0)
    keyboard.updateRepeatInfo(rate: 20, delay: 100)
    var events: [TextEditEvent] = []
    var deliveries = 0
    keyboard.onInputAvailable = {
      deliveries += 1
      var commands: [Command] = []
      keyboard.drain(editingSession: 1, commands: &commands, textEvents: &events)
    }
    keyboard.keyPressed(30, editing: true, editingSession: 1, now: 0)
    #expect(keyboard.dispatchRepeats(editing: true, editingSession: 1, now: 0.26))
    #expect(deliveries == 5)
    #expect(events == Array(repeating: .insert("a"), count: 5))
  }

  @Test func nativeDispatchUsesRefreshedEditingSessionForEveryRepeat() throws {
    let keyboard = try keyboard()
    defer { keyboard.cleanup() }
    keyboard.updateModifiers(depressed: 0, latched: 0, locked: 0, group: 0)
    keyboard.updateRepeatInfo(rate: 20, delay: 100)
    var session = 1
    var dispatches = 0
    var events: [TextEditEvent] = []
    keyboard.dispatch = { _, deliver in
      dispatches += 1
      session += 1
      deliver(.text(.insert("a")), true, session)
    }
    keyboard.onInputAvailable = {
      var commands: [Command] = []
      keyboard.drain(editingSession: session, commands: &commands, textEvents: &events)
    }
    keyboard.keyPressed(30, editing: false, editingSession: 0, now: 0)
    #expect(keyboard.dispatchRepeats(editing: false, editingSession: 0, now: 0.26))
    #expect(dispatches == 5)
    #expect(events == Array(repeating: .insert("a"), count: 5))
  }

}
