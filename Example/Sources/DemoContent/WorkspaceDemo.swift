import Chroma
import Foundation
import Observation

@Observable @MainActor
final class WorkspaceSession: Identifiable {
  let id: Int
  let title: String
  let subtitle: String
  var draft = ""
  var messages: [WorkspaceMessage]
  var concise = true
  let scroll = ScrollViewController()
  let input = FocusTarget()

  init(id: Int, title: String, subtitle: String, messages: [String]) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.messages = messages.enumerated().map {
      WorkspaceMessage(id: $0.offset, author: "CHROMA", text: $0.element)
    }
  }

  func send() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    messages.append(WorkspaceMessage(id: messages.count, author: "YOU", text: text))
    messages.append(
      WorkspaceMessage(
        id: messages.count, author: "CHROMA",
        text: concise
          ? "Draft received. Try another session, then find your way back."
          : "This reply is simulated locally. Your conversation, draft and scroll position stay here while you explore. Nothing is sent over the network."
      ))
    draft = ""
  }
}

struct WorkspaceMessage: Identifiable {
  let id: Int
  let author: String
  let text: String
  var saved = false
}

@Observable @MainActor
final class WorkspaceState {
  var selectedSession = 0
  var showsGallery = false
  var status = "Start anywhere: d / f / j / k selects a section. l enters it."
  let sessions = [
    WorkspaceSession(
      id: 0, title: "First steps", subtitle: "Learn by moving",
      messages: [
        "Welcome to Chroma. This is a GUI you can explore like a tree.",
        "MOVE: d left, f up, j down, k right. l goes in. s comes out.",
        "Plain movement stays inside a section. Shift + d / f / j / k changes sections without diving into them.",
        "Try the composer below. Select the input and press l to EDIT. Escape returns to MOVE; your draft stays put.",
        "Now press Shift+d to select Sessions. Enter, open Field notes, then return here. Groups remember where you left off.",
        "Messages are groups too. Enter one, then enter its text. Shift+arrows selects a passage; Cmd/Ctrl+C copies it. Escape returns to MOVE.",
        "Scrolling follows your selection only when needed. Sending a message will not drag you away from what you are reading.",
        "Use Latest when you want the bottom. There is no automatic follow mode in this workspace.",
      ]),
    WorkspaceSession(
      id: 1, title: "Field notes", subtitle: "A place to leave a draft",
      messages: [
        "A good navigation tree describes meaning, not every layout wrapper.",
        "A row can contain text, badges and buttons without making each decorative detail a stop.",
        "Group boundaries are explicit. Moving a button into an HStack should not add another level.",
        "Leave yourself a note below, then visit another session. Your unfinished thought will be waiting.",
      ]),
    WorkspaceSession(
      id: 2, title: "The long way", subtitle: "Explore a deeper history",
      messages: (1...24).map {
        "Waypoint \($0). Move between messages with f / j. Enter a message with l, or leave the entire history with s. You do not need to climb back to the first message."
      }),
  ]

  var session: WorkspaceSession { sessions[selectedSession] }

  func open(_ session: WorkspaceSession) {
    selectedSession = session.id
    status = "Opened \(session.title). Shift+k moves toward the conversation; l enters it."
  }
}

private enum WorkspacePalette {
  static let background = Color(r: 0.035, g: 0.047, b: 0.075, a: 1)
  static let panel = Color(r: 0.065, g: 0.082, b: 0.12, a: 1)
  static let card = Color(r: 0.09, g: 0.11, b: 0.16, a: 1)
  static let accent = Color(r: 0.46, g: 0.87, b: 0.77, a: 1)
  static let muted = Color(r: 0.56, g: 0.63, b: 0.73, a: 1)
}

struct WorkspaceDemo: Block {
  let state: WorkspaceState
  let gallery: PerformanceDemoState

