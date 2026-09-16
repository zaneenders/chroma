import CWaylandClient
import CWaylandProtocols
import Chroma
import Dispatch
import Foundation
import Glibc

@diagnose(
  StrictMemorySafety, as: ignored,
  reason: "Wayland clipboard handles and listener storage are managed by setup/cleanup on the main actor."
)
@MainActor
final class WaylandClipboard {
  private let interaction: Interaction
  private let keyboard: WaylandKeyboard
  private let flushWayland: () -> Void
  private let requestFrame: () -> Void

  init(
    interaction: Interaction, keyboard: WaylandKeyboard,
    flush: @escaping () -> Void, requestFrame: @escaping () -> Void
  ) {
    self.interaction = interaction
    self.keyboard = keyboard
    self.flushWayland = flush
    self.requestFrame = requestFrame
  }

  private var dataDeviceManager: OpaquePointer?
  private var dataDevice: OpaquePointer?
  private var dataDeviceVersion: UInt32 = 0
  private var selectionOffer: OpaquePointer?
  private var dragOffer: OpaquePointer?
  private var offeredMIMETypes: [OpaquePointer: Set<String>] = [:]
  private var clipboardSources: [OpaquePointer: Data] = [:]
  private struct ClipboardRead {
    var source: DispatchSourceRead
    var timeout: DispatchSourceTimer
    var data: Data
    var pasteID: Int32
    var editingLeaf: WidgetID
    var editingSessionGeneration: Int
  }
  private var clipboardReads: [Int32: ClipboardRead] = [:]
  var latestInputSerial: UInt32 = 0

  private static var dataDeviceManagerInterface: wl_interface = unsafe wl_data_device_manager_interface
  private static let clipboardMIMETypes = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING"]
  private static let maximumClipboardBytes = 16 * 1024 * 1024
  private static let clipboardReadTimeout: DispatchTimeInterval = .seconds(5)

  func bind(registry: OpaquePointer, name: UInt32, version: UInt32) {
    dataDeviceVersion = min(version, 3)
    dataDeviceManager = unsafe OpaquePointer(
      wl_registry_bind(registry, name, &Self.dataDeviceManagerInterface, dataDeviceVersion))
  }

  func setUp(seat: OpaquePointer?) {
    guard dataDevice == nil, let dataDeviceManager, let seat else { return }
    dataDevice = unsafe wl_data_device_manager_get_data_device(dataDeviceManager, seat)
    if let dataDevice {
      unsafe wl_data_device_add_listener(
        dataDevice, &Self.dataDeviceListener, Unmanaged.passUnretained(self).toOpaque())
    }
  }

  func copyEditableSelectionToClipboard() -> Bool {
    guard let text = interaction.editableSelectionText(), !text.isEmpty else { return false }
    return copyToClipboard(text)
  }

  @discardableResult
  func copyToClipboard(_ explicitText: String? = nil) -> Bool {
    guard let dataDeviceManager, let dataDevice, latestInputSerial != 0,
      let text = explicitText ?? interaction.copyText(), !text.isEmpty,
      let source = unsafe wl_data_device_manager_create_data_source(dataDeviceManager)
    else { return false }
    let sourceKey = source
    clipboardSources[sourceKey] = Data(text.utf8)
    unsafe wl_data_source_add_listener(
      source, &Self.dataSourceListener, Unmanaged.passUnretained(self).toOpaque())
    for mimeType in Self.clipboardMIMETypes {
      unsafe wl_data_source_offer(source, mimeType)
    }
    unsafe wl_data_device_set_selection(dataDevice, source, latestInputSerial)
    flushWayland()
    return true
  }

