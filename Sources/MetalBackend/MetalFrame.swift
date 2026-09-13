import Metal
import Synchronization

public struct MetalFrameCompletion: Sendable {
  public let succeeded: Bool
  public let gpuDuration: Double?
  public let errorDescription: String?

  fileprivate init(_ command: MTLCommandBuffer) {
    succeeded = command.status == .completed
    let duration = command.gpuEndTime - command.gpuStartTime
    gpuDuration = succeeded && command.gpuStartTime > 0 && duration >= 0 ? duration : nil
    errorDescription = command.error.map { String(describing: $0) }
  }
}

final class MetalFrameSlots: Sendable {
  private let available = Mutex([true, true, true])

  func acquire() -> MetalFrameReservation? {
    let index = available.withLock { slots -> Int? in
      guard let index = slots.firstIndex(of: true) else { return nil }
      slots[index] = false
      return index
    }
    return index.map { MetalFrameReservation(pool: self, index: $0) }
  }

  fileprivate func release(_ index: Int) {
    available.withLock { slots in
      precondition(!slots[index])
      slots[index] = true
    }
  }
}

final class MetalFrameReservation: Sendable {
  private let pool: MetalFrameSlots
  let index: Int
  private let released = Mutex(false)

  fileprivate init(pool: MetalFrameSlots, index: Int) {
    self.pool = pool
    self.index = index
  }

  func release() {
    released.withLock { released in
      guard !released else { return }
      released = true
      pool.release(index)
    }
  }

  deinit { release() }
}

@MainActor
public struct MetalPreparedFrame: ~Copyable {
  private let command: MTLCommandBuffer
  private let reservation: MetalFrameReservation

  internal init(command: MTLCommandBuffer, reservation: MetalFrameReservation) {
    self.command = command
    self.reservation = reservation
  }

  public consuming func submit(
    presenting drawable: (any MTLDrawable)? = nil,
    onCompletion: @escaping @Sendable (MetalFrameCompletion) -> Void = { _ in }
  ) -> MetalSubmittedFrame {
    if let drawable { command.present(drawable) }
    let reservation = reservation
    command.addCompletedHandler { command in
      reservation.release()
      onCompletion(MetalFrameCompletion(command))
    }
    command.commit()
    return MetalSubmittedFrame(command: command)
  }
}

@MainActor
public struct MetalSubmittedFrame: ~Copyable {
  private let command: MTLCommandBuffer

  fileprivate init(command: MTLCommandBuffer) { self.command = command }

  public consuming func waitUntilCompleted() -> MetalFrameCompletion {
    command.waitUntilCompleted()
    return MetalFrameCompletion(command)
  }
}
