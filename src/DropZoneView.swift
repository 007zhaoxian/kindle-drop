// DropZoneView.swift
// 悬浮投放区：虚线方框，接收拖入的文件，显示状态 / 进度 / 已传本数。
// 窗口本身是透明无边框的，所有视觉都在这里自绘。

import AppKit

final class DropZoneView: NSView {

    var onFiles: (([String]) -> Void)?
    var onQuit: (() -> Void)?
    var onOpenLog: (() -> Void)?
    var onMenu: (() -> Void)?

    var highlighted = false { didSet { needsDisplay = true } }
    var status = "把书拖到这里" { didSet { needsDisplay = true } }
    var detail = "epub 自动转 azw3" { didSet { needsDisplay = true } }
    var kindleOK = true { didSet { needsDisplay = true } }
    var busy = false { didSet { needsDisplay = true } }
    var total = 0 { didSet { needsDisplay = true } }
    var progress: Double = -1 { didSet { needsDisplay = true } }   // -1 = 不显示

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    // MARK: 拖拽
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if busy { return [] }
        highlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !busy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let board = sender.draggingPasteboard
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        let paths = urls.map { $0.path }
        guard !paths.isEmpty else { return false }
        onFiles?(paths)
        return true
    }

    // MARK: 绘制
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 6, dy: 6)
        let bgPath = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)

        if highlighted {
            NSColor(calibratedRed: 0.16, green: 0.52, blue: 0.30, alpha: 0.95).setFill()
        } else if busy {
            NSColor(calibratedRed: 0.30, green: 0.26, blue: 0.10, alpha: 0.88).setFill()
        } else {
            NSColor(calibratedWhite: 0.09, alpha: 0.85).setFill()
        }
        bgPath.fill()

        // 虚线边框
        let border = NSBezierPath(roundedRect: r.insetBy(dx: 3.5, dy: 3.5), xRadius: 11, yRadius: 11)
        border.lineWidth = 2.5
        border.setLineDash([7, 5], count: 2, phase: 0)
        if highlighted {
            NSColor(calibratedRed: 0.55, green: 1.0, blue: 0.70, alpha: 1).setStroke()
        } else if busy {
            NSColor.systemYellow.setStroke()
        } else if !kindleOK {
            NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.45, alpha: 0.95).setStroke()
        } else {
            NSColor(calibratedWhite: 0.85, alpha: 0.85).setStroke()
        }
        border.stroke()

        // 标题
        let title = busy ? "正在传书…" : (highlighted ? "松手即传" : "传到 Kindle")
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.white
        ]
        let ts = (title as NSString).size(withAttributes: titleAttr)
        (title as NSString).draw(
            at: NSPoint(x: (bounds.width - ts.width) / 2, y: bounds.height - 34),
            withAttributes: titleAttr
        )

        // 状态
        let statusColor: NSColor
        if !kindleOK && !busy {
            statusColor = NSColor(calibratedRed: 1, green: 0.5, blue: 0.5, alpha: 1)
        } else if status.hasPrefix("✓") {
            statusColor = NSColor(calibratedRed: 0.55, green: 1, blue: 0.7, alpha: 1)
        } else if status.hasPrefix("✗") || status.hasPrefix("❌") {
            statusColor = NSColor(calibratedRed: 1, green: 0.55, blue: 0.55, alpha: 1)
        } else {
            statusColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        }
        let stAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5),
            .foregroundColor: statusColor
        ]
        let ss = (status as NSString).size(withAttributes: stAttr)
        (status as NSString).draw(
            at: NSPoint(x: (bounds.width - ss.width) / 2, y: bounds.height / 2 + 12),
            withAttributes: stAttr
        )

        // 副标题
        if !detail.isEmpty {
            let dAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5),
                .foregroundColor: NSColor(calibratedWhite: 0.68, alpha: 1)
            ]
            let ds = (detail as NSString).size(withAttributes: dAttr)
            let dw = min(ds.width, bounds.width - 20)
            (detail as NSString).draw(
                in: NSRect(x: (bounds.width - dw) / 2, y: bounds.height / 2 - 8,
                           width: dw, height: 16),
                withAttributes: dAttr
            )
        }

        // 进度条
        if progress >= 0 {
            let bar = NSRect(x: 30, y: 48, width: bounds.width - 60, height: 7)
            NSColor(calibratedWhite: 0.28, alpha: 1).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3.5, yRadius: 3.5).fill()

            let filled = max(0.0, min(1.0, progress))
            let w = bar.width * CGFloat(filled)
            if w > 2 {
                let f = NSRect(x: bar.minX, y: bar.minY, width: w, height: bar.height)
                (filled >= 1.0
                    ? NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.5, alpha: 1)
                    : NSColor.systemYellow).setFill()
                NSBezierPath(roundedRect: f, xRadius: 3.5, yRadius: 3.5).fill()
            }
        }

        // 底部：日志入口
        let foot = "已传 \(total) 本 · 点这里看日志"
        let fAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5),
            .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1)
        ]
        let fs = (foot as NSString).size(withAttributes: fAttr)
        (foot as NSString).draw(
            at: NSPoint(x: (bounds.width - fs.width) / 2, y: 14),
            withAttributes: fAttr
        )

        // 右上角关闭按钮
        let xAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1)
        ]
        ("✕" as NSString).draw(at: NSPoint(x: bounds.width - 23, y: bounds.height - 25), withAttributes: xAttr)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x > bounds.width - 34 && p.y > bounds.height - 34 {
            onQuit?()
        } else if p.y < 32 {
            onOpenLog?()
        }
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onQuit?() }
    }

    override var acceptsFirstResponder: Bool { true }
}
