// Renders the Oùvivre app icon: light / dark / tinted 1024×1024 + macOS sizes.
//   swift MakeIcon.swift ../../Ouvivre/Ouvivre/Assets.xcassets/AppIcon.appiconset
// A landscape painting: a sky and two hills seen through a frosted-glass frame,
// on a solid ground. Same construction as Plutar — opaque artwork behind, real
// frosted glass in front (backdrop sampled, blurred, tinted, specular + rim).

import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

// ---------------------------------------------------------------- geometry
let S: CGFloat = 1024

// The frame: outer and inner rounded rectangles, centred on the canvas.
let frameOuter = CGRect(x: 132, y: 204, width: 760, height: 616)
let frameT: CGFloat = 52
let frameInner = frameOuter.insetBy(dx: frameT, dy: frameT)
let outerR: CGFloat = 96, innerR: CGFloat = 46

/// A point given on a 620×480 grid laid over the picture, scaled to fit it.
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: frameInner.minX + x * frameInner.width / 620, y: frameInner.minY + y * frameInner.height / 480)
}
let sunC = P(150, 120)
let sunR: CGFloat = 58

// ---------------------------------------------------------------- helpers
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func c(_ hex: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255, CGFloat(a)])!
}

func newContext(_ size: Int = Int(S)) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(size))          // work in y-down coordinates
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    return ctx
}

/// Draw a CGImage upright inside our y-down context.
func draw(_ img: CGImage, in ctx: CGContext, rect: CGRect = CGRect(x: 0, y: 0, width: S, height: S)) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: rect.minX, y: S - rect.maxY, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat], center: CGPoint, r0: CGFloat, r1: CGFloat) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: r0, endCenter: center, endRadius: r1,
                           options: [.drawsAfterEndLocation])
}

func blur(_ img: CGImage, radius: Double) -> CGImage {
    let ci = CIImage(cgImage: img)
    let f = CIFilter(name: "CIGaussianBlur")!
    f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
    f.setValue(radius, forKey: kCIInputRadiusKey)
    let out = f.outputImage!.cropped(to: ci.extent)
    return CIContext(options: [.workingColorSpace: sRGB]).createCGImage(out, from: ci.extent)!
}

