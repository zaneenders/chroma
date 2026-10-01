import Chroma
import Foundation

public enum DemoImages {
  public static let mandelbrot: ImageResource = {
    let width = 640
    let height = 400
    let maximumIterations = 160
    var pixels = Data(capacity: width * height * 4)
    for y in 0..<height {
      let cy = -1.15 + 2.3 * Double(y) / Double(height - 1)
      for x in 0..<width {
        let cx = -2.35 + 3.4 * Double(x) / Double(width - 1)
        var zx = 0.0
        var zy = 0.0
        var iteration = 0
        while zx * zx + zy * zy <= 4, iteration < maximumIterations {
          let nextX = zx * zx - zy * zy + cx
          zy = 2 * zx * zy + cy
          zx = nextX
          iteration += 1
        }
        if iteration == maximumIterations {
          pixels.append(contentsOf: [8, 10, 20, 255])
        } else {
          let magnitude = max(zx * zx + zy * zy, 4)
          let smooth = Double(iteration) + 1 - log2(log2(magnitude) / 2)
          let t = max(0, min(1, smooth / Double(maximumIterations)))
          let phase = 6.283185307179586 * (t * 8 + 0.62)
          let red = UInt8(clamping: Int(127.5 + 127.5 * sin(phase)))
          let green = UInt8(clamping: Int(127.5 + 127.5 * sin(phase + 2.094)))
          let blue = UInt8(clamping: Int(127.5 + 127.5 * sin(phase + 4.188)))
          pixels.append(contentsOf: [red, green, blue, 255])
        }
      }
    }
    return try! ImageResource(
      id: ImageID("demo.mandelbrot"), width: width, height: height, rgba8: pixels)
  }()
}
