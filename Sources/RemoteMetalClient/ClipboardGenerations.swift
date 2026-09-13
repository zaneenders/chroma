struct ClipboardGenerations {
  private var pending: [UInt64: Int] = [:]

  mutating func record(sequence: UInt64, generation: Int) {
    pending[sequence] = generation
    pending = pending.filter { sequence &- $0.key < 1024 }
  }

  mutating func consume(sequence: UInt64) -> Int? {
    pending.removeValue(forKey: sequence)
  }

  mutating func didWrite(sequence: UInt64, from oldGeneration: Int, to newGeneration: Int) {
    for (id, generation) in pending where id > sequence && generation == oldGeneration {
      pending[id] = newGeneration
    }
  }

  mutating func removeAll() {
    pending.removeAll()
  }
}