  @MainActor var body: some Block {
    VStack(spacing: 12) {
      Group("Tabs") {
        HStack(spacing: 12) {
          VStack(spacing: 3) {
            Text("CHROMA").fontScale(0.8).foregroundColor(WorkspacePalette.accent).navigationIgnored()
            Text("A GUI you can move through").fontScale(0.38).foregroundColor(WorkspacePalette.muted)
              .navigationIgnored()
          }
          Spacer()
          Button(state.showsGallery ? "Workspace" : "Workspace *", fontScale: 0.5) {
            state.showsGallery = false
          }
          Button(state.showsGallery ? "Render gallery *" : "Render gallery", fontScale: 0.5) {
            state.showsGallery = true
          }
        }.padding(12)
      }.roundedBackground(WorkspacePalette.panel, radius: 10)

      if state.showsGallery {
        Group("Render gallery") {
          PerformanceDemo(state: gallery)
        }.sizing(x: .grow, y: .grow)
      } else {
        HStack(spacing: 12) {
          sidebar
          ForEach([state.session]) { session in
            ConversationPanel(session: session, workspace: state)
          }
        }.sizing(x: .grow, y: .grow)
      }
      NavigationGuide()
      Text(state.status).fontScale(0.4).foregroundColor(WorkspacePalette.muted)
        .navigationIgnored().sizing(x: .grow).clipped()
    }
    .padding(16)
    .background(WorkspacePalette.background)
  }

  @MainActor private var sidebar: some Block {
    Group("Sessions") {
      VStack(spacing: 14) {
        Text("SESSIONS").fontScale(0.42).foregroundColor(WorkspacePalette.accent).navigationIgnored()
        ForEach(state.sessions) { session in
          Interactive(action: { state.open(session) }) { phase in
            VStack(spacing: 7) {
              Text((state.selectedSession == session.id ? "> " : "  ") + session.title).fontScale(0.55)
              Text(session.subtitle).fontScale(0.38).foregroundColor(WorkspacePalette.muted)
              Text("\(session.messages.count) messages" + (session.draft.isEmpty ? "" : " / draft"))
                .fontScale(0.35).foregroundColor(WorkspacePalette.accent)
            }.padding(12).sizing(x: .grow)
              .roundedBackground(phase == .idle ? WorkspacePalette.panel : WorkspacePalette.card, radius: 8)
          }
        }
        Spacer()
        Text("THE EXPERIMENT\n\nLeave a draft.\nSwitch sessions.\nFind your way back.\n\nNo mouse required.")
          .fontScale(0.42).foregroundColor(WorkspacePalette.muted).navigationIgnored()
      }.padding(16)
    }.sizing(x: .fixed(250), y: .grow)
      .roundedBackground(WorkspacePalette.panel, radius: 10)
  }
}

private struct ConversationPanel: Block {
  let session: WorkspaceSession
  let workspace: WorkspaceState

  @MainActor var body: some Block {
    Group("Conversation") {
      VStack(spacing: 12) {
        HStack {
          Text(session.title).fontScale(0.75).navigationIgnored()
          Spacer()
          Text("LOCAL / SIMULATED").fontScale(0.35).foregroundColor(WorkspacePalette.accent).navigationIgnored()
        }.padding(8)
        ScrollView("History", controller: session.scroll) {
          ForEach(session.messages) { message in
            MessageCard(message: message, session: session, workspace: workspace)
          }
        }.sizing(x: .grow, y: .grow)
        composer
      }.padding(12)
    }.sizing(x: .grow, y: .grow)
      .roundedBackground(WorkspacePalette.panel, radius: 10)
  }

