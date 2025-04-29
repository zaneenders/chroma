enum L2Element {
  case text(String, InputHandler?)
  case group([L2Element])
}
