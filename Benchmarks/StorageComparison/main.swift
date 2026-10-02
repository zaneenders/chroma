import BasicContainers
import Foundation

struct Node {
  var parent: Int
  var value: Int
  var x: Float
  var y: Float
}
func now() -> Double { ProcessInfo.processInfo.systemUptime }
func report(_ name: String, _ samples: [Double], _ growth: Int, _ checksum: Int) {
  let s = samples.sorted()
  print("\(name) p50=\(s[14]*1000) p95=\(s[28]*1000) ms growth=\(growth) checksum=\(checksum)")
}
for count in [1000, 100000] {
  for reserved in [false, true] {
    var arrayTimes = Array(repeating: [Double](), count: 3)
    var uniqueTimes = Array(repeating: [Double](), count: 3)
    var ag = 0
    var ug = 0
    var acheck = 0
    var ucheck = 0
    for trial in 0..<35 {
      var a: [Node] = []
      var u = UniqueArray<Node>()
      if reserved {
        a.reserveCapacity(count)
        u.reserveCapacity(count)
      }
      var growth = 0
      let arrayStart = now()
      for i in 0..<count {
        let capacity = a.capacity
        a.append(Node(parent: i - 1, value: i, x: 0, y: 0))
        if a.capacity != capacity { growth += 1 }
      }
      let built = now()
      for i in 0..<count { a[i].value += 1 }
      let updated = now()
      var checksum = 0
      for i in 0..<count { checksum &+= a[i].value }
      let end = now()
      if trial >= 5 {
        let durations = [built - arrayStart, updated - built, end - updated]
        precondition(durations.allSatisfy { $0 >= 0 })
        for stage in 0..<3 { arrayTimes[stage].append(durations[stage]) }
        ag = growth
        acheck = checksum
      }
      growth = 0
      let uniqueStart = now()
      for i in 0..<count {
        let capacity = u.capacity
        u.append(Node(parent: i - 1, value: i, x: 0, y: 0))
        if u.capacity != capacity { growth += 1 }
      }
      let uniqueBuilt = now()
      for i in 0..<count { u[i].value += 1 }
      let uniqueUpdated = now()
      checksum = 0
      for i in 0..<count { checksum &+= u[i].value }
      let uniqueEnd = now()
      if trial >= 5 {
        let durations = [uniqueBuilt - uniqueStart, uniqueUpdated - uniqueBuilt, uniqueEnd - uniqueUpdated]
        precondition(durations.allSatisfy { $0 >= 0 })
        for stage in 0..<3 { uniqueTimes[stage].append(durations[stage]) }
        ug = growth
        ucheck = checksum
      }
    }
    print("nodes=\(count) reserved=\(reserved) trials=30 warmup=5")
    for (stage, name) in ["build", "update", "traversal"].enumerated() {
      report("Array \(name)", arrayTimes[stage], ag, acheck)
      report("UniqueArray \(name)", uniqueTimes[stage], ug, ucheck)
    }
    precondition(acheck == ucheck)
  }
}
