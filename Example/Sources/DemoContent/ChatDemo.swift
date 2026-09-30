import Chroma

struct ChatDemo: Block {
  let state: ChatState
  let shortcutModifier: KeyModifiers

  @MainActor var body: some Block {
    HStack(spacing: 16) {
      Group("Conversations") {
        VStack(spacing: 12) {
          Text("CONVERSATIONS").fontScale(0.5).foregroundColor(DemoStyle.muted).navigationIgnored()
            .padding(8)
          ForEach(state.sessions) { session in
            Interactive(action: { state.selectedSession = session.id }) { phase in
              VStack(spacing: 8) {
                Text(session.title).fontScale(0.7)
                  .foregroundColor(state.selectedSession == session.id ? DemoStyle.accent : .white)
                Text(session.subtitle).fontScale(0.48).foregroundColor(DemoStyle.muted)
                Text(session.isResponding ? "Replying..." : session.draft.isEmpty ? "" : "Draft saved")
                  .fontScale(0.45).foregroundColor(DemoStyle.accent)
              }.padding(16).sizing(x: .grow)
                .roundedBackground(
                  state.selectedSession == session.id || phase != .idle ? DemoStyle.card : DemoStyle.panel,
                  radius: 10)
            }
          }
          Spacer()
          Text("A local conversation.\nNo account. No network.").fontScale(0.5)
            .foregroundColor(DemoStyle.muted).navigationIgnored().padding(8)
        }.padding(12)
      }.sizing(x: .fixed(248), y: .grow).roundedBackground(DemoStyle.panel, radius: 14)
      conversation(state.session).id(state.session.id)
    }.sizing(x: .grow, y: .grow)
  }

  @MainActor private func conversation(_ session: ChatSession) -> some Block {
    Group("Conversation") {
      VStack(spacing: 18) {
        HStack {
          VStack(spacing: 6) {
            Text(session.title).fontScale(1.05).navigationIgnored()
            Text("Scripted replies, streamed locally.").fontScale(0.52)
              .foregroundColor(DemoStyle.muted).navigationIgnored()
          }
          Spacer()
          Text("OFFLINE DEMO").fontScale(0.45).foregroundColor(DemoStyle.accent).navigationIgnored()
        }
        ScrollView("Messages", sticksToBottom: true, controller: session.scroll) {
          ForEach(session.messages) { message in
            VStack(spacing: 10) {
              Text(message.author.rawValue).fontScale(0.45)
                .foregroundColor(message.author == .you ? DemoStyle.muted : DemoStyle.accent)
                .navigationIgnored()
              Text(message.text.isEmpty ? "..." : message.text).fontScale(0.68).wrapping().selectable()
            }.padding(18).sizing(x: .grow)
              .roundedBackground(message.author == .you ? DemoStyle.card : DemoStyle.background, radius: 10)
              .padding(4)
          }
        }.sizing(x: .grow, y: .grow)
        HStack(spacing: 8) {
          if session.isResponding {
            ProgressIndicator(color: DemoStyle.accent, diameter: 12)
          }
          Text(session.isResponding ? "Chroma is replying..." : "All caught up")
            .fontScale(0.5).foregroundColor(DemoStyle.muted).navigationIgnored()
          Spacer()
          Button("Latest", fontScale: 0.5) { session.scroll.scrollToBottom() }
        }
        composer(session)
      }.padding(24)
    }.sizing(x: .grow, y: .grow).roundedBackground(DemoStyle.panel, radius: 14)
  }

  @MainActor private func composer(_ session: ChatSession) -> some Block {
    Group("Composer") {
      VStack(spacing: 10) {
        TextEditor(
          "Say something...", fontScale: 0.65, lineLimits: 2...5, padding: 14,
          text: { session.draft }, onChange: { session.draft = $0 }
        )
        .focusTarget(session.input)
        HStack {
          Text(
            shortcutModifier == .command
              ? "Enter for a new line / Cmd+Enter to send" : "Enter for a new line / Ctrl+Enter to send"
          )
          .fontScale(0.45).foregroundColor(DemoStyle.muted).navigationIgnored()
          Spacer()
          Button(
            session.isResponding ? "Stop reply" : "Send", fontScale: 0.6,
            style: DemoStyle.selectedButton
          ) {
            if session.isResponding { session.stopReply() } else { session.send() }
          }
        }
      }
    }
    .keyBindings { bind(.enter, modifiers: shortcutModifier, to: .application("chat.send")) }
    .onCommand(.application("chat.send")) {
      session.send()
      return .handled
    }
  }
}
