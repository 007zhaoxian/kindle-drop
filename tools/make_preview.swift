// tools/make_preview.swift
// 生成 README 用的界面预览图：docs/preview.png
//
// 用法（在仓库根目录）：
//     swiftc -O -o /tmp/mkpreview tools/make_preview.swift src/DropZoneView.swift && /tmp/mkpreview
//
// 界面是真身画的（直接复用 DropZoneView），不是画上去的假图。

import AppKit

let SCALE: CGFloat = 2          // 2x 输出，Retina 上不糊
let BOX_W: CGFloat = 268, BOX_H: CGFloat = 170
let GAP: CGFloat = 26, MARGIN: CGFloat = 26
let LABEL_H: CGFloat = 30
let COUNT = 3

let W = MARGIN * 2 + BOX_W * CGFloat(COUNT) + GAP * CGFloat(COUNT - 1)
let H = LABEL_H + GAP + BOX_H + MARGIN

/// 三种状态各造一个 DropZoneView
func makeStates() -> [(view: DropZoneView, label: String)] {
    // 1) 待机
    let idle = DropZoneView(frame: NSRect(x: 0, y: 0, width: BOX_W, height: BOX_H))
    idle.kindleOK = true
    idle.busy = false
    idle.total = 128
    idle.status = "把书拖到这里"
    idle.detail = "epub 自动转 azw3"

    // 2) 拖入高亮
    let hover = DropZoneView(frame: NSRect(x: 0, y: 0, width: BOX_W, height: BOX_H))
    hover.kindleOK = true
    hover.highlighted = true
    hover.total = 128
    hover.status = "把书拖到这里"
    hover.detail = "epub 自动转 azw3"

    // 3) 传书中
    let busy = DropZoneView(frame: NSRect(x: 0, y: 0, width: BOX_W, height: BOX_H))
    busy.kindleOK = true
    busy.busy = true
    busy.progress = 0.42
    busy.total = 128
    busy.status = "正在处理 7 个…"
    busy.detail = "3/7  如果这是宋史（全七册）"

    return [(idle, "① 待机：拖书进来"),
            (hover, "② 拖入：高亮提示"),
            (busy, "③ 转换中：进度条")]
}

let states = makeStates()

// 两个文件一起编译时不允许顶层语句，所以用 @main 包一层
@main
struct MakePreview {

    static func main() {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(W * SCALE), pixelsHigh: Int(H * SCALE),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { fatalError("无法创建画布") }
        // 注意：rep.size 必须等于像素尺寸（1点=1像素），否则 NSGraphicsContext
        // 会自己再套一层缩放，和下面的 scaleBy 叠加成 4x，画面就溢出了。
        rep.size = NSSize(width: W * SCALE, height: H * SCALE)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: SCALE, y: SCALE)

        let full = NSRect(x: 0, y: 0, width: W, height: H)
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        full.fill()
        NSGradient(starting: NSColor(calibratedWhite: 0.16, alpha: 1),
                   ending: NSColor(calibratedWhite: 0.07, alpha: 1))?.draw(in: full, angle: -90)

        // ---- 逐个画方框 ----
        let boxY = MARGIN
        for (i, item) in states.enumerated() {
            let x = MARGIN + CGFloat(i) * (BOX_W + GAP)
            ctx.saveGState()
            ctx.translateBy(x: x, y: boxY)
            item.view.draw(item.view.bounds)
            ctx.restoreGState()

            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
            ]
            let s = item.label as NSString
            let size = s.size(withAttributes: attr)
            s.draw(at: NSPoint(x: x + (BOX_W - size.width) / 2, y: boxY - size.height - 2),
                   withAttributes: attr)
        }

        NSGraphicsContext.restoreGraphicsState()

        let out = "docs/preview.png"
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
            print("已生成 \(out)  \(Int(W * SCALE))x\(Int(H * SCALE))")
        } else {
            print("写 PNG 失败")
        }
    }
}
