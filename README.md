# 传到 Kindle

> 拖一下就完事 —— 把电子书拖进屏幕上的悬浮方框，自动转格式、修封面、传进 Kindle。

[![Release](https://img.shields.io/github/v/release/007zhaoxian/kindle-drop?label=%E4%B8%8B%E8%BD%BD&color=blue)](../../releases/latest)
[![Build](https://img.shields.io/github/actions/workflow/status/007zhaoxian/kindle-drop/build.yml?label=build)](../../actions)
[![License](https://img.shields.io/github/license/007zhaoxian/kindle-drop?label=license&color=green)](LICENSE)

*[English →](README_EN.md)*

---

> [!IMPORTANT]
> ## ⚠️ 用之前先看这一条
>
> **必须先在 Mac 上装好 MacDroid，而且要能「写入设备」的 Pro 版。**
>
> 2024 年之后的 Kindle（Paperwhite 12 代、Colorsoft、Scribe 等）USB 走的是 **MTP** 协议，
> macOS 原生不支持 —— Finder 里根本看不到 Kindle，任何传书工具都无从下手。
> MacDroid 负责把 Kindle 挂载成普通文件夹，**它是硬前置，不是可选项**。
>
> 另外，官方免费版**只能 设备 → Mac 单向导出**，往 Kindle 里写书属于 Pro 功能：
>
> | MacDroid 版本 | 能否用本工具 |
> |---|---|
> | 免费版 | ❌ 读取可以，写入会失败 |
> | **Pro 版** | ✅ 正常使用 |
>
> 本工具不去检查 MacDroid 的版本或授权状态，但**没有 Pro，就一定会在写入那一步失败**。
> 官方下载：<https://www.macdroid.app/>
>
> 装完之后确认三件事：**用数据线（不是充电线）、直连不要过 hub、Kindle 亮屏解锁停在主界面**。

---

![界面预览](docs/preview.png)

Mac 上用数据线给 Kindle 传书，坑是真的多：Finder 根本看不到设备、传过去的书全都没有封面、
mobi 在 Kindle 上死活改不了字体、Calibre 还会把书塞到 Kindle 认不出的目录里。
这个小工具把这一串麻烦事全包了 —— **你只管把书拖进去**。

---

## 它替你做了什么

| 步骤 | 细节 |
|---|---|
| **① 认格式** | `epub / doc / docx / html / rtf / fb2 / mobi / azw / prc` → 转成 **azw3**；`azw3 / kfx / pdf / txt` 直接传 |
| **② 修封面** | 提取封面 → 尺寸统一到 800px（太小的放大，Kindle 会忽略小图）→ 强制嵌入 → 再用**个人文档标记**挡掉亚马逊的封面替换 |
| **③ 解锁字体** | 去掉 CSS 里的字体锁定，Kindle 的 Aa 菜单才能真正换字体（宋体等） |
| **④ 放对地方** | 只写进 Kindle 认得的 `documents/` 目录，绝不错放到别处 |
| **⑤ 真校验** | 写完轮询确认真的落盘了；传之前先确认设备真的插着，**不给你假成功** |
| **⑥ 记日志** | `~/Desktop/传到Kindle日志.txt`，最新的在最上面，每本标了封面 ✓ 字体 ✓ |

---

## 环境要求

| 需要什么 | 说明 |
|---|---|
| **macOS 13+** | 支持 Apple Silicon 和 Intel（发布的是通用二进制） |
| **MacDroid** | 把 Kindle 挂载成文件系统。2024 年后的 Kindle 走 MTP，macOS 原生不支持，**必须有它** |
| **Calibre** | 格式转换和元数据读写。默认找 `/Applications/calibre.app`，可用 `KINDLE_CALIBRE_DIR` 改 |
| **Xcode Command Line Tools** | 自己编译时需要（提供 `swiftc` 和 `/usr/bin/python3`）。下载现成的 app 则不需要 |

> MacDroid **必须装，且必须是 Pro 版**（免费版只能设备 → Mac 导出，写不进去）。
> 详见文首的前置条件说明 —— 本工具不检查版本，但没有 Pro 会在写入那一步失败。

---

## 安装

### 方式一：下载现成的

到 [Releases](../../releases) 下载 `KindleDrop-v2.1.zip`，解压得到 `传到Kindle.app`，
拖进 `/Applications` 即可。

因为没买苹果开发者证书（ad-hoc 签名），首次打开会被 Gatekeeper 拦一下：

```bash
xattr -dr com.apple.quarantine /Applications/传到Kindle.app
```

或者：右键点 app → 打开 → 在弹窗里再点「打开」。

### 方式二：自己编译

```bash
git clone https://github.com/007zhaoxian/kindle-drop.git
cd kindle-drop
bash build.sh            # 编译到 dist/传到Kindle.app
bash build.sh --zip      # 顺便打个 zip
bash build.sh --install  # 直接装到 /Applications
```

只需 Xcode Command Line Tools，**不需要完整 Xcode**：

```bash
xcode-select --install
```

---

## 使用

1. 插上 Kindle，**亮屏解锁**，在 MacDroid 里连上（连接模式选 **MTP**）
2. 双击 **传到Kindle.app** —— 屏幕上出现一个置顶的虚线方框
3. 把书**拖进方框**，松手
4. 方框会显示进度条，完成后提示「✓ 已传 N 本到 Kindle」
5. 断开 Kindle（或拔线），它会自动重新扫描，书就出来了

方框可以拖到任意位置（位置会记住），始终浮在所有窗口最上面，翻文件夹时不会被盖住。

### 方框上的交互

| 操作 | 效果 |
|---|---|
| 拖动方框 | 挪到任意位置，下次启动还在那儿 |
| 点底部「已传 N 本·点这里看日志」 | 打开传书日志 |
| 右键 | 弹出菜单（见下） |
| 右上角 ✕ / 按 Esc | 退出 |

### 右键菜单

- **打开传书日志**
- **修复 Kindle 上已有的书** —— 把已经在 Kindle 里的 mobi 转成 azw3、补封面、改个人文档标记。以前手工传的书也一起救
- **启动 / 重连 MacDroid**
- **✓ 插上后再启动 MacDroid（防掉线）** —— 见下文「Kindle 弹回书架」
- **退出**

---

## 工作原理

这部分是踩坑踩出来的，记下来省得别人再踩一遍。

### 1. 侧载的书为什么没有封面

Calibre 转出来的 azw3，文件头 EXTH 里写着：

```
501 (CDE Type) = EBOK
113 (ASIN)     = 3128ea59-3fad-…      ← Calibre 随机生成的假号
```

`EBOK` 是「电子书」，Kindle 一联网就拿着这个假 ASIN 去亚马逊查封面 —— 查不到，
于是把封面替换成「暂无图片」。商店买的书有真 ASIN，所以**只有数据线传的没封面**。

解法是把类型改成 **`PDOC`（个人文档）**：亚马逊对个人文档不做校验，Kindle 直接读书里自带的封面。
`EBOK` 和 `PDOC` 都是 4 字节，原地替换即可，不用重写整个文件。

> ⚠️ 别指望 Calibre 自己搞定。它有个 `--share-not-sync` 选项，效果是**删掉** 501 记录，
> 结果 Kindle 只显示书名占位图，还是没封面。

**一个隐蔽的坑**：Calibre 会把封面缩略图嵌进 MOBI 文件头，书名长的书 EXTH 头能落到
**14KB 开外**。如果读文件时写死了「只读开头 8KB」，这类书的 501 就读不到 —— 补丁会**静默失败**，
扫描时还会把「需要修复」的书整本跳过。所以这里按需渐进读取（64KB 起步，不够就翻倍，上限 8MB）。

### 2. 为什么 mobi 在 Kindle 上改不了字体

`mobi` / `azw` / `prc` 都是 **KF7** 老格式，Kindle 不给它们换字体，这是格式决定的。
转成 **azw3（KF8）** 才有字体菜单。

还有一层：就算转成 azw3，如果书里的 CSS 写死了 `font-family`，Kindle 的 Aa 菜单还是不起作用。
转换时加 `--filter-css=font-family` 把这类声明去掉，字体才能真正由你选。

> **PDF 是例外**：固定版式，永远改不了字体，无解。工具会照传，并在日志里标出来。

### 3. 为什么会出现「传输成功」但其实没传进去

MacDroid 用的是 macOS 的 **File Provider** 机制。设备拔掉之后，那个挂载目录**依然存在、
依然能读能写能删**（走的是本地缓存），完全看不出来设备已经不在。

实测：往里面写 2000 字节再读回来，内容一模一样 —— 「成功」是假的，书根本没进 Kindle。

系统的 File Provider 接口查不出连接状态，所以这里改用**物理事实**判断：
查 USB 总线上有没有 Amazon 的设备（Vendor ID `6473` / `0x1949`）。没插就不让传，直接红字拦住。

> 调试时可用 `KINDLE_SKIP_USB_CHECK=1` 跳过这道检查。

### 4. 为什么 Kindle 会「闪一下已连接就弹回书架」

看 MacDroid 自己的日志（`~/Library/Logs/MacDroid.log`），每次插上都是同一套动作：

```
PTP_ERROR_IO: failed to open session        ← 第一次开 MTP 会话就失败
LIBMTP libusb: Attempt to reset device      ← 于是强制重置 USB 设备
libusb left  →  libusb arrived              ← Kindle 被踢下线，重新枚举
mounted disk ... via FileProvider           ← 第二次才挂上
```

**那个「强制重置 USB 设备」就是元凶** —— 对 Kindle 来说等于被拔了一次线，所以它退回书架。

根因是 MacDroid **一发现设备就立刻去抢**，而那会儿 Kindle 还没把 USB 模式切换完，第一次必然失败。

实测：把 MacDroid 关掉、让设备静置几秒再启动它 —— **一次成功、1.5 秒挂好、零重置**。

所以本工具接管了 MacDroid 的启停时机：

- USB 上没有 Kindle → 让 MacDroid 退场歇着
- 你插上 Kindle → **先等 4 秒**，再启动 MacDroid 去挂载

不想要这个行为？右键菜单里取消勾选即可（偏好键 `cn.user.kindledrop` 下的 `kindleManageMacDroid`），
取消后就退回「MacDroid 常驻」的老样子。

### 5. 其他两个小坑

- **File Provider 上不能 move/rename**：`move` 会「假成功」（复制过去了，但源文件没删），
  清理时容易连源带目标一起误删。所以全程只用 `copy2`。
- **写入有可见性延迟**：刚写完立刻 `ls` 可能看不到。写完会轮询几次确认落盘，才算成功。

---

## 常见问题

**打开提示「无法验证开发者」**
```bash
xattr -dr com.apple.quarantine /Applications/传到Kindle.app
```

**方框一直红字「Kindle 没连上」**
按顺序检查：Kindle 是否**亮屏解锁**（休眠时 MTP 不响应）→ 线是否是**数据线**（很多线只能充电）→
是否**直连**没接 hub → MacDroid 里是否已经连上。

**传完了 Kindle 上看不到书**
断开设备（或拔线）后 Kindle 会重新扫描 `documents/`。等十几秒还没有就**长按电源键 40 秒重启**。

**封面还是没出来 / 还是旧的**
封面是 Kindle 建索引时生成的。断开重连；还不行就长按电源键 40 秒重启。
已经在 Kindle 里的老书，用右键菜单的「修复 Kindle 上已有的书」批量救一遍。

**第一次运行时弹出「想控制 MacDroid」**
这是它的兜底挂载机制（Kindle 该挂上却迟迟没挂上时，调 MacDroid 自己的脚本接口主动挂一次）。
点「允许」即可。拒绝也不影响正常使用。

**为什么非要 MacDroid？**
2024 年起的 Kindle（Basic 11 / Paperwhite 12 / Colorsoft / Scribe）USB 改用 **MTP**，
macOS 原生不认。同类工具还有 OpenMTP、MacDroid。本工具直接读 MacDroid 的挂载路径。

**MacDroid 免费版能用吗？**
官方说 Mac → 设备写入需要 Pro。代码不检查版本，你试试就知道。

---

## 只想要命令行版

图形界面只是个「投放区」，真正干活的是 `src/kindle_send.py`，可以单独用：

```bash
# 传书
python3 src/kindle_send.py ~/书/某本书.epub ~/书/另一本.pdf

# 批量修复 Kindle 上已有的书
python3 src/kindle_send.py --fix-existing
```

环境变量（都可选）：

| 变量 | 作用 | 默认 |
|---|---|---|
| `KINDLE_CALIBRE_DIR` | Calibre 命令行目录 | `/Applications/calibre.app/Contents/MacOS` |
| `KINDLE_DOCS` | Kindle 的 `documents` 目录 | 自动在 `~/Library/CloudStorage` 里找 `MacDroid-*` |
| `KINDLE_LOG_PATH` | 日志文件路径 | `~/Desktop/传到Kindle日志.txt` |
| `KINDLE_SKIP_USB_CHECK` | 设为 `1` 跳过 USB 检测（调试用） | 不跳过 |

用别的挂载方式（比如 `simple-mtpfs`）时，把 `KINDLE_DOCS` 指到挂载点就行。

---

## 已知限制

- **强依赖 MacDroid**：默认挂载路径写死 `~/Library/CloudStorage/MacDroid-*/Internal Storage/documents`。
  用别的挂载工具请设 `KINDLE_DOCS`
- **不碰 DRM**：只处理无加密的书。亚马逊买的 AZW/KFX 加密书不在范围内
- **PDF 改不了字体**：格式决定的，无解
- **不做书库管理**：不重命名系列、不归类别、不下载元数据，只负责「把书准确送进 Kindle」
- 传书时 Kindle 必须**亮屏解锁**
- 「插上后再启动 MacDroid」需要本工具持续运行才能生效（关了它就退回 MacDroid 常驻）

---

## 目录结构

```
.
├── build.sh                 # 一键编译（swiftc → 通用二进制 → .app → ad-hoc 签名）
├── src/
│   ├── main.swift           # 主程序：窗口、USB 检测、MacDroid 启停状态机
│   ├── DropZoneView.swift   # 悬浮投放区视图（全部自绘）
│   ├── kindle_send.py       # 传书引擎：转换 / 封面 / 字体 / 日志
│   └── Info.plist
├── assets/
│   └── AppIcon.icns         # 应用图标（由 tools/make_icon.swift 生成）
├── tools/
│   ├── make_icon.swift      # 用代码画图标
│   └── make_preview.swift   # 渲染 README 里的界面预览图
├── docs/                    # 预览图 / 图标大图
└── dist/                    # 构建产物（不入库）
```

图标和预览图都是**代码画出来的**，改配色直接改常量重新跑就行，不需要设计工具：

```bash
swiftc -O -o /tmp/mkicon tools/make_icon.swift && /tmp/mkicon /tmp/out
iconutil -c icns /tmp/out/AppIcon.iconset -o assets/AppIcon.icns

swiftc -O -o /tmp/mkpreview tools/make_preview.swift src/DropZoneView.swift && /tmp/mkpreview
```

---

## 免责声明

本工具只帮你把**自己电脑上的电子书**传进**自己的** Kindle，不做格式破解、不绕过 DRM。
请遵守你所在地区的版权法规，不要用它分发受版权保护的内容。

与 Amazon、Calibre、MacDroid 均无关联。

## 许可

[MIT](LICENSE)
