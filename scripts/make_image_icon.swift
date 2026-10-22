// Erzeugt ein 1024x1024-Icon aus einem Logo-Bild: Logo zentriert mit Rand auf abgerundetem Hintergrund.
//   make_image_icon <logo.png|svg> <ausgabe.png> [hintergrund-hex z. B. FFFFFF] [fuellgrad 0.1-1.0]
import AppKit

let a = CommandLine.arguments
guard a.count >= 3 else { fputs("Aufruf: make_image_icon <logo> <ausgabe.png> [hex] [fuellgrad]\n", stderr); exit(1) }
guard let logo = NSImage(contentsOfFile: a[1]) else { fputs("Logo nicht lesbar\n", stderr); exit(2) }
let hex = a.count > 3 ? a[3] : "FFFFFF"
let fill = a.count > 4 ? (Double(a[4]) ?? 0.72) : 0.72
func color(_ h: String) -> NSColor {
    var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
}
let size: CGFloat = 1024
let out = NSImage(size: NSSize(width: size, height: size))
out.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high
let inset = size * 0.09
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
color(hex).setFill(); path.fill()
let ls = logo.size
let maxW = rect.width * CGFloat(fill), maxH = rect.height * CGFloat(fill)
let scale = min(maxW / ls.width, maxH / ls.height)
let w = ls.width * scale, h = ls.height * scale
logo.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
out.unlockFocus()
guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
try! png.write(to: URL(fileURLWithPath: a[2]))
print("geschrieben: \(a[2])")
