import Dispatch
import Foundation

struct Workload: Sendable {
  let name: String
  let line: Data
  let count: Int
  let oversized: Bool
  let interactive: Bool
}

let limit = 65_536
let request = Data("{\"version\":1,\"id\":\"benchmark\",\"op\":\"frame\"}".utf8)
let workloads = [
  Workload(name: "short-burst", line: request, count: 10_000, oversized: false, interactive: false),
  Workload(name: "short-handshakes", line: request, count: 1_000, oversized: false, interactive: true),
  Workload(
    name: "maximum-length", line: request + Data(repeating: 32, count: limit - request.count),
    count: 32, oversized: false, interactive: false),
  Workload(
    name: "oversized", line: Data(repeating: 32, count: 4 * limit), count: 8, oversized: true, interactive: false),
]

// Compile with the actual BoundedLineReader source from either revision. This probe
// excludes JSON decoding, session scheduling, rendering and response encoding.
for workload in workloads {
  let terminated = workload.line + Data([10])
  var burst = Data()
  if !workload.interactive {
    for _ in 0..<workload.count { burst.append(terminated) }
  }
  let payload = burst
  for trial in 0..<6 {
    let pipe = Pipe()
    let reader = BoundedLineReader(handle: pipe.fileHandleForReading, limit: limit)
    let consumed = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let start = DispatchTime.now().uptimeNanoseconds
    DispatchQueue.global().async {
      if workload.interactive {
        for _ in 0..<workload.count {
          try! pipe.fileHandleForWriting.write(contentsOf: terminated)
          precondition(consumed.wait(timeout: .now() + 10) == .success)
        }
      } else {
        try! pipe.fileHandleForWriting.write(contentsOf: payload)
      }
      try! pipe.fileHandleForWriting.close()
      finished.signal()
    }
    for _ in 0..<workload.count {
      switch try reader.next() {
      case .bytes(let bytes): precondition(!workload.oversized && bytes == workload.line)
      case .oversized: precondition(workload.oversized)
      case nil: fatalError("Unexpected EOF")
      }
      if workload.interactive { consumed.signal() }
    }
    let end = try reader.next()
    precondition(end == nil)
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    precondition(finished.wait(timeout: .now() + 10) == .success)
    try pipe.fileHandleForReading.close()
    if trial > 0 {
      print(
        "{\"workload\":\"\(workload.name)\",\"trial\":\(trial),\"lines\":\(workload.count),\"inputBytes\":\(terminated.count * workload.count),\"milliseconds\":\(elapsed)}"
      )
    }
  }
}
