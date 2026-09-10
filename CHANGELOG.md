# 更新日志

## v2.1

**封面修复（重头戏）**

- 找到侧载书没封面的真正原因：Calibre 写了 `EXTH 501 = EBOK` + 随机假 ASIN，
  Kindle 联网查不到就把封面换成「暂无图片」。改为 `PDOC`（个人文档）后绕过校验
- 修复 `EXTH` 头读取写死 8192 字节的 bug —— 封面缩略图嵌在文件头里时，
  501 记录会落到 14KB 开外，导致补丁静默失败、扫描也整本跳过。
  改为按需渐进读取（64KB 起，翻倍，上限 8MB）
- 封面尺寸小于 400px 会被 Kindle 忽略，统一缩放到 800px
- 新增「修复 Kindle 上已有的书」，批量救回之前手工传的书

**字体**

- mobi/azw/prc（KF7）统一转 azw3（KF8），Kindle 才有字体菜单
- 转换加 `--filter-css=font-family`，去掉 CSS 里的字体锁定

**不再假成功**

- 设备断开后 File Provider 目录仍可读写（走缓存），导致「传输成功」是假的。
  改用 USB 总线检测（Vendor ID 6473）确认设备真的在，没插就拦下

**治好「插上 Kindle 闪一下就弹回书架」**

- 定位到 MacDroid 一发现设备就抢，第一次 MTP 会话必失败，libmtp 强制 reset USB，
  Kindle 因此掉线。改为：没插设备时让 MacDroid 退场，插上后等 4 秒再启动

**界面**

- 新增进度条（解析处理脚本的进度输出，黄→绿）
- 日志去重：同一本书只留一条，「共 N 本」数的是书不是次数
- 转换后用元数据里的中文书名做文件名（不再是一串拼音）
- 右键菜单：打开日志 / 修复已有书籍 / 重连 MacDroid / 防掉线开关

**工程**

- 应用图标（代码生成，`tools/make_icon.swift`）
- 构建脚本 `build.sh`：arm64 + x86_64 通用二进制，ad-hoc 签名，一条命令出包
- 支持 `KINDLE_DOCS` / `KINDLE_LOG_PATH` / `KINDLE_CALIBRE_DIR` 环境变量覆盖
- 源码拆分为 `main.swift` + `DropZoneView.swift` + `kindle_send.py`

## v2.0

- 从 AppleScript droplet 重写为原生 AppKit 悬浮投放区
- 置顶悬浮窗、可拖动、位置记忆、拖入高亮、Esc 退出

## v1.0

- 最初的 AppleScript 拖拽版：把书拖到图标上，自动转换并复制进 Kindle
