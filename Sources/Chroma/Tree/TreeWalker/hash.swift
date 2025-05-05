import Crypto

func hash(contents: String) -> Hash {
  var copy = contents
  var sha = Insecure.SHA1()
  copy.withUTF8 {
    sha.update(data: $0)
  }
  let f = sha.finalize()
  return f.description.replacingOccurrences(of: "SHA1 digest: ", with: "")
}
