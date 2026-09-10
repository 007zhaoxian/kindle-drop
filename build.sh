#!/usr/bin/env bash
#
# 传到 Kindle —— 构建脚本
#
#   bash build.sh             编译到 dist/传到Kindle.app
#   bash build.sh --zip       顺便打个 zip，方便发 GitHub Release
#   bash build.sh --install   编译后装到 /Applications
#
# 只依赖 Xcode Command Line Tools（swiftc），不需要完整 Xcode。
# 会同时编出 arm64 和 x86_64，合成一个通用二进制，Intel 机器也能跑。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/src"
DIST="$ROOT/dist"
APP_NAME="传到Kindle"
APP="$DIST/$APP_NAME.app"
BIN="KindleDrop"
MIN_MACOS="13.0"

say()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

ZIP=0
INSTALL=0
for a in "$@"; do
    case "$a" in
        --zip)     ZIP=1 ;;
        --install) INSTALL=1 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "未知参数：$a（试试 --help）" ;;
    esac
done

# ---------- 依赖检查 ----------
command -v swiftc >/dev/null 2>&1 || die "找不到 swiftc。先装 Xcode Command Line Tools：xcode-select --install"
command -v lipo   >/dev/null 2>&1 || die "找不到 lipo（Xcode Command Line Tools 的一部分）"

PY=/usr/bin/python3
[ -x "$PY" ] || PY="$(command -v python3 2>/dev/null || true)"
[ -n "${PY:-}" ] || die "找不到 python3。先装 Xcode Command Line Tools：xcode-select --install"

CALIBRE_DIR="${KINDLE_CALIBRE_DIR:-/Applications/calibre.app/Contents/MacOS}"
if [ -x "$CALIBRE_DIR/ebook-convert" ]; then
    say "找到 Calibre：$CALIBRE_DIR"
else
    warn "警告：没找到 $CALIBRE_DIR/ebook-convert —— app 能编译，但转换功能需要 Calibre"
    warn "      下载：https://calibre-ebook.com/download_osx"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Info.plist")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- 编译 ----------
say "编译 arm64 …"
swiftc -O -target "arm64-apple-macos$MIN_MACOS" -o "$TMP/$BIN.arm64" \
      "$SRC/DropZoneView.swift" "$SRC/main.swift"

say "编译 x86_64 …"
swiftc -O -target "x86_64-apple-macos$MIN_MACOS" -o "$TMP/$BIN.x86_64" \
      "$SRC/DropZoneView.swift" "$SRC/main.swift"

lipo -create -output "$TMP/$BIN" "$TMP/$BIN.arm64" "$TMP/$BIN.x86_64"
strip -x "$TMP/$BIN" 2>/dev/null || true

# ---------- 组装 .app ----------
say "组装 $APP_NAME.app …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$TMP/$BIN"                    "$APP/Contents/MacOS/$BIN"
install -m 644 "$SRC/kindle_send.py"          "$APP/Contents/Resources/kindle_send.py"
install -m 644 "$SRC/Info.plist"              "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f "$ROOT/assets/AppIcon.icns" ]; then
    install -m 644 "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    warn "没找到 assets/AppIcon.icns，将显示系统默认图标"
    warn "（可用 tools/make_icon.swift 重新生成）"
fi

# ad-hoc 签名：没有签名 macOS 会直接拒绝启动
if codesign --force --deep --sign - "$APP" >/dev/null 2>&1; then
    say "已做 ad-hoc 签名"
else
    warn "ad-hoc 签名失败，app 可能无法启动"
fi

echo
say "构建完成：$APP   (v$VERSION)"
file "$APP/Contents/MacOS/$BIN" | sed 's/^/  /'
du -sh "$APP" | awk '{print "  体积：" $1}'
echo

# ---------- 可选：打包 / 安装 ----------
if [ "$ZIP" = "1" ]; then
    OUT="$DIST/${APP_NAME}-v${VERSION}.zip"
    rm -f "$OUT"
    # --norsrc：不带 AppleDouble(._*) 冗余条目，包更干净
    ditto -c -k --norsrc --keepParent "$APP" "$OUT"
    say "已打包：$OUT"
    echo "  （别人下载后解开是个 .app，拖进 /Applications 即可）"
    echo
fi

if [ "$INSTALL" = "1" ]; then
    DEST="/Applications/$APP_NAME.app"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    say "已安装到 $DEST"
    echo
fi

cat <<'EOF'
下一步：
  1. 把 dist/传到Kindle.app 拖进 /Applications
  2. 双击启动 —— 屏幕上会出现一个置顶的虚线方框
  3. 把书拖进方框即可

首次打开若被 Gatekeeper 拦住（「无法验证开发者」），执行：
  xattr -dr com.apple.quarantine /Applications/传到Kindle.app

前提：MacDroid 已装好并连接 Kindle（MTP 模式）。见 README.md。
EOF