  func pasteFromClipboard(id: Int32) {
    guard let editingLeaf = interaction.editingLeaf, let offer = selectionOffer,
      let offered = offeredMIMETypes[offer],
      let mimeType = Self.clipboardMIMETypes.first(where: offered.contains)
    else {
      keyboard.completePaste(id: id, text: nil)
      return
    }
    let editingSessionGeneration = interaction.editingSessionGeneration
    var descriptors = [Int32](repeating: -1, count: 2)
    guard unsafe pipe(&descriptors) == 0 else {
      keyboard.completePaste(id: id, text: nil)
      return
    }
    let readFD = descriptors[0]
    let writeFD = descriptors[1]
    let flags = fcntl(readFD, F_GETFL)
    if flags >= 0 { _ = fcntl(readFD, F_SETFL, flags | O_NONBLOCK) }
    let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: .main)
    let timeout = DispatchSource.makeTimerSource(queue: .main)
    clipboardReads[readFD] = ClipboardRead(
      source: source,
      timeout: timeout,
      data: Data(),
      pasteID: id,
      editingLeaf: editingLeaf,
      editingSessionGeneration: editingSessionGeneration)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.readClipboard(fd: readFD) }
    }
    source.setCancelHandler { close(readFD) }
    timeout.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.cancelClipboardRead(fd: readFD) }
    }
    timeout.schedule(deadline: .now() + Self.clipboardReadTimeout)
    source.resume()
    timeout.resume()
    unsafe wl_data_offer_receive(offer, mimeType, writeFD)
    close(writeFD)
    flushWayland()
  }

  private func readClipboard(fd: Int32) {
    guard var transfer = clipboardReads[fd] else { return }
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
      let count = buffer.withUnsafeMutableBytes { bytes in
        unsafe read(fd, bytes.baseAddress, bytes.count)
      }
      if count > 0 {
        guard transfer.data.count <= Self.maximumClipboardBytes - count else {
          finishClipboardRead(fd: fd, transfer: transfer, text: nil)
          return
        }
        transfer.data.append(contentsOf: buffer.prefix(count))
        clipboardReads[fd] = transfer
      } else if count == 0 {
        let sessionIsCurrent =
          interaction.editingLeaf == transfer.editingLeaf
          && interaction.editingSessionGeneration == transfer.editingSessionGeneration
        let text = sessionIsCurrent ? String(decoding: transfer.data, as: UTF8.self) : nil
        finishClipboardRead(fd: fd, transfer: transfer, text: text)
        return
      } else if errno == EAGAIN || errno == EWOULDBLOCK {
        return
      } else {
        finishClipboardRead(fd: fd, transfer: transfer, text: nil)
        return
      }
    }
  }

  private func cancelClipboardRead(fd: Int32) {
    guard let transfer = clipboardReads[fd] else { return }
    finishClipboardRead(fd: fd, transfer: transfer, text: nil)
  }

  private func finishClipboardRead(fd: Int32, transfer: ClipboardRead, text: String?) {
    clipboardReads.removeValue(forKey: fd)
    transfer.timeout.cancel()
    transfer.source.cancel()
    keyboard.completePaste(id: transfer.pasteID, text: text)
    requestFrame()
  }

  private static var dataOfferListener = unsafe wl_data_offer_listener(
    offer: { data, offer, mimeType in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let mimeType = mimeType
      nonisolated(unsafe) let offer = offer
      MainActor.assumeIsolated {
        guard let data, let offer, let mimeType else { return }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        clipboard.offeredMIMETypes[offer, default: []].insert(
          unsafe String(cString: mimeType))
      }
    },
    source_actions: { _, _, _ in },
    action: { _, _, _ in }
  )

  private static var dataDeviceListener = unsafe wl_data_device_listener(
    data_offer: { data, _, offer in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let offer = offer
      MainActor.assumeIsolated {
        guard let data, let offer else { return }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        clipboard.offeredMIMETypes[offer] = []
        unsafe wl_data_offer_add_listener(
          offer, &dataOfferListener, Unmanaged.passUnretained(clipboard).toOpaque())
      }
    },
    enter: { data, _, _, _, _, _, offer in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let offer = offer
      MainActor.assumeIsolated {
        guard let data else { return }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        if let previous = clipboard.dragOffer, previous != offer,
          previous != clipboard.selectionOffer
        {
          clipboard.offeredMIMETypes.removeValue(forKey: previous)
          unsafe wl_data_offer_destroy(previous)
        }
        clipboard.dragOffer = offer
      }
    },
    leave: { data, _ in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        if let offer = clipboard.dragOffer, offer != clipboard.selectionOffer {
          clipboard.offeredMIMETypes.removeValue(forKey: offer)
          unsafe wl_data_offer_destroy(offer)
        }
        clipboard.dragOffer = nil
      }
    },
    motion: { _, _, _, _, _ in },
    drop: { data, _ in
      nonisolated(unsafe) let data = data
      MainActor.assumeIsolated {
        guard let data else { return }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        if let offer = clipboard.dragOffer, offer != clipboard.selectionOffer {
          clipboard.offeredMIMETypes.removeValue(forKey: offer)
          unsafe wl_data_offer_destroy(offer)
        }
        clipboard.dragOffer = nil
      }
    },
    selection: { data, _, offer in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let offer = offer
      MainActor.assumeIsolated {
        guard let data else { return }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        if let previous = clipboard.selectionOffer, previous != offer {
          if clipboard.dragOffer == previous { clipboard.dragOffer = nil }
          clipboard.offeredMIMETypes.removeValue(forKey: previous)
          unsafe wl_data_offer_destroy(previous)
        }
        clipboard.selectionOffer = offer
      }
    }
  )

  private static var dataSourceListener = unsafe wl_data_source_listener(
    target: { _, _, _ in },
    send: { data, source, _, fd in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let source = source
      MainActor.assumeIsolated {
        guard let data, let source else {
          close(fd)
          return
        }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        let bytes = clipboard.clipboardSources[source] ?? Data()
        DispatchQueue.global().async {
          bytes.bytes.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
              let count = unsafe chroma_write_no_sigpipe(
                fd, base.advanced(by: offset), rawBuffer.count - offset)
              if count > 0 { offset += count } else if errno != EINTR { break }
            }
          }
          close(fd)
        }
      }
    },
    cancelled: { data, source in
      nonisolated(unsafe) let data = data
      nonisolated(unsafe) let source = source
      MainActor.assumeIsolated {
        guard let data, let source else { return }
        let clipboard = unsafe Unmanaged<WaylandClipboard>.fromOpaque(data).takeUnretainedValue()
        clipboard.clipboardSources.removeValue(forKey: source)
        unsafe wl_data_source_destroy(source)
      }
    },
    dnd_drop_performed: { _, _ in },
    dnd_finished: { _, _ in },
    action: { _, _, _ in }
  )

  func cleanup() {
    for transfer in clipboardReads.values {
      transfer.timeout.cancel()
      transfer.source.cancel()
    }
    clipboardReads.removeAll()
    if let dragOffer, dragOffer != selectionOffer {
      unsafe wl_data_offer_destroy(dragOffer)
    }
    if let selectionOffer { unsafe wl_data_offer_destroy(selectionOffer) }
    dragOffer = nil
    selectionOffer = nil
    offeredMIMETypes.removeAll()
    for source in clipboardSources.keys { unsafe wl_data_source_destroy(source) }
    clipboardSources.removeAll()
    if let dataDevice {
      if dataDeviceVersion >= UInt32(WL_DATA_DEVICE_RELEASE_SINCE_VERSION) {
        unsafe wl_data_device_release(dataDevice)
      } else {
        unsafe wl_proxy_destroy(dataDevice)
      }
    }
    if let dataDeviceManager { unsafe wl_data_device_manager_destroy(dataDeviceManager) }
    dataDevice = nil
    dataDeviceManager = nil
    dataDeviceVersion = 0
    latestInputSerial = 0
  }
}
