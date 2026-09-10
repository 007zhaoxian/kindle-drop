// tools/make_icon.swift
// 生成 App 图标：assets/AppIcon.icns（以及一张 1024 的 PNG 备用）
//
// 用法（在仓库根目录）：
//     swiftc -O -o /tmp/mkicon tools/make_icon.swift && /tmp/mkicon
//
// 不需要装设计工具，图标是代码画出来的，改配色直接改下面的常量即可。

import AppKit

let S: CGFloat = 1024

// ---- 配色 ----
let bgTop    = NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.28, alpha: 1)
let bgBottom = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
let inkWhite = NSColor(calibratedWhite: 0.97, alpha: 1)
let greenA   = NSColor(calibratedRed: 0.30, green: 0.88, blue: 0.48, alpha: 1)
let greenB   = NSColor(calibratedRed: 0.13, green: 0.66, blue: 0.32, alpha: 1)

/// 画圆角矩形，可选填充/描边
func roundRect(_ r: NSRect, _ radius: CGFloat,
               fill: NSColor? = nil,
               stroke: NSColor? = nil,
               lineWidth: CGFloat = 0) {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    if let f = fill {
        f.setFill()
        p.fill()
    }
    if let s = stroke, lineWidth > 0 {
        p.lineWidth = lineWidth
        s.setStroke()
        p.stroke()
    }
}

/// 画三角形（用于箭头头部）
func triangle(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, fill: NSColor) {
    let p = NSBezierPath()
    p.move(to: a)
    p.line(to: b)
    p.line(to: c)
    p.close()
    fill.setFill()
    p.fill()
}

/// 把图标画进当前图形上下文（坐标系已翻成左上原点）
func drawIcon() {
    // macOS 图标规范：内容约占 82%，四周留白
    let squircle = NSRect(x: 100, y: 100, width: 824, height: 824)
    let radius = 824 * 0.2237

    // 阴影底
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    roundRect(squircle, radius, fill: bgBottom)
    NSGraphicsContext.restoreGraphicsState()

    // 背景渐变（从上到下加深）
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(roundedRect: squircle, xRadius: radius, yRadius: radius)
    clip.addClip()
    NSGradient(starting: bgTop, ending: bgBottom)?.draw(in: squircle, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // ---- 设备（白色描边的平板）----
    let device = NSRect(x: 262, y: 392, width: 500, height: 442)
    roundRect(device, 46, stroke: inkWhite, lineWidth: 30)
    roundRect(NSRect(x: 322, y: 452, width: 380, height: 292), 22,
              fill: NSColor(calibratedWhite: 1, alpha: 0.10))
    roundRect(NSRect(x: 452, y: 782, width: 120, height: 15), 7.5,
              fill: NSColor(calibratedWhite: 1, alpha: 0.38))

    // ---- 箭头（绿色，从上落下、扎进设备）----
    // 画在设备之后，尖端压在设备边框上，读起来才是「传进去」而不是「从背后戳出来」
    NSGraphicsContext.saveGraphicsState()
    let arrowClip = NSBezierPath()
    arrowClip.appendRect(NSRect(x: 480, y: 178, width: 64, height: 128))
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 398, y: 306))
    head.line(to: NSPoint(x: 626, y: 306))
    head.line(to: NSPoint(x: 512, y: 432))
    head.close()
    arrowClip.append(head)
    arrowClip.addClip()
    let arrowBox = NSRect(x: 398, y: 178, width: 228, height: 254)
    NSGradient(starting: greenA, ending: greenB)?.draw(in: arrowBox, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

// ---- 渲染 ----
func renderPNG(size: CGFloat, to path: String) {
    let px = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 翻成左上原点，方便按「从上到下」的直觉写坐标
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    drawIcon()

    NSGraphicsContext.restoreGraphicsState()

    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(atPath: iconset)
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// 主图 1024
let master = (outDir as NSString).appendingPathComponent("icon_1024.png")
renderPNG(size: 1024, to: master)

// iconset 需要的各种尺寸
let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for spec in specs {
    let dest = (iconset as NSString).appendingPathComponent("\(spec.name).png")
    // 注意：Process 不能复用，每张图都新建一个
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(Int(spec.px))", "\(Int(spec.px))", master, "--out", dest]
    task.standardOutput = Pipe()      // sips 会回显输入路径，屏蔽掉
    task.standardError = Pipe()
    try? task.run()
    task.waitUntilExit()
}

print("已生成 \(iconset) 和 \(master)")
print("下一步：iconutil -c icns \"\(iconset)\" -o \"\(outDir)/AppIcon.icns\"")