func writePNG(_ img: CGImage, _ path: String) {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                              UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

func resized(_ img: CGImage, _ n: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
    return ctx.makeImage()!
}

// ---------------------------------------------------------------- shapes
func rrect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// The glass frame: outer rounded rectangle minus the inner one (even-odd).
func framePath() -> CGPath {
    let p = CGMutablePath()
    p.addPath(rrect(frameOuter, outerR))
    p.addPath(rrect(frameInner, innerR))
    return p
}

/// A hill: a smooth crest between two points on the picture's edges, closed along the bottom.
func hillPath(_ pts: [CGPoint], _ curves: [(CGPoint, CGPoint)]) -> CGPath {
    let p = CGMutablePath()
    let r = frameInner
    p.move(to: pts[0])
    for (i, cc) in curves.enumerated() { p.addCurve(to: pts[i + 1], control1: cc.0, control2: cc.1) }
    p.addLine(to: CGPoint(x: r.maxX + 20, y: r.maxY + 20))
    p.addLine(to: CGPoint(x: r.minX - 20, y: r.maxY + 20))
    p.closeSubpath()
    return p
}

let backHill: CGPath = hillPath(
    [P(230, 470), P(440, 262), P(650, 300)],
    [(P(300, 340), P(350, 262)), (P(520, 262), P(590, 280))])

let frontHill: CGPath = hillPath(
    [P(-30, 330), P(240, 292), P(650, 400)],
    [(P(50, 312), P(140, 292)), (P(370, 292), P(500, 375))])

// ---------------------------------------------------------------- variants
struct Variant {
    var name: String
    var bg: UInt32?                                    // flat ground, nil = transparent
    var skyTop: UInt32, skyBottom: UInt32
    var backTop: UInt32, backBottom: UInt32
    var frontTop: UInt32, frontBottom: UInt32
    var sunInner: UInt32, sunMid: UInt32, sunOuter: UInt32
    var glassTint: UInt32, glassAlpha: Double
    var strokeAlpha: Double
    var specular: Double
    var shadowAlpha: Double
    var frost = true
}

let light = Variant(name: "light", bg: 0x5F8FC7,
                    skyTop: 0x5FB0F2, skyBottom: 0xBFE5FB,
                    backTop: 0x6DBB86, backBottom: 0x3E9463,
                    frontTop: 0x5DB65F, frontBottom: 0x2F8A45,
                    sunInner: 0xFFE07A, sunMid: 0xEBB300, sunOuter: 0xC48A00,
                    glassTint: 0xFFFFFF, glassAlpha: 0.62,
                    strokeAlpha: 0.95, specular: 0.50, shadowAlpha: 0.28)

let dark = Variant(name: "dark", bg: 0x000000,
                   skyTop: 0x1B4E92, skyBottom: 0x4C86C4,
                   backTop: 0x2E7C58, backBottom: 0x1F5E43,
                   frontTop: 0x2B8C4C, frontBottom: 0x14612F,
                   sunInner: 0xFFE07A, sunMid: 0xEBB300, sunOuter: 0xC48A00,
                   glassTint: 0xFFFFFF, glassAlpha: 0.24,
                   strokeAlpha: 0.38, specular: 0.30, shadowAlpha: 0.50)

let tinted = Variant(name: "tinted", bg: nil,
                     skyTop: 0x9A9A9A, skyBottom: 0xC8C8C8,
                     backTop: 0x7A7A7A, backBottom: 0x606060,
                     frontTop: 0x555555, frontBottom: 0x3A3A3A,
                     sunInner: 0xFFFFFF, sunMid: 0xF0F0F0, sunOuter: 0xD0D0D0,
                     glassTint: 0xFFFFFF, glassAlpha: 0.55,
                     strokeAlpha: 0.55, specular: 0.20, shadowAlpha: 0, frost: false)

// ---------------------------------------------------------------- drawing
/// Fill `path` with a top-to-bottom gradient, plus a light falling off to the lower right.
func gradientFill(_ ctx: CGContext, _ path: CGPath, top: UInt32, bottom: UInt32) {
    let box = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    linear(ctx, [c(top), c(bottom)], [0, 1], from: CGPoint(x: box.midX, y: box.minY), to: CGPoint(x: box.midX, y: box.maxY))
    linear(ctx, [c(0x000000, 0), c(0x000000, 0.14)], [0.3, 1],
           from: CGPoint(x: box.minX, y: box.minY), to: CGPoint(x: box.maxX, y: box.maxY))
    ctx.restoreGState()
}

/// The picture: sky, sun, two hills — everything that sits *behind* the glass.
func drawPicture(_ ctx: CGContext, _ v: Variant) {
    ctx.saveGState()
    ctx.addPath(rrect(frameInner, innerR)); ctx.clip()

    linear(ctx, [c(v.skyTop), c(v.skyBottom)], [0, 1],
           from: CGPoint(x: 0, y: frameInner.minY), to: CGPoint(x: 0, y: frameInner.minY + frameInner.height * 0.66))

    // Sun with sphere shading.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: sunC.x - sunR, y: sunC.y - sunR, width: sunR * 2, height: sunR * 2)); ctx.clip()
    radial(ctx, [c(v.sunInner), c(v.sunMid), c(v.sunOuter)], [0, 0.55, 1],
           center: CGPoint(x: sunC.x - sunR * 0.3, y: sunC.y - sunR * 0.35), r0: 0, r1: sunR * 1.6)
    ctx.restoreGState()

    gradientFill(ctx, backHill, top: v.backTop, bottom: v.backBottom)
    gradientFill(ctx, frontHill, top: v.frontTop, bottom: v.frontBottom)
    ctx.restoreGState()
}

/// Frosted glass frame over whatever is already in `ctx`.
func drawFrame(_ ctx: CGContext, _ v: Variant) {
    let backdrop = ctx.makeImage()!
    let path = framePath()
    let box = frameOuter

    if v.shadowAlpha > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: c(0x000000, v.shadowAlpha))
        ctx.addPath(path)
        ctx.setFillColor(c(0x000000))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)
    if v.frost { draw(blur(backdrop, radius: 34), in: ctx) }
    ctx.setFillColor(c(v.glassTint, v.glassAlpha))
    ctx.fill(box)
    // Specular sheen across the top-left.
    linear(ctx, [c(0xFFFFFF, v.specular), c(0xFFFFFF, 0)], [0, 1],
           from: CGPoint(x: box.minX, y: box.minY),
           to: CGPoint(x: box.minX + box.width * 0.55, y: box.minY + box.height * 0.6))
    ctx.restoreGState()

    // Rim light on both edges of the frame.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(3)
    ctx.setStrokeColor(c(0xFFFFFF, v.strokeAlpha))
    ctx.strokePath()
    ctx.restoreGState()
}

func render(_ v: Variant) -> CGImage {
    let ctx = newContext()
    if let bg = v.bg { ctx.setFillColor(c(bg)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S)) }
    drawPicture(ctx, v)
    drawFrame(ctx, v)
    return ctx.makeImage()!
}

// ---------------------------------------------------------------- output
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
var images: [CGImage] = []
for v in [light, dark, tinted] {
    let img = render(v); images.append(img)
    writePNG(img, "\(outDir)/AppIcon-\(v.name)-1024.png")
    print("wrote AppIcon-\(v.name)-1024.png")
}
// macOS asset catalogs take only the light set; dark comes from the universal 1024.
for (pt, sc) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    writePNG(resized(images[0], pt * sc), "\(outDir)/AppIcon-mac-light-\(pt)\(sc == 2 ? "@2x" : "").png")
}
print("wrote mac sizes")
