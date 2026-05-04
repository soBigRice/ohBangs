import AppKit

let outputDirectory = URL(fileURLWithPath: "ohBangs/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let appIconURL = URL(fileURLWithPath: "ohBangs/AppIcon.icns")
let canvasSize = CGSize(width: 1024, height: 1024)

let iconSizes: [(name: String, size: CGSize)] = [
    ("icon_16x16.png", CGSize(width: 16, height: 16)),
    ("icon_16x16@2x.png", CGSize(width: 32, height: 32)),
    ("icon_32x32.png", CGSize(width: 32, height: 32)),
    ("icon_32x32@2x.png", CGSize(width: 64, height: 64)),
    ("icon_128x128.png", CGSize(width: 128, height: 128)),
    ("icon_128x128@2x.png", CGSize(width: 256, height: 256)),
    ("icon_256x256.png", CGSize(width: 256, height: 256)),
    ("icon_256x256@2x.png", CGSize(width: 512, height: 512)),
    ("icon_512x512.png", CGSize(width: 512, height: 512)),
    ("icon_512x512@2x.png", CGSize(width: 1024, height: 1024))
]

func drawRoundedRect(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, gradient: NSGradient, angle: CGFloat) {
    path.addClip()
    gradient.draw(in: path.bounds, angle: angle)
}

func drawGradientBorder(
    in rect: CGRect,
    radius: CGFloat,
    lineWidth: CGFloat,
    colors: [NSColor],
    angle: CGFloat
) {
    let outerPath = drawRoundedRect(in: rect, radius: radius)
    let innerRect = rect.insetBy(dx: lineWidth, dy: lineWidth)
    let innerPath = drawRoundedRect(in: innerRect, radius: max(0, radius - lineWidth))
    let ringPath = NSBezierPath()
    ringPath.append(outerPath)
    ringPath.append(innerPath.reversed)

    withSavedGraphicsState {
        ringPath.addClip()
        NSGradient(colors: colors)!.draw(in: rect, angle: angle)
    }
}

func withSavedGraphicsState(_ work: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    work()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
    context.scaleBy(x: scale, y: scale)

    let canvas = CGRect(origin: .zero, size: canvasSize)

    let outerRect = canvas.insetBy(dx: 10, dy: 10)
    let outerPath = drawRoundedRect(in: outerRect, radius: 160)
    withSavedGraphicsState {
        let background = NSGradient(colors: [
            NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.15, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.22, blue: 0.42, alpha: 1)
        ])!
        fill(outerPath, gradient: background, angle: -75)
    }

    withSavedGraphicsState {
        let strokePath = drawRoundedRect(in: outerRect.insetBy(dx: 3, dy: 3), radius: 156)
        NSColor.white.withAlphaComponent(0.20).setStroke()
        strokePath.lineWidth = 7
        strokePath.stroke()
    }

    let pillRect = CGRect(x: 105, y: 310, width: 814, height: 300)
    let pillPath = drawRoundedRect(in: pillRect, radius: 120)

    context.saveGState()
    context.setShadow(offset: .zero, blur: 42, color: NSColor(calibratedRed: 0.38, green: 0.22, blue: 1.0, alpha: 0.78).cgColor)
    NSColor(calibratedRed: 0.44, green: 0.32, blue: 1.0, alpha: 0.85).setStroke()
    pillPath.lineWidth = 16
    pillPath.stroke()
    context.restoreGState()

    withSavedGraphicsState {
        let innerBackground = NSGradient(colors: [
            NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.11, blue: 0.24, alpha: 1)
        ])!
        fill(pillPath, gradient: innerBackground, angle: -90)
    }

    withSavedGraphicsState {
        let strokeRect = pillRect.insetBy(dx: 8, dy: 8)
        drawGradientBorder(
            in: strokeRect,
            radius: 112,
            lineWidth: 7,
            colors: [
                NSColor(calibratedRed: 0.75, green: 0.54, blue: 1.0, alpha: 0.95),
                NSColor(calibratedRed: 0.26, green: 0.53, blue: 1.0, alpha: 0.98)
            ],
            angle: 0
        )
    }

    func drawCard(_ rect: CGRect, radius: CGFloat = 48) {
        let path = drawRoundedRect(in: rect, radius: radius)
        withSavedGraphicsState {
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.38, alpha: 0.82),
                NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.31, alpha: 0.92)
            ])!
            fill(path, gradient: gradient, angle: -90)
        }
        NSColor.white.withAlphaComponent(0.07).setStroke()
        path.lineWidth = 4
        path.stroke()
    }

    let leftCard = CGRect(x: 180, y: 390, width: 140, height: 140)
    let centerCard = CGRect(x: 345, y: 392, width: 305, height: 138)
    let rightCard = CGRect(x: 675, y: 390, width: 160, height: 140)
    drawCard(leftCard)
    drawCard(centerCard)
    drawCard(rightCard)

    let leftDotRect = CGRect(x: leftCard.midX - 32, y: leftCard.midY - 32, width: 64, height: 64)
    let leftDotPath = NSBezierPath(ovalIn: leftDotRect)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 18, color: NSColor(calibratedRed: 0.52, green: 0.40, blue: 1.0, alpha: 0.72).cgColor)
    NSColor(calibratedRed: 0.43, green: 0.32, blue: 1.0, alpha: 1).setFill()
    leftDotPath.fill()
    context.restoreGState()

    func drawRoundedBar(_ rect: CGRect, colors: [NSColor]) {
        let path = drawRoundedRect(in: rect, radius: rect.height / 2)
        withSavedGraphicsState {
            let gradient = NSGradient(colors: colors)!
            fill(path, gradient: gradient, angle: 0)
        }
    }

    drawRoundedBar(
        CGRect(x: centerCard.minX + 42, y: centerCard.maxY - 60, width: 200, height: 20),
        colors: [
            NSColor(calibratedRed: 0.78, green: 0.60, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.30, green: 0.39, blue: 1.0, alpha: 1)
        ]
    )
    drawRoundedBar(
        CGRect(x: centerCard.minX + 42, y: centerCard.minY + 34, width: 120, height: 18),
        colors: [
            NSColor(calibratedRed: 0.45, green: 0.64, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.26, green: 0.43, blue: 1.0, alpha: 1)
        ]
    )

    let dotColors: [NSColor] = [
        NSColor(calibratedRed: 0.63, green: 0.34, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.29, green: 0.40, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.26, green: 0.66, blue: 1.0, alpha: 1)
    ]

    for (index, color) in dotColors.enumerated() {
        let rect = CGRect(x: rightCard.minX + 34 + CGFloat(index) * 56, y: rightCard.midY - 20, width: 26, height: 52)
        let path = drawRoundedRect(in: rect, radius: 13)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 12, color: color.withAlphaComponent(0.55).cgColor)
        color.setFill()
        path.fill()
        context.restoreGState()
    }

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage, pixelSize: CGSize) -> Data? {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize.width),
        pixelsHigh: Int(pixelSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let rep = bitmap else { return nil }

    rep.size = pixelSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: CGRect(origin: .zero, size: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let master = drawIcon(size: canvasSize)
let fileManager = FileManager.default

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for icon in iconSizes {
    let url = outputDirectory.appendingPathComponent(icon.name)
    if let data = pngData(from: master, pixelSize: icon.size) {
        try data.write(to: url)
        print("Wrote \(icon.name)")
    } else {
        fputs("Failed to encode \(icon.name)\n", stderr)
        exit(1)
    }
}

let temporaryIconset = fileManager.temporaryDirectory.appendingPathComponent("ohBangs_AppIcon.iconset", isDirectory: true)
try? fileManager.removeItem(at: temporaryIconset)
try fileManager.createDirectory(at: temporaryIconset, withIntermediateDirectories: true)

for icon in iconSizes {
    let sourceURL = outputDirectory.appendingPathComponent(icon.name)
    let destinationURL = temporaryIconset.appendingPathComponent(icon.name)
    try fileManager.copyItem(at: sourceURL, to: destinationURL)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", temporaryIconset.path, "-o", appIconURL.path]
try process.run()
process.waitUntilExit()
try? fileManager.removeItem(at: temporaryIconset)

if process.terminationStatus != 0 {
    fputs("Failed to generate AppIcon.icns\n", stderr)
    exit(1)
}

print("Wrote \(appIconURL.path)")
