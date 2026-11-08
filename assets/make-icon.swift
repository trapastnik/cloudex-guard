// Рисует иконку приложения (тот же знак, что в mark.svg: шкала-дуга со стрелкой) и собирает AppIcon.icns:
//   swift make-icon.swift && iconutil -c icns AppIcon.iconset
import AppKit

func draw(_ size: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = size / 100
  // Поле иконки по сетке macOS: отступ ~10%, скругление ~22%.
  let inset: CGFloat = 10 * s
  let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
  NSColor(red: 0.086, green: 0.086, blue: 0.102, alpha: 1).setFill()
  NSBezierPath(roundedRect: tile, xRadius: 18 * s, yRadius: 18 * s).fill()
  // Шкала-дуга — как в mark.svg; координаты AppKit — y вверх.
  let k = tile.width / 100
  let center = NSPoint(x: tile.midX, y: tile.midY)
  func arc(to end: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: 32 * k, startAngle: 225, endAngle: end, clockwise: true)
    path.lineWidth = 9 * k
    path.lineCapStyle = .round
    return path
  }
  NSColor(red: 0.18, green: 0.18, blue: 0.208, alpha: 1).setStroke()
  arc(to: -45).stroke()
  NSColor(red: 0.937, green: 0.427, blue: 0.122, alpha: 1).setStroke()
  arc(to: 41.4).stroke()
  // Стрелка шкалы и ось — как в mark.svg.
  NSColor(white: 0.96, alpha: 1).set()
  let needle = NSBezierPath()
  needle.move(to: center); needle.line(to: NSPoint(x: center.x + 15.6 * k, y: center.y + 13.8 * k))
  needle.lineWidth = 4.4 * k; needle.lineCapStyle = .round; needle.stroke()
  NSBezierPath(ovalIn: NSRect(x: center.x - 6.2 * k, y: center.y - 6.2 * k, width: 12.4 * k, height: 12.4 * k)).fill()
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let folder = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let rep = draw(CGFloat(base * scale))
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
  }
}
try! draw(512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon-512.png"))
