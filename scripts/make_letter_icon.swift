// Erzeugt ein 1024x1024-PNG-Icon mit abgerundetem Hintergrund und Buchstaben: make_letter_icon <Buchstaben> <ausgabe.png>
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("Aufruf: make_letter_icon <Buchstaben> <ausgabe.png>\n", stderr); exit(1) }
let letters = args[1], outPath = args[2]
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
// Farbe aus den Buchstaben ableiten (stabil je Name)
var hash: UInt32 = 2166136261
for b in letters.utf8 { hash = (hash ^ UInt32(b)) &* 16777619 }
let hue = CGFloat(hash % 360) / 360
let bg = NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.62, alpha: 1)
let inset: CGFloat = size * 0.09   // Apple-Icons haben Rand
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
NSGradient(starting: bg.blended(withFraction: 0.18, of: .white) ?? bg, ending: bg.blended(withFraction: 0.18, of: .black) ?? bg)?.draw(in: path, angle: -90)
let fontSize = letters.count > 3 ? rect.width * 0.30 : (letters.count == 3 ? rect.width * 0.38 : rect.width * 0.46)
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: NSColor.white,
]
let str = NSAttributedString(string: letters, attributes: attrs)
let s = str.size()
str.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2 + fontSize * 0.02))
img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("geschrieben: \(outPath)")
