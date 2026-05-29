import Cocoa
import CoreGraphics
import ImageIO

// Configuration
let size: CGFloat = 1024
let assetsDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let outputPath = "\(assetsDir)/AppIcon_optimized.png"

// Create bitmap context with alpha
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create context")
    exit(1)
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)

// Clear to transparent
context.clear(rect)

// Draw gradient background (deep dark blue, professional look)
let gradientColors = [
    CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1.0),   // Deep navy
    CGColor(red: 0.10, green: 0.14, blue: 0.22, alpha: 1.0),   // Slightly lighter navy
    CGColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1.0),   // Deep navy again (edge)
] as CFArray

let gradientLocations: [CGFloat] = [0.0, 0.5, 1.0]
guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors,
    locations: gradientLocations
) else {
    print("Failed to create gradient")
    exit(1)
}

// Fill with radial gradient from center
context.drawRadialGradient(
    gradient,
    startCenter: CGPoint(x: size/2, y: size/2),
    startRadius: 0,
    endCenter: CGPoint(x: size/2, y: size/2),
    endRadius: size * 0.72,
    options: [.drawsAfterEndLocation]
)

// === Draw the icon elements ===
let cx = size / 2
let cy = size / 2
let mainRadius: CGFloat = size * 0.28

// Subtle outer glow
let glowColor = CGColor(red: 0.0, green: 0.82, blue: 0.93, alpha: 0.08)
context.setFillColor(glowColor)
context.fillEllipse(in: CGRect(
    x: cx - mainRadius * 1.6,
    y: cy - mainRadius * 1.6,
    width: mainRadius * 3.2,
    height: mainRadius * 3.2
))

// Cyan color for main elements
let cyanColor = CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 1.0)
let cyanDimColor = CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.5)

// --- Outer arc (left side, ~220 degrees) ---
context.setStrokeColor(cyanColor)
context.setLineWidth(size * 0.032)
context.setLineCap(.round)
context.addArc(
    center: CGPoint(x: cx, y: cy),
    radius: mainRadius,
    startAngle: CGFloat.pi * 0.55,
    endAngle: CGFloat.pi * 1.95,
    clockwise: false
)
context.strokePath()

// --- Inner arc (left side, ~180 degrees) ---
context.setLineWidth(size * 0.024)
context.addArc(
    center: CGPoint(x: cx, y: cy),
    radius: mainRadius * 0.70,
    startAngle: CGFloat.pi * 0.7,
    endAngle: CGFloat.pi * 1.8,
    clockwise: false
)
context.strokePath()

// --- Center dot ---
context.setFillColor(cyanColor)
let dotRadius = size * 0.038
context.fillEllipse(in: CGRect(
    x: cx - dotRadius,
    y: cy - dotRadius,
    width: dotRadius * 2,
    height: dotRadius * 2
))

// --- Sound wave bars (right side, audio visualization) ---
context.setStrokeColor(cyanColor)
context.setLineCap(.round)

let barHeights: [CGFloat] = [0.06, 0.11, 0.18, 0.22, 0.18, 0.11, 0.06]
let barStartX = cx + mainRadius * 0.20
let barSpacing = size * 0.038
let barWidth = size * 0.020

for (i, height) in barHeights.enumerated() {
    let x = barStartX + CGFloat(i) * barSpacing
    let halfH = size * height
    context.setLineWidth(barWidth)
    context.move(to: CGPoint(x: x, y: cy - halfH))
    context.addLine(to: CGPoint(x: x, y: cy + halfH))
    context.strokePath()
}

// --- Small REC indicator dot (top-right area) ---
context.setFillColor(CGColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 0.85))
let recDotRadius = size * 0.016
let recX = cx + mainRadius * 0.75
let recY = cy + mainRadius * 0.65  // Note: CoreGraphics Y is flipped
context.fillEllipse(in: CGRect(
    x: recX - recDotRadius,
    y: recY - recDotRadius,
    width: recDotRadius * 2,
    height: recDotRadius * 2
))

// --- Subtle outer ring (very thin, decorative) ---
context.setStrokeColor(CGColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 0.2))
context.setLineWidth(size * 0.006)
context.addArc(
    center: CGPoint(x: cx, y: cy),
    radius: mainRadius * 1.25,
    startAngle: 0,
    endAngle: CGFloat.pi * 2,
    clockwise: false
)
context.strokePath()

// Generate image
guard let cgImage = context.makeImage() else {
    print("Failed to create image")
    exit(1)
}

// Save as PNG
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    print("Failed to create image destination")
    exit(1)
}
CGImageDestinationAddImage(destination, cgImage, nil)
guard CGImageDestinationFinalize(destination) else {
    print("Failed to write image")
    exit(1)
}

print("✅ Icon generated: \(outputPath)")
