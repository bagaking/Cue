import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/Cue.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func masterImage() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = NSRect(origin: .zero, size: size)
    NSColor(calibratedWhite: 0.085, alpha: 1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 34, dy: 34), xRadius: 214, yRadius: 214).fill()

    let cards: [(NSRect, CGFloat, NSColor)] = [
        (NSRect(x: 238, y: 592, width: 548, height: 174), -4, NSColor(calibratedWhite: 0.22, alpha: 1)),
        (NSRect(x: 214, y: 397, width: 596, height: 188), 2.5, NSColor(calibratedWhite: 0.28, alpha: 1)),
        (NSRect(x: 190, y: 190, width: 644, height: 202), 0, NSColor(calibratedWhite: 0.94, alpha: 1)),
    ]

    for (rect, angle, color) in cards {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: angle)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 56, yRadius: 56).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    let accent = NSColor(calibratedRed: 0.19, green: 0.78, blue: 0.64, alpha: 1)
    accent.setStroke()
    let circle = NSBezierPath(ovalIn: NSRect(x: 248, y: 251, width: 88, height: 88))
    circle.lineWidth = 18
    circle.stroke()

    let line = NSBezierPath()
    line.move(to: NSPoint(x: 386, y: 318))
    line.line(to: NSPoint(x: 720, y: 318))
    line.lineCapStyle = .round
    line.lineWidth = 22
    NSColor(calibratedWhite: 0.16, alpha: 1).setStroke()
    line.stroke()

    let shortLine = NSBezierPath()
    shortLine.move(to: NSPoint(x: 386, y: 269))
    shortLine.line(to: NSPoint(x: 602, y: 269))
    shortLine.lineCapStyle = .round
    shortLine.lineWidth = 16
    NSColor(calibratedWhite: 0.38, alpha: 1).setStroke()
    shortLine.stroke()

    return image
}

func writePNG(_ source: NSImage, pixels: Int, to url: URL) throws {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CueIcon", code: 1)
    }
    try data.write(to: url)
}

let source = masterImage()
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in entries {
    try writePNG(source, pixels: pixels, to: iconset.appendingPathComponent(name))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["--convert", "icns", "--output", output, iconset.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
