import Chroma
import DemoImages

struct ImageDemo: Block {
  @MainActor var body: some Block {
    VStack(spacing: 16) {
      Text("Mandelbrot").fontScale(1.2).navigationIgnored()
      Text("640 × 400 / RGBA image").fontScale(0.5)
        .foregroundColor(DemoStyle.muted).navigationIgnored()
      Image(DemoImages.mandelbrot, scaling: .contain)
        .sizing(x: .grow, y: .grow)
        .roundedBackground(DemoStyle.background, radius: 10)
    }.padding(24).roundedBackground(DemoStyle.panel, radius: 14)
  }
}
