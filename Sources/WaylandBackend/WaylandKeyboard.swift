#if WAYLAND_BACKEND

import Chroma
import CXKBKeyboard

@MainActor
final class WaylandKeyboard {
  private var keyboard: OpaquePointer?
  private var bindings = KeyBindings()
  private var pendingCommands: [Command] = []
  private var pendingTextEvents: [TextEditEvent] = []
  private var repeatRate: Int32 = 0
  private var repeatDelay: Int32 = 0
  private var repeatingKey: UInt32?
  private var nextRepeatTime: Double?

  func setKeyBindings(_ bindings: KeyBindings) {
    self.bindings = bindings
  }

  func cleanup() {
    if let keyboard { chroma_xkb_keyboard_destroy(keyboard) }
    keyboard = nil
    pendingCommands.removeAll(keepingCapacity: false)
    pendingTextEvents.removeAll(keepingCapacity: false)
    cancelRepeat()
  }

  func installKeymap(fd: Int32, size: UInt32) {
    if let keyboard { chroma_xkb_keyboard_destroy(keyboard) }
    keyboard = chroma_xkb_keyboard_create(fd, size)
  }

  func updateModifiers(depressed: UInt32, latched: UInt32, locked: UInt32, group: UInt32) {
    chroma_xkb_keyboard_update_mask(keyboard, depressed, latched, locked, group)
  }

  func updateRepeatInfo(rate: Int32, delay: Int32) {
    repeatRate = max(0, rate)
    repeatDelay = max(0, delay)
    if repeatRate == 0 { cancelRepeat() }
  }

  func keyPressed(_ key: UInt32, editing: Bool, now: Double) {
    cancelRepeat()
    dispatchKey(key, editing: editing)
    guard repeatRate > 0, let keyboard,
      chroma_xkb_keyboard_key_repeats(keyboard, key) != 0
    else { return }
    repeatingKey = key
    nextRepeatTime = now + Double(repeatDelay) / 1_000
  }

  func keyReleased(_ key: UInt32) {
    if repeatingKey == key { cancelRepeat() }
  }

  func focusLost() {
    cancelRepeat()
    chroma_xkb_keyboard_reset_compose(keyboard)
  }

  func dispatchRepeats(editing: Bool, now: Double) -> Bool {
    guard let key = repeatingKey, var deadline = nextRepeatTime, repeatRate > 0,
      now >= deadline
    else { return false }
    let interval = 1 / Double(repeatRate)
    repeat {
      dispatchKey(key, editing: editing)
      deadline += interval
    } while now >= deadline
    nextRepeatTime = deadline
    return true
  }

  var repeatDeadline: Double? { nextRepeatTime }

  private func dispatchKey(_ key: UInt32, editing: Bool) {
    guard let keyboard else { return }
    let symbol = chroma_xkb_keyboard_keysym(keyboard, key)
    guard let chord = keyChord(symbol: symbol, keyboard: keyboard) else {
      if editing, let text = text(for: key, keyboard: keyboard) {
        pendingTextEvents.append(.insert(text))
      }
      return
    }

    let resolution = bindings.command(for: chord)
    if editing {
      if case .some(.some(let command)) = resolution, case .editing(let event) = command {
        applyEditingEvent(event)
        return
      }
      if case .some(.none) = resolution { return }
      if let text = text(for: key, keyboard: keyboard) {
        pendingTextEvents.append(.insert(text))
        return
      }
    }
    if let resolution, let command = resolution {
      if case .editing(let event) = command {
        applyEditingEvent(event)
      } else {
        pendingCommands.append(command)
      }
    }
  }

  func drain(commands: inout [Command], textEvents: inout [TextEditEvent]) {
    commands.append(contentsOf: pendingCommands)
    textEvents.append(contentsOf: pendingTextEvents)
    pendingCommands.removeAll(keepingCapacity: true)
    pendingTextEvents.removeAll(keepingCapacity: true)
  }

  private func cancelRepeat() {
    repeatingKey = nil
    nextRepeatTime = nil
  }

  private func applyEditingEvent(_ event: TextEditEvent) {
    switch event {
    case .copy, .paste:
      // Wayland clipboard protocol support is not wired up yet.
      break
    default:
      pendingTextEvents.append(event)
    }
  }

  private func text(for key: UInt32, keyboard: OpaquePointer) -> String? {
    guard !modifier("Control", keyboard: keyboard), !modifier("Logo", keyboard: keyboard) else {
      return nil
    }
    var buffer = [CChar](repeating: 0, count: 64)
    let count = chroma_xkb_keyboard_utf8(keyboard, key, &buffer, Int32(buffer.count))
    guard count > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  private func keyChord(symbol: UInt32, keyboard: OpaquePointer) -> KeyChord? {
    let key: Key
    switch symbol {
    case 0xff08: key = .backspace
    case 0xff09: key = .tab
    case 0xff0d, 0xff8d: key = .enter
    case 0xff1b: key = .escape
    case 0xffff, 0xff9f: key = .delete
    case 0xff50, 0xff95: key = .home
    case 0xff51, 0xff96: key = .leftArrow
    case 0xff52, 0xff97: key = .upArrow
    case 0xff53, 0xff98: key = .rightArrow
    case 0xff54, 0xff99: key = .downArrow
    case 0xff55, 0xff9a: key = .pageUp
    case 0xff56, 0xff9b: key = .pageDown
    case 0xff57, 0xff9c: key = .end
    case 0x20: key = .space
    default:
      guard symbol >= 0x20, symbol <= 0x7e,
        let scalar = UnicodeScalar(symbol)
      else { return nil }
      key = .character(Character(String(scalar).lowercased()))
    }
    var modifiers: KeyModifiers = []
    if modifier("Shift", keyboard: keyboard) { modifiers.insert(.shift) }
    if modifier("Control", keyboard: keyboard) { modifiers.insert(.control) }
    if modifier("Mod1", keyboard: keyboard) { modifiers.insert(.option) }
    if modifier("Logo", keyboard: keyboard) { modifiers.insert(.command) }
    return KeyChord(key, modifiers: modifiers)
  }

  private func modifier(_ name: String, keyboard: OpaquePointer) -> Bool {
    name.withCString { chroma_xkb_keyboard_modifier_active(keyboard, $0) != 0 }
  }
}

#endif
