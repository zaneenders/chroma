import Chroma
import Foundation
import Observation

struct ChatMessage: Identifiable {
  enum Author: String {
    case you = "YOU"
    case chroma = "CHROMA"
  }
  let id: Int
  let author: Author
  var text: String
}

@Observable @MainActor
final class ChatSession: Identifiable {
  let id: Int
  let title: String
  let subtitle: String
  var draft = ""
  private(set) var messages: [ChatMessage]
  private(set) var isResponding = false
  let scroll = ScrollViewController()
  let input = FocusTarget()
  private let automaticallyStreams: Bool
  @ObservationIgnored private var replyTask: Task<Void, Never>?
  @ObservationIgnored private var remainingWords: ArraySlice<String> = []

  init(id: Int, title: String, subtitle: String, greeting: String, automaticallyStreams: Bool = true) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.automaticallyStreams = automaticallyStreams
    messages = [ChatMessage(id: 0, author: .chroma, text: greeting)]
  }

  deinit { replyTask?.cancel() }

  func send() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !isResponding else { return }
    messages.append(ChatMessage(id: messages.count, author: .you, text: text))
    messages.append(ChatMessage(id: messages.count, author: .chroma, text: ""))
    draft = ""
    remainingWords = Self.reply(to: text).components(separatedBy: " ")[...]
    isResponding = true
    scroll.scrollToBottom()
    input.focus(editing: true)
    scheduleReply()
  }

  func stopReply() {
    replyTask?.cancel()
    replyTask = nil
    remainingWords = []
    isResponding = false
    if messages.last?.text.isEmpty == true {
      messages[messages.count - 1].text = "Reply stopped."
    }
  }

  func advanceReply() {
    guard isResponding else { return }
    let words = remainingWords.prefix(3)
    let index = messages.count - 1
    messages[index].text += (messages[index].text.isEmpty ? "" : " ") + words.joined(separator: " ")
    remainingWords.removeFirst(words.count)
    if remainingWords.isEmpty {
      isResponding = false
      replyTask?.cancel()
      replyTask = nil
    } else {
      scheduleReply()
    }
  }

  private func scheduleReply() {
    replyTask?.cancel()
    replyTask = nil
    guard automaticallyStreams, isResponding else { return }
    replyTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
      guard !Task.isCancelled else { return }
      self?.advanceReply()
    }
  }

  private static func reply(to text: String) -> String {
    let text = text.lowercased()
    if ["game", "play", "tetris", "block", "controls"].contains(where: text.contains) {
      return
        "Keep the stack low and leave a clear path for the long piece. d/k move left/right, f rotates, j soft-drops, and Space drops straight to the ghost. Press s to pause and leave the board. Clear a full row to make room. Switching to Chat pauses your game, so take your time."
    }
    if ["color", "design", "interface", "ui"].contains(where: text.contains) {
      return
        "Start with less: a quiet background, comfortable spacing, and one accent for the important actions. Let the content bring the color. The pieces get the spotlight in Play; the words do the work here."
    }
    if ["swift", "chroma", "code"].contains(where: text.contains) {
      return
        "Both screens are built with Chroma. The board uses drawing primitives; the conversation uses stacks, scrolling, selectable text, and a text editor. This reply is a local script streamed a few words at a time, not an AI service."
    }
    if ["hello", "hey", "hi"].contains(text) {
      return
        "Hey! Pull up a chair. You can ask about the game, the interface, or how this demo is built. I'm a small collection of local replies, but the typing, selection, scrolling, and drafts are real."
    }
    return
      "A little space to think out loud. Try asking about the game, the design, or Chroma. This is a scripted, offline conversation: no account, no API key, and nothing sent over the network. Your draft stays here when you switch conversations."
  }
}

@Observable @MainActor
final class ChatState {
  var selectedSession = 0
  let sessions: [ChatSession]
  var session: ChatSession { sessions[selectedSession] }

  init(automaticallyStreams: Bool = true) {
    sessions = [
      ChatSession(
        id: 0, title: "The lounge", subtitle: "A break between rounds",
        greeting: "Hey, welcome in. Play a round, leave a thought, or ask me about the game. There's no rush.",
        automaticallyStreams: automaticallyStreams),
      ChatSession(
        id: 1, title: "Build notes", subtitle: "How it comes together",
        greeting:
          "Two small things, built with Chroma: a game to play and a place to talk. Curious about the code or the interface?",
        automaticallyStreams: automaticallyStreams),
      ChatSession(
        id: 2, title: "Fresh ideas", subtitle: "Leave something for later",
        greeting: "A blank page, without the pressure. Leave an idea here and come back to it after a few rounds.",
        automaticallyStreams: automaticallyStreams),
    ]
  }
}
