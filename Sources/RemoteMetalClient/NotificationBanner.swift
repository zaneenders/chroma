import AppKit

/// Client-owned overlay: remains available even when the daemon cannot render.
@MainActor
final class NotificationBanner: NSVisualEffectView {
  private var dismissTimer: Timer?
  private let icon = NSImageView()
  private let label = NSTextField(wrappingLabelWithString: "")
  private let dismissButton = NSButton(title: "", target: nil, action: nil)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    material = .popover
    blendingMode = .withinWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.borderWidth = 1

    icon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
    icon.contentTintColor = .systemOrange
    icon.symbolConfiguration = .init(pointSize: 18, weight: .medium)
    icon.setAccessibilityElement(false)

    label.font = .systemFont(ofSize: 13)
    label.textColor = .labelColor
    label.maximumNumberOfLines = 0
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss notification")
    dismissButton.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
    dismissButton.contentTintColor = .secondaryLabelColor
    dismissButton.isBordered = false
    dismissButton.setAccessibilityLabel("Dismiss notification")
    dismissButton.toolTip = "Dismiss notification"
    dismissButton.target = self
    dismissButton.action = #selector(dismiss)
    dismissButton.refusesFirstResponder = true
    for child in [icon, label, dismissButton] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      icon.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      icon.widthAnchor.constraint(equalToConstant: 20),
      icon.heightAnchor.constraint(equalToConstant: 20),
      label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
      label.topAnchor.constraint(equalTo: topAnchor, constant: 16),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
      dismissButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
      dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      dismissButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      dismissButton.widthAnchor.constraint(equalToConstant: 28),
      dismissButton.heightAnchor.constraint(equalToConstant: 28),
      heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
    ])
    isHidden = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    }
  }

  func show(_ message: String, success: Bool = false, dismissAfter: TimeInterval? = nil) {
    dismissTimer?.invalidate()
    dismissTimer = nil
    icon.image = NSImage(
      systemSymbolName: success ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
      accessibilityDescription: nil)
    icon.contentTintColor = success ? .systemGreen : .systemOrange
    if let dismissAfter {
      let timer = Timer(timeInterval: dismissAfter, repeats: false) { [weak self] _ in
        MainActor.assumeIsolated { self?.dismiss() }
      }
      dismissTimer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
    label.stringValue = message
    isHidden = false
    // AppKit receives the live view and owned notification payload for this call.
    unsafe NSAccessibility.post(
      element: self, notification: .announcementRequested,
      userInfo: [
        .announcement: message,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
  }

  @objc func dismiss() {
    dismissTimer?.invalidate()
    dismissTimer = nil
    isHidden = true
  }
}