  @MainActor private var composer: some Block {
    Group("Composer") {
      VStack(spacing: 10) {
        Text("COMPOSE / l to edit / Escape to move").fontScale(0.38)
          .foregroundColor(WorkspacePalette.accent).navigationIgnored()
        HStack(spacing: 10) {
          TextField(
            "Leave a thought here...", fontScale: 0.55,
            text: { session.draft }, onChange: { session.draft = $0 }, onSubmit: { _ in session.send() }
          )
          .focusTarget(session.input)
          Button("Send", fontScale: 0.5) { session.send() }
        }
        Group("Options") {
          HStack(spacing: 8) {
            Button(session.concise ? "Reply: brief" : "Reply: detailed", fontScale: 0.4) {
              session.concise.toggle()
            }
            Button("Latest", fontScale: 0.4) { session.scroll.scrollToBottom() }
            Button("Clear draft", fontScale: 0.4) { session.draft = "" }
          }
        }
      }.padding(12)
    }.roundedBackground(WorkspacePalette.card, radius: 8)
  }
}

private struct MessageCard: Block {
  let message: WorkspaceMessage
  let session: WorkspaceSession
  let workspace: WorkspaceState

  @MainActor var body: some Block {
    Group("Message \(message.id + 1)") {
      VStack(spacing: 10) {
        Text("\(message.author) / \(String(format: "%02d", message.id + 1))")
          .fontScale(0.35).foregroundColor(WorkspacePalette.accent).navigationIgnored()
        WrappedMessage(text: message.text)
        HStack(spacing: 8) {
          Button(message.saved ? "Saved" : "Save", fontScale: 0.35) {
            if let index = session.messages.firstIndex(where: { $0.id == message.id }) {
              session.messages[index].saved.toggle()
            }
          }
          Button("Quote", fontScale: 0.35) {
            session.draft = "> " + message.text
            workspace.status = "Quoted into the composer. Your position in history is unchanged."
          }
        }
      }.padding(14).sizing(x: .grow)
    }.roundedBackground(WorkspacePalette.card, radius: 8).padding(5)
  }
}

private struct WrappedMessage: PrimitiveBlock {
  let text: String
  var focusRule: FocusRule { .container }
  var expandsHorizontally: Bool { true }

  @MainActor private func content(width: Float, context: RenderContext) -> Text {
    let columns = max(1, Int(max(1, width) / max(1, context.fontMetrics.cellAdvance * 0.5 * context.textScale)))
    var lines: [String] = []
    var line = ""
    for word in text.split(separator: " ") {
      if !line.isEmpty, line.count + 1 + word.count > columns {
        lines.append(line)
        line = ""
      }
      if !line.isEmpty { line += " " }
      line += word
    }
    if !line.isEmpty { lines.append(line) }
    return Text(lines.joined(separator: "\n")).fontScale(0.5).selectable()
  }

  @MainActor func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let measured = BlockEngine.measure(
      content(width: proposal.width, context: context), proposal: proposal, context: context)
    return Size(width: proposal.width, height: measured.height)
  }

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content(width: rect.size.width, context: context), into: &drawList, in: rect, context: context)
  }
}

private struct NavigationGuide: PrimitiveBlock {
  var focusRule: FocusRule { .decorative }
  var expandsHorizontally: Bool { true }

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Size(width: proposal.width, height: 64)
  }

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let editing = context.interactionMode == .editing
    let mode = context.isSelectingText ? "SELECT" : editing ? "EDIT" : "MOVE"
    let location = context.navigationBreadcrumb.joined(separator: " / ")
    let hint =
      context.isSelectingText
      ? "Arrows  caret   Shift+arrows  select   Cmd/Ctrl+C  copy   Escape  MOVE"
      : editing
        ? "Escape  return to MOVE     Enter  send     Your draft stays here."
        : "dfjk move   Shift+dfjk section     s out     l \(context.navigationSelectionIsGroup ? "enter" : "use / edit")"
    drawList.fillRoundedRect(rect, radius: 8, color: WorkspacePalette.card)
    drawList.pushClip(rect)
    drawList.text(
      "\(mode)   /   \(location)", at: Point(x: rect.minX + 12, y: rect.minY + 9),
      color: WorkspacePalette.accent, scale: 0.45)
    drawList.text(
      hint, at: Point(x: rect.minX + 12, y: rect.minY + 36),
      color: WorkspacePalette.muted, scale: 0.4)
    drawList.popClip()
  }
}
