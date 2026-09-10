// main.swift
// 传到 Kindle —— 悬浮投放区主程序。
//
// 职责：
//   1. 建一个始终置顶、可拖动的无边框窗口，里面是 DropZoneView
//   2. 盯着 USB 总线和 MacDroid 的状态，决定什么时候挂载 Kindle
//   3. 把拖进来的文件交给 kindle_send.py 处理，并把进度画到界面上
//
// 编译：见仓库根目录 build.sh（swiftc，仅需 Xcode Command Line Tools）

import AppKit

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var dropView: DropZoneView!
    var scriptPath: String = ""
    var logPath: String = ""
    var launchedMacDroid = false
    var mountTried = false
    var mountWaitTicks = 0

    // MacDroid 启停托管：USB 上没有 Kindle 时让 MacDroid 歇着，插上后再延迟几秒拉起。
    // 原因见 MacDroid 日志：插上的瞬间就去抢设备，第一次 MTP 会话必定失败，
    // libmtp 会强制 reset USB 设备 —— 那个 reset 就是 Kindle 掉回书架的元凶。
    // 实测：设备静置后再连，一次成功、1.5 秒挂好、没有任何 reset。
    var manageMacDroid: Bool = true
    var attachAt: Date? = nil
    var lastQuitAttempt: Date? = nil
    let attachSettleSeconds: TimeInterval = 4.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        scriptPath = Bundle.main.path(forResource: "kindle_send", ofType: "py") ?? ""

        // 日志位置：默认桌面，可用 KINDLE_LOG_PATH 覆盖（要和 kindle_send.py 保持一致）
        if let custom = ProcessInfo.processInfo.environment["KINDLE_LOG_PATH"], !custom.isEmpty {
            logPath = (custom as NSString).expandingTildeInPath
        } else {
            logPath = (("~/Desktop/传到Kindle日志.txt") as NSString).expandingTildeInPath
        }

        let w: CGFloat = 268, h: CGFloat = 170
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: screen.midX - w / 2, y: screen.midY - h / 2 + 120)

        if let saved = UserDefaults.standard.string(forKey: "kindleDropPos") {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { origin = NSPoint(x: parts[0], y: parts[1]) }
        }

        window = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        dropView = DropZoneView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        dropView.onFiles = { [weak self] paths in self?.handle(paths) }
        dropView.onQuit = { [weak self] in
            self?.savePos()
            NSApp.terminate(nil)
        }
        dropView.onOpenLog = { [weak self] in self?.openLog() }
        dropView.onMenu = { [weak self] in self?.showMenu() }
        dropView.total = logCount()
        window.contentView = dropView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if UserDefaults.standard.object(forKey: "kindleManageMacDroid") != nil {
            manageMacDroid = UserDefaults.standard.bool(forKey: "kindleManageMacDroid")
        }

        // 不在这里无脑拉起 MacDroid —— 交给下面的状态机按“插上后再启动”的时机来管
        checkKindle()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkKindle()
        }

        let info = "frame=\(NSStringFromRect(window.frame)) visible=\(window.isVisible) level=\(window.level.rawValue) script=\(scriptPath.isEmpty ? "MISSING" : "OK")"
        try? info.write(toFile: "/tmp/kindledrop_status.log", atomically: true, encoding: .utf8)
    }

    func savePos() {
        let o = window.frame.origin
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: "kindleDropPos")
    }

    func applicationWillTerminate(_ notification: Notification) {
        savePos()
        // 退出本 app 就把 MacDroid 恢复常驻，免得不带 app 时没人挂载 Kindle
        if manageMacDroid && !macDroidRunning() {
            let url = URL(fileURLWithPath: "/Applications/MacDroid.app")
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
        }
    }

    // MARK: MacDroid
    func macDroidRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleURL?.lastPathComponent == "MacDroid.app"
        }
    }

    func ensureMacDroidRunning() {
        if macDroidRunning() { return }
        let url = URL(fileURLWithPath: "/Applications/MacDroid.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        launchedMacDroid = true
        dropView.busy = false
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    /// 让 MacDroid 退出。SIGTERM 它不理，所以先请它正常退，1.5 秒还赖着就强杀。
    func quitMacDroid(reason: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.lastPathComponent == "MacDroid.app"
        }) else { return }
        if let last = lastQuitAttempt, Date().timeIntervalSince(last) < 15 { return }
        lastQuitAttempt = Date()
        let pid = app.processIdentifier
        app.terminate()                      // 礼貌请退
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if NSRunningApplication(processIdentifier: pid)?.isTerminated == false {
                kill(pid, SIGKILL)           // 它忽略 SIGTERM，只好强杀
                // 挂载扩展也得一并清掉，否则下次挂载会残留旧句柄
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                p.arguments = ["-9", "-f", "MountProvider.macdroid"]
                try? p.run()
            }
        }
    }

    /// 兜底挂载：USB 上明明插着 Kindle、却迟迟没挂上时，用 MacDroid 自带的
    /// AppleScript 接口（sdef 里有 mount 命令）主动挂一次。
    /// 首次调用 macOS 会弹一次“允许控制 MacDroid”，点允许即可；拒绝也不影响轮询。
    func tryMacDroidMount() {
        guard !mountTried else { return }
        mountTried = true
        let src = """
        tell application "MacDroid"
            repeat with d in devices
                try
                    if (isMounted of d) is false then
                        mount d
                    end if
                end try
            end repeat
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
    }

    // MARK: 日志
    func logCount() -> Int {
        guard let s = try? String(contentsOfFile: logPath, encoding: .utf8) else { return 0 }
        var n = 0
        for line in s.split(separator: "\n") {
            if line.hasPrefix("20") && line.count > 10, line[line.index(line.startIndex, offsetBy: 4)] == "-" {
                n += 1
            }
        }
        return n
    }

    func openLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            try? "Kindle 传书日志  ·  共 0 本\n最新的在最上面\n".write(
                toFile: logPath, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    func showMenu() {
        let menu = NSMenu()
        let items = [
            NSMenuItem(title: "打开传书日志", action: #selector(openLogAction), keyEquivalent: ""),
            NSMenuItem(title: "修复 Kindle 上已有的书", action: #selector(fixExisting), keyEquivalent: ""),
            NSMenuItem(title: "启动 / 重连 MacDroid", action: #selector(reconnectAction), keyEquivalent: ""),
            NSMenuItem(title: manageMacDroid ? "✓ 插上后再启动 MacDroid（防掉线）"
                                             : "　插上后再启动 MacDroid（防掉线）",
                       action: #selector(toggleManageMacDroid), keyEquivalent: ""),
            NSMenuItem.separator(),
            NSMenuItem(title: "退出", action: #selector(quitAction), keyEquivalent: "q"),
        ]
        for it in items { it.target = self; menu.addItem(it) }
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: dropView)
    }

    @objc func openLogAction() { openLog() }

    @objc func quitAction() {
        savePos()
        NSApp.terminate(nil)
    }

    @objc func toggleManageMacDroid() {
        manageMacDroid.toggle()
        UserDefaults.standard.set(manageMacDroid, forKey: "kindleManageMacDroid")
        if manageMacDroid {
            dropView.status = "已开启防掉线"
            dropView.detail = "没插 Kindle 时会让 MacDroid 先退场"
        } else {
            dropView.status = "已关闭防掉线"
            dropView.detail = "MacDroid 会一直常驻"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let v = self?.dropView, !v.busy else { return }
            v.status = "把书拖到这里"
            v.detail = "epub 自动转 azw3"
        }
    }

    @objc func reconnectAction() {
        if !macDroidRunning() {
            ensureMacDroidRunning()
            dropView.kindleOK = true
            dropView.status = "正在启动 MacDroid…"
            dropView.detail = "稍等它连上 Kindle"
        } else {
            dropView.status = "请在 MacDroid 里连接设备"
            dropView.detail = "连好后这里会自动变回绿色"
        }
    }

    @objc func fixExisting() {
        runScript(args: ["--fix-existing"], busyText: "正在修复…")
    }

    // MARK: Kindle 连接检测
    /// USB 总线上有没有 Kindle（Amazon，Vendor ID 6473）。
    /// 必须查物理连接的真正原因：MacDroid 拔线后 File Provider 目录照样能读写（走缓存），
    /// 会造成“写入假成功、书根本没进 Kindle”。返回 nil 表示检测不了，那就别拦。
    func usbHasKindle() -> Bool? {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        t.arguments = ["-p", "IOUSB", "-w0", "-l"]
        let pipe = Pipe()
        t.standardOutput = pipe
        t.standardError = Pipe()
        do { try t.run() } catch { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        t.waitUntilExit()
        let s = String(data: d, encoding: .utf8) ?? ""
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if s.contains("\"idVendor\" = 6473") || s.contains("Amazon") || s.contains("Kindle") {
            return true
        }
        return false
    }

    func docsPath() -> String? {
        let base = (("~/Library/CloudStorage") as NSString).expandingTildeInPath
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: base) else { return nil }
        for item in items where item.hasPrefix("MacDroid-") {
            let docs = base + "/" + item + "/Internal Storage/documents"
            if fm.fileExists(atPath: docs) { return docs }
        }
        return nil
    }

    func checkKindle() {
        let usb = usbHasKindle()
        let hasDocs = docsPath() != nil
        let mdUp = macDroidRunning()
        // 注意：MacDroid 退出后 File Provider 目录照样在（走本地缓存），
        // 光看目录会把「假挂载」当成就绪。必须同时要求 MacDroid 真的在跑。
        let connected = (usb ?? true) && hasDocs && mdUp

        DispatchQueue.main.async {
            let wasOK = self.dropView.kindleOK
            self.dropView.kindleOK = connected
            if self.dropView.busy { return }

            // 就绪：切换成可投放状态
            if connected {
                self.mountWaitTicks = 0
                if !wasOK {
                    self.dropView.status = "Kindle 已就绪"
                    self.dropView.detail = "把书拖进来就行"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        guard let v = self?.dropView, !v.busy, v.kindleOK else { return }
                        v.status = "把书拖到这里"
                        v.detail = "epub 自动转 azw3"
                    }
                }
                return
            }

            // 物理上根本没插
            if usb == false {
                self.attachAt = nil
                self.mountWaitTicks = 0
                if self.manageMacDroid && self.macDroidRunning() {
                    // 关键：没有 Kindle 时让 MacDroid 退场。否则下次一插上它就会
                    // 立刻抢设备 → MTP 会话失败 → 强制 reset USB → Kindle 弹回书架。
                    self.quitMacDroid(reason: "no-device")
                    self.dropView.status = "✗ Kindle 没连上"
                    self.dropView.detail = "插上后我会等几秒再挂载"
                } else {
                    self.dropView.status = "✗ Kindle 没连上"
                    self.dropView.detail = "插好数据线"
                }
                return
            }

            // 插着但还没挂上 —— 记下插上的时间，让设备先静置一会儿
            if self.attachAt == nil {
                self.attachAt = Date()
                self.mountTried = false
                self.mountWaitTicks = 0
            }
            let aged = Date().timeIntervalSince(self.attachAt!)

            if !self.macDroidRunning() {
                if aged < self.attachSettleSeconds {
                    // 静置期：这时候什么都不做，等 Kindle 把 USB 模式切换好
                    self.dropView.status = "Kindle 已插上"
                    self.dropView.detail = "等 \(Int(self.attachSettleSeconds)) 秒再挂载，避免掉线"
                } else {
                    self.ensureMacDroidRunning()
                    self.dropView.status = "正在启动 MacDroid…"
                    self.dropView.detail = "准备挂载 Kindle"
                }
                return
            }

            // MacDroid 已在跑但还没挂上：等几秒兜底主动挂一次
            self.mountWaitTicks += 1
            if self.mountWaitTicks >= 3 { self.tryMacDroidMount() }
            if self.mountWaitTicks >= 10 {
                self.dropView.status = "Kindle 还没挂上"
                self.dropView.detail = "在 MacDroid 里点一下挂载"
            } else {
                self.dropView.status = "正在挂载 Kindle…"
                self.dropView.detail = "MacDroid 正在准备"
            }
        }
    }

    // MARK: 处理
    func handle(_ paths: [String]) {
        // 拖进来先拦一道，避免白折腾
        if usbHasKindle() == false {
            dropView.kindleOK = false
            dropView.status = "✗ Kindle 没连上"
            dropView.detail = "插好线、MacDroid 连上再拖"
            return
        }
        runScript(args: paths, busyText: "正在处理 \(paths.count) 个…")
    }

    func runScript(args: [String], busyText: String) {
        guard !scriptPath.isEmpty else {
            dropView.status = "✗ 缺少处理脚本"
            dropView.detail = "kindle_send.py 不在 app 里"
            return
        }
        dropView.busy = true
        dropView.status = busyText
        dropView.detail = "准备中…"
        dropView.progress = 0

        let script = scriptPath
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [script] + args
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            var buf = Data()
            var okCount = 0
            var failCount = 0
            var total = 0
            var lastLine = ""

            pipe.fileHandleForReading.readabilityHandler = { fh in
                let d = fh.availableData
                guard !d.isEmpty else { return }
                buf.append(d)
                while let idx = buf.firstIndex(of: 0x0A) {
                    let lineData = buf.subdata(in: 0..<idx)
                    buf.removeSubrange(0...idx)
                    guard let line = String(data: lineData, encoding: .utf8) else { continue }
                    let l = line.trimmingCharacters(in: .newlines)

                    if l.contains("✓") { okCount += 1 }
                    if l.contains("✗") || l.contains("❌") { failCount += 1 }
                    if l.hasPrefix("@@TOTAL:") {
                        total = Int(l.replacingOccurrences(of: "@@TOTAL:", with: "")) ?? 0
                    }
                    if l.hasPrefix("@@PROGRESS:") {
                        let rest = l.replacingOccurrences(of: "@@PROGRESS:", with: "")
                        let seg = rest.split(separator: "|", maxSplits: 1)
                        let nums = seg[0].split(separator: "/")
                        if nums.count == 2, let cur = Double(nums[0]), let tot = Double(nums[1]), tot > 0 {
                            let name = seg.count > 1 ? String(seg[1]) : ""
                            lastLine = "\(Int(cur))/\(Int(tot))  \(name)"
                            DispatchQueue.main.async {
                                self.dropView.progress = cur / tot
                                self.dropView.detail = lastLine
                            }
                        }
                    }
                    if l.hasPrefix("❌") {
                        DispatchQueue.main.async { self.dropView.detail = "Kindle 没连上" }
                    }
                }
            }

            do {
                try task.run()
                task.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
            } catch {
                failCount += 1
            }

            let finalCount = total > 0 ? total : self.logCount()
            DispatchQueue.main.async {
                self.dropView.busy = false
                self.dropView.total = finalCount
                self.dropView.progress = okCount > 0 ? 1.0 : -1
                if okCount > 0 {
                    self.dropView.status = "✓ 已传 \(okCount) 本到 Kindle"
                    self.dropView.detail = failCount > 0
                        ? "另有 \(failCount) 个失败"
                        : "断开后 Kindle 会自动刷新"
                } else if failCount > 0 {
                    self.dropView.status = "✗ 一个都没传成功"
                    self.dropView.detail = "查看桌面日志了解原因"
                } else {
                    self.dropView.status = "完成"
                    self.dropView.detail = "没有需要处理的文件"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    guard let v = self?.dropView, !v.busy else { return }
                    v.progress = -1
                    if v.kindleOK {
                        v.status = "把书拖到这里"
                        v.detail = "epub 自动转 azw3"
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
