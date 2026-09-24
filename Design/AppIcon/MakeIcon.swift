// Renders the Ouvivre app icon: light / dark / tinted 1024×1024 + macOS sizes.
//   swift MakeIcon.swift ../../Ouvivre/Ouvivre/Assets.xcassets/AppIcon.appiconset
// Same construction as Plutar: solid ground, an opaque back glyph (the sun) and a
// front glyph (the pin) with a cast shadow and a specular sheen. Glyphs are the
// SF Symbols `sun.max` and `mappin.and.ellipse`.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
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
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ img: CGImage, _ path: String) {
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                              UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

// ---------------------------------------------------------------- glyphs
/// A glyph as an alpha mask, trimmed to its ink and scaled so its width is `width`.
struct Glyph { let mask: CGImage; let size: CGSize }

func glyph(_ name: String, weight: NSFont.Weight, width: CGFloat) -> Glyph {
    let cfg = NSImage.SymbolConfiguration(pointSize: 600, weight: weight)
    let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let dim = 1400
    let ctx = newContext(dim)
    let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
    let r = CGRect(x: (CGFloat(dim) - sym.size.width) / 2, y: (CGFloat(dim) - sym.size.height) / 2,
                   width: sym.size.width, height: sym.size.height)
    sym.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let img = ctx.makeImage()!
    // Trim to ink bounds.
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self); let bpr = ctx.bytesPerRow
    var x0 = dim, x1 = 0, y0 = dim, y1 = 0
    for y in 0..<dim { for x in 0..<dim where px[y * bpr + x * 4 + 3] > 8 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    let crop = img.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))!
    let k = width / CGFloat(crop.width)
    return Glyph(mask: crop, size: CGSize(width: width, height: CGFloat(crop.height) * k))
}

/// Fill a glyph, centred on `center`, with `paint`.
func fill(_ ctx: CGContext, _ g: Glyph, center: CGPoint, paint: (CGContext, CGRect) -> Void) {
    let r = CGRect(x: center.x - g.size.width / 2, y: center.y - g.size.height / 2,
                   width: g.size.width, height: g.size.height)
    ctx.saveGState()
    ctx.clip(to: r, mask: g.mask)
    paint(ctx, r)
    ctx.restoreGState()
}

func vgrad(_ ctx: CGContext, _ r: CGRect, _ top: CGColor, _ bottom: CGColor) {
    let g = CGGradient(colorsSpace: sRGB, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// ---------------------------------------------------------------- variants
struct Variant {
    var name: String
    var bg: UInt32?
    var sunTop: UInt32, sunBottom: UInt32
    var pinTop: UInt32, pinBottom: UInt32
    var sheen: Double
    var shadowAlpha: Double
}

let light = Variant(name: "light", bg: 0x9CCBF2,
                    sunTop: 0xE8B400, sunBottom: 0xB98200,
                    pinTop: 0xFF4A3D, pinBottom: 0xE0140C,
                    sheen: 0.38, shadowAlpha: 0.30)
let dark = Variant(name: "dark", bg: 0x0C2C52,
                   sunTop: 0xEDB800, sunBottom: 0xBF8A00,
                   pinTop: 0xFF5245, pinBottom: 0xE8180F,
                   sheen: 0.28, shadowAlpha: 0.55)
let tinted = Variant(name: "tinted", bg: nil,
                     sunTop: 0xBDBDBD, sunBottom: 0x8C8C8C,
                     pinTop: 0xFFFFFF, pinBottom: 0xE6E6E6,
                     sheen: 0.15, shadowAlpha: 0)

// Sun: large, behind, upper right. Pin: in front, lower left, overlapping it.
let sun = glyph("sun.max", weight: .semibold, width: 640)
let pin = glyph("mappin.and.ellipse", weight: .bold, width: 520)
let sunC = CGPoint(x: 566, y: 575)
let pinC = CGPoint(x: 410, y: 405)

func render(_ v: Variant) -> CGImage {
    let ctx = newContext()
    if let bg = v.bg { ctx.setFillColor(c(bg)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S)) }

    fill(ctx, sun, center: sunC) { cx, r in vgrad(cx, r, c(v.sunTop), c(v.sunBottom)) }

    // Cast shadow of the pin onto the sun and ground.
    if v.shadowAlpha > 0 {
        let r = CGRect(x: pinC.x - pin.size.width / 2, y: pinC.y - pin.size.height / 2,
                       width: pin.size.width, height: pin.size.height)
        // Caster drawn off-canvas so only its shadow lands on the artwork (no dark fringe).
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 3000, height: -20), blur: 40, color: c(0x000000, v.shadowAlpha))
        ctx.draw(pin.mask, in: r.offsetBy(dx: -3000, dy: 0))
        ctx.restoreGState()
    }

    fill(ctx, pin, center: pinC) { cx, r in
        vgrad(cx, r, c(v.pinTop), c(v.pinBottom))
        // Specular sheen across the top of the pin.
        let g = CGGradient(colorsSpace: sRGB, colors: [c(0xFFFFFF, v.sheen), c(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
        cx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: r.maxY),
                              end: CGPoint(x: r.midX, y: r.midY), options: [])
    }
    return ctx.makeImage()!
}

func resized(_ img: CGImage, _ n: Int) -> CGImage {
    let ctx = newContext(n)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
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
for v in [(light, images[0])] {
    for (pt, sc) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
        let suffix = sc == 2 ? "@2x" : ""
        writePNG(resized(v.1, pt * sc), "\(outDir)/AppIcon-mac-\(v.0.name)-\(pt)\(suffix).png")
    }
}
print("wrote mac sizes")
