import AppKit

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [
        CGFloat((hex >> 16) & 0xff) / 255,
        CGFloat((hex >> 8) & 0xff) / 255,
        CGFloat(hex & 0xff) / 255,
        alpha
    ])!
}

func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: colors as CFArray, locations: locations)!
}

func renderIcon(size: Int) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let compact = size <= 32
    let tile = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                      cornerWidth: 202, cornerHeight: 202, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                      color: color(0x001018, alpha: 0.28))
    context.setFillColor(color(0x102D3C))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0x2D5668), color(0x133747), color(0x0A202E)], locations: [0, 0.5, 1]),
        start: CGPoint(x: 140, y: 1000), end: CGPoint(x: 860, y: 60), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    if !compact {
        context.drawRadialGradient(
            gradient([color(0x74C8C3, alpha: 0.1), color(0x74C8C3, alpha: 0)], locations: [0, 1]),
            startCenter: CGPoint(x: 390, y: 760), startRadius: 0,
            endCenter: CGPoint(x: 390, y: 760), endRadius: 590, options: []
        )
        context.addPath(tile)
        context.setStrokeColor(color(0xDCFBFF, alpha: 0.2))
        context.setLineWidth(4)
        context.strokePath()
    }
    context.restoreGState()

    let power = CGMutablePath()
    power.addArc(center: CGPoint(x: 512, y: 548), radius: 208,
                 startAngle: 132 * .pi / 180, endAngle: 408 * .pi / 180, clockwise: false)
    power.move(to: CGPoint(x: 512, y: 800))
    power.addLine(to: CGPoint(x: 512, y: 604))
    let symbol = power.copy(strokingWithWidth: compact ? 90 : 80,
                            lineCap: .round, lineJoin: .round, miterLimit: 1)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 14,
                      color: color(0x00141C, alpha: 0.5))
    context.addPath(symbol)
    context.setFillColor(color(0x70F0C3))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(symbol)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xD3FFE5), color(0x8CF5CF), color(0x41DCA7)], locations: [0, 0.5, 1]),
        start: CGPoint(x: 420, y: 840), end: CGPoint(x: 600, y: 300), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    if compact {
        context.addPath(CGPath(roundedRect: CGRect(x: 240, y: 208, width: 544, height: 58),
                               cornerWidth: 29, cornerHeight: 29, transform: nil))
        context.setFillColor(color(0xD4EBEE))
        context.fillPath()
    } else {
        let lid = CGPath(roundedRect: CGRect(x: 274, y: 260, width: 476, height: 24),
                         cornerWidth: 12, cornerHeight: 12, transform: nil)
        context.addPath(lid)
        context.setFillColor(color(0xD5ECEF))
        context.fillPath()

        let base = CGMutablePath()
        base.move(to: CGPoint(x: 232, y: 241))
        base.addLine(to: CGPoint(x: 792, y: 241))
        base.addCurve(to: CGPoint(x: 754, y: 201),
                      control1: CGPoint(x: 788, y: 217), control2: CGPoint(x: 776, y: 201))
        base.addLine(to: CGPoint(x: 270, y: 201))
        base.addCurve(to: CGPoint(x: 232, y: 241),
                      control1: CGPoint(x: 248, y: 201), control2: CGPoint(x: 236, y: 217))
        base.closeSubpath()
        context.saveGState()
        context.addPath(base)
        context.clip()
        context.drawLinearGradient(
            gradient([color(0xBDD8DF), color(0x71949F)], locations: [0, 1]),
            start: CGPoint(x: 512, y: 241), end: CGPoint(x: 512, y: 201), options: []
        )
        context.restoreGState()
    }

    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: render-icon <output.iconset>")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let file = output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try renderIcon(size: points * scale).write(to: file)
    }
}
