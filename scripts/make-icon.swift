// Generates a macOS .icns from a square logo, masked into the standard
// rounded-square ("squircle-ish") icon shape with Apple's icon-grid margins.
//
//   swift scripts/make-icon.swift logo.png build/AppIcon.icns
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-icon.swift <logo.png> <out.icns>\n".data(using: .utf8)!)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot read \(input.path)\n".data(using: .utf8)!)
    exit(1)
}

/// Render one icon bitmap at `size`×`size` pixels.
func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high

    // macOS icon grid: 824/1024 body, centered, ~185/1024 corner radius.
    let body = s * 824 / 1024
    let rect = CGRect(x: (s - body) / 2, y: (s - body) / 2, width: body, height: body)
    let radius = s * 185.4 / 1024
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow under the body (skipped at tiny sizes where it just blurs).
    if size >= 64 {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 10 / 1024),
            blur: s * 20 / 1024,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(logo, in: rect)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write("cannot write \(url.path)\n".data(using: .utf8)!)
        exit(1)
    }
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

try? fm.removeItem(at: output)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
