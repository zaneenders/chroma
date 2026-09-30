import Chroma
import ChromaTesting
import Testing

@testable import DemoContent

@MainActor
struct ChatTests {
  @Test func emptySendIsIgnoredAndReplyStreamsInChunks() {
    let state = ChatState(automaticallyStreams: false)
    let session = state.session
    session.draft = " \n "
    session.send()
    #expect(session.messages.count == 1)
    #expect(!session.isResponding)
    session.draft = " Hello "
    session.send()
    #expect(session.messages.count == 3)
    #expect(session.messages[1].text == "Hello")
    #expect(session.messages[2].text.isEmpty)
    #expect(session.draft.isEmpty)
    #expect(session.isResponding)
    session.advanceReply()
    let first = session.messages[2].text
    #expect(!first.isEmpty)
    #expect(session.isResponding)
    for _ in 0..<100 { session.advanceReply() }
    #expect(!session.isResponding)
    #expect(session.messages[2].text.hasPrefix(first))
    #expect(session.messages[2].text.contains("local replies"))
    #expect(state.sessions[1].messages.count == 1)
  }

  @Test func concurrentSendKeepsDraftAndStopKeepsPartialReply() {
    let session = ChatState(automaticallyStreams: false).session
    session.draft = "How does the game work?"
    session.send()
    session.advanceReply()
    let partial = session.messages.last?.text
    session.draft = "Next question"
    session.send()
    #expect(session.messages.count == 3)
    #expect(session.draft == "Next question")
    session.stopReply()
    session.advanceReply()
    #expect(session.messages.last?.text == partial)
    #expect(!session.isResponding)
    session.send()
    #expect(session.messages.count == 5)
    #expect(session.draft.isEmpty)
  }

  @Test func conversationSwitchesPreserveDraftsAndReplies() {
    let state = ChatState(automaticallyStreams: false)
    state.session.draft = "First draft"
    state.selectedSession = 1
    state.session.draft = "Tell me about Chroma"
    state.session.send()
    state.session.draft = "Second draft"
    state.selectedSession = 0
    #expect(state.session.draft == "First draft")
    state.sessions[1].advanceReply()
    #expect(state.sessions[1].isResponding)
    state.selectedSession = 1
    #expect(state.session.draft == "Second draft")
    #expect(state.session.messages[1].text == "Tell me about Chroma")
  }

  @Test func conversationSwitchDoesNotTransferComposerFocusOrSelection() throws {
    let state = DemoState(automaticallyUpdates: false)
    state.open(.chat)
    let ui = try NavigationTestHost(app: DemoApplication(state: state, shortcutModifier: .command))
    let first = state.chat.session
    first.draft = "First draft"
    first.input.focus(editing: true)
    ui.host.render()
    ui.press(KeyboardInput(chord: KeyChord("a", modifiers: .command)))
    #expect(first.input.isEditing)

    state.chat.selectedSession = 1
    let second = state.chat.session
    second.draft = "Second draft"
    ui.host.render()
    #expect(!first.input.isFocused)
    #expect(!second.input.isFocused)
    #expect(!second.input.isEditing)

    second.input.focus(editing: true)
    ui.host.render()
    ui.press("!")
    #expect(second.draft == "Second draft!")
    #expect(first.draft == "First draft")

    state.chat.selectedSession = 0
    ui.host.render()
    #expect(!second.input.isFocused)
    #expect(!first.input.isEditing)
    first.input.focus(editing: true)
    ui.host.render()
    ui.press("!")
    #expect(first.draft == "First draft!")
  }

  @Test func historyDoesNotJumpWhenAReplyStreams() {
    let state = ChatState(automaticallyStreams: false)
    let session = state.session
    for _ in 0..<12 {
      session.draft = "Tell me about the game"
      session.send()
      for _ in 0..<100 { session.advanceReply() }
    }
    let host = HeadlessHost(size: Size(width: 1000, height: 600))
    host.content = DeferredBlock { ChatDemo(state: state, shortcutModifier: .command) }
    host.render()
    session.scroll.scrollToBottom()
    host.render()
    #expect(session.scroll.offset > 0)
    session.draft = "Another question"
    session.send()
    host.render()
    session.scroll.scroll(to: 100)
    host.render()
    let offset = session.scroll.offset
    session.advanceReply()
    host.render()
    #expect(session.scroll.offset == offset)
    state.selectedSession = 1
    host.render()
    state.selectedSession = 0
    host.render()
    #expect(session.scroll.offset == offset)
  }

  @Test func historyFollowsStreamingOnlyWhileAtTheBottom() {
    let state = ChatState(automaticallyStreams: false)
    let session = state.session
    let host = HeadlessHost(size: Size(width: 800, height: 430))
    host.content = DeferredBlock { ChatDemo(state: state, shortcutModifier: .command) }
    host.render()
    session.draft = "Tell me about the game"
    session.send()
    host.render()
    let initialOffset = session.scroll.offset
    for _ in 0..<100 {
      session.advanceReply()
      host.render()
    }
    #expect(session.scroll.offset > initialOffset)
    let followedOffset = session.scroll.offset
    session.scroll.scrollToBottom()
    host.render()
    #expect(session.scroll.offset == followedOffset)
  }

  @Test func replyRunsAutomaticallyAndStopCancelsIt() async throws {
    let session = ChatState().session
    session.draft = "Hello"
    session.send()
    let deadline = ContinuousClock.now + .seconds(4)
    while session.messages.last?.text.isEmpty == true && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(session.messages.last?.text.isEmpty == false)
    session.stopReply()
    let text = session.messages.last?.text
    try await Task.sleep(for: .milliseconds(150))
    #expect(session.messages.last?.text == text)
    #expect(!session.isResponding)
  }

  @Test func stoppedEmptyReplyHasAnExplanation() {
    let session = ChatState(automaticallyStreams: false).session
    session.draft = "Hello"
    session.send()
    session.stopReply()
    #expect(session.messages.last?.text == "Reply stopped.")
    #expect(!session.isResponding)
  }

  @Test func streamingDoesNotRetainSession() {
    weak var released: ChatSession?
    do {
      let session = ChatState().session
      released = session
      session.draft = "Hello"
      session.send()
    }
    #expect(released == nil)
  }
}
