import Crypto

/// Parses the Block tree producing ``Hash``s based on the parent ``Block`` the
/// blocks position in the tree and the type of Block. Should remain
/// independent of the contains of the block IE it's mutations.
protocol L2HashWalker: L2ElementWalker {
  var currentHash: Hash { get set }
  mutating func beforeGroup(_ group: [L2Element])
  mutating func afterGroup(_ group: [L2Element])
}

extension L2HashWalker {

  mutating func walkGroup(_ group: [L2Element]) {
    beforeGroup(group)
    let ourHash = currentHash
    for (index, element) in group.enumerated() {
      currentHash = hash(contents: "\(ourHash)\(#function)\(index)")
      walk(element)
    }
    currentHash = ourHash
    afterGroup(group)
  }
}

func hash(contents: String) -> Hash {
  var copy = contents
  var sha = Insecure.SHA1()
  copy.withUTF8 {
    sha.update(data: $0)
  }
  let f = sha.finalize()
  return f.description.replacingOccurrences(of: "SHA1 digest: ", with: "")
}
