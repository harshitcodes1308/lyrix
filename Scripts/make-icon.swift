import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let base = NSBezierPath(roundedRect: rect.insetBy(dx: 35, dy: 35), xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.055, green: 0.08, blue: 0.16, alpha: 1).setFill(); base.fill()
let glow = NSBezierPath(ovalIn: NSRect(x: 180, y: 190, width: 660, height: 660))
NSColor(calibratedRed: 0.08, green: 0.65, blue: 0.85, alpha: 0.20).setFill(); glow.fill()
let string = NSAttributedString(string: "✦", attributes: [.font: NSFont.systemFont(ofSize: 620, weight: .ultraLight), .foregroundColor: NSColor(calibratedRed: 0.4, green: 0.9, blue: 1, alpha: 1)])
string.draw(at: NSPoint(x: 260, y: 190))
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
