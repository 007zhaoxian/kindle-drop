#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
传到 Kindle —— 传书处理引擎

用法：
    python3 kindle_send.py 书1.epub 书2.pdf ...     # 传书
    python3 kindle_send.py --fix-existing           # 修复 Kindle 上已有的书

它做三件事：
1) 封面修复：提取源封面 -> 统一缩放到 800px（太小的放大、过大的压缩）
   -> 用 --cover 强制嵌入 -> 把 CDE Type 改成 PDOC -> 转换后校验
2) 字体解锁：mobi/azw/prc 是 KF7 老格式，Kindle 上不能改字体，统一转 azw3；
   转换时加 --filter-css=font-family 去掉 CSS 字体锁定，Kindle 才能用你选的宋体
3) 日志记录：默认 ~/Desktop/传到Kindle日志.txt，最新在上

处理规则：
  epub/doc/docx/html/rtf/fb2/mobi/azw/prc -> 转 azw3（解锁字体）
  azw3/kfx/pdf/txt -> 直传（pdf 固定版式，改不了字体）

环境变量（都可选）：
  KINDLE_CALIBRE_DIR  Calibre 命令行目录
  KINDLE_DOCS         Kindle 的 documents 目录（换挂载方式时用）
  KINDLE_LOG_PATH     日志文件路径
  KINDLE_SKIP_USB_CHECK=1  跳过 USB 检测（调试用）

注意：Kindle 只认 documents 目录；File Provider 上禁止 move（会假成功），一律 copy2。
"""

import os
import sys
import glob
import time
import shutil
import struct
import subprocess

# 可用环境变量覆盖（方便换用别的挂载方式，或把日志挪个地方）
#   KINDLE_CALIBRE_DIR  Calibre 命令行目录，默认 /Applications/calibre.app/Contents/MacOS
#   KINDLE_DOCS         Kindle 的 documents 目录，默认自动在 ~/Library/CloudStorage 里找 MacDroid 挂载点
#   KINDLE_LOG_PATH     日志文件路径，默认 ~/Desktop/传到Kindle日志.txt
CALIBRE = os.environ.get("KINDLE_CALIBRE_DIR", "/Applications/calibre.app/Contents/MacOS")
EBOOK_CONVERT = CALIBRE + "/ebook-convert"
EBOOK_META = CALIBRE + "/ebook-meta"

LOG_PATH = os.path.expanduser(
    os.environ.get("KINDLE_LOG_PATH", "~/Desktop/传到Kindle日志.txt"))
DOCS_OVERRIDE = os.environ.get("KINDLE_DOCS", "")
TMPDIR = "/tmp/kindle_send_convert"

# 需要转成 azw3 的（mobi/azw/prc 是 KF7，Kindle 上不能改字体，必须转）
NEED_CONVERT = {".epub", ".mobi", ".azw", ".prc", ".doc", ".docx",
                ".html", ".htm", ".rtf", ".fb2"}
# 直接传的（azw3/kfx 已支持字体切换；pdf 固定版式无法改字体）
DIRECT = {".azw3", ".kfx", ".pdf", ".txt"}

COVER_TARGET = 800   # 封面最长边统一到 800px
COVER_MIN = 400      # 小于此宽度算封面过小，需要放大修复

FIX_EXISTING = "--fix-existing"


def human_size(n):
    if n < 1024:
        return "%dB" % n
    if n < 1024 * 1024:
        return "%.0fKB" % (n / 1024.0)
    return "%.1fMB" % (n / (1024.0 * 1024.0))


def find_kindle_docs():
    """定位 Kindle 的 documents 目录"""
    if DOCS_OVERRIDE:
        return DOCS_OVERRIDE if os.path.isdir(DOCS_OVERRIDE) else None
    base = os.path.expanduser("~/Library/CloudStorage")
    if not os.path.isdir(base):
        return None
    patterns = (
        os.path.join(base, "MacDroid-*", "Internal Storage", "documents"),
        os.path.join(base, "MacDroid-*", "*", "documents"),
    )
    for pattern in patterns:
        hits = [p for p in glob.glob(pattern) if os.path.isdir(p)]
        if hits:
            return hits[0]
    return None


def usb_has_kindle():
    """
    查 USB 总线上有没有 Kindle（Amazon，Vendor ID 6473）。

    为什么必须查这个：MacDroid 的 File Provider 目录在设备拔掉后依然存在，
    照样能读写（走本地缓存），导致写入“假成功”——书根本没进 Kindle。
    所以只能用 USB 总线这个物理事实来判断。

    返回 True=连着 / False=没连 / None=检测不了（那就放行，别误拦）
    """
    for tool in ("/usr/sbin/ioreg", "/usr/bin/ioreg"):
        if not os.path.exists(tool):
            continue
        try:
            r = subprocess.run([tool, "-p", "IOUSB", "-w0", "-l"],
                               capture_output=True, text=True, timeout=20)
            out = r.stdout
            if not out.strip():
                return None          # 沙箱里读不到，别误判
            if ('"idVendor" = 6473' in out) or ("Amazon" in out) or ("Kindle" in out):
                return True
            return False
        except Exception:
            continue
    return None


# ---------------- 封面处理 ----------------

def extract_cover(src, out):
    """从源书里提取封面图"""
    try:
        if os.path.exists(out):
            os.remove(out)
        subprocess.run([EBOOK_META, src, "--get-cover=" + out],
                       capture_output=True, text=True, timeout=120)
    except Exception:
        return False
    return os.path.exists(out) and os.path.getsize(out) > 1000


def cover_width(path):
    """读封面宽度（像素）"""
    try:
        r = subprocess.run(["sips", "-g", "pixelWidth", path],
                           capture_output=True, text=True, timeout=30)
        for line in r.stdout.splitlines():
            if "pixelWidth" in line:
                return int(line.split()[-1])
    except Exception:
        pass
    return 0


def fix_cover(src, out):
    """统一封面尺寸：最长边缩放到 800px（小图放大修复，大图压缩省空间）"""
    try:
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(["sips", "-Z", str(COVER_TARGET), src, "--out", out],
                       capture_output=True, text=True, timeout=60)
    except Exception:
        return False
    return os.path.exists(out) and os.path.getsize(out) > 1000


def book_has_cover(path):
    """检查成书里有没有封面"""
    tmp = os.path.join(TMPDIR, "_probe.jpg")
    ok = extract_cover(path, tmp)
    if ok and os.path.exists(tmp):
        os.remove(tmp)
    return ok


HEAD_LIMIT = 8 * 1024 * 1024   # EXTH 头最远可能到几 MB（封面缩略图嵌在头里）


def read_head(path, limit=HEAD_LIMIT):
    """
    按需读取文件开头，直到找到完整的 EXTH 头。

    为什么不能直接读固定的 8KB：Calibre 会把封面缩略图嵌进 MOBI 头，
    书名/简介长的书 EXTH 头能落到 14KB 开外 —— 老代码固定读 8192 字节，
    于是这些书的 501(CDE Type) 读不到、也改不了，封面就被亚马逊换掉了。
    """
    size = 64 * 1024
    data = b""
    try:
        with open(path, "rb") as f:
            while True:
                chunk = f.read(size)
                if not chunk:
                    break
                data += chunk
                i = data.find(b"EXTH")
                if i >= 0 and len(data) >= i + 16384:
                    break          # 头已完整，别再多读
                if len(data) >= limit:
                    break
                size = min(size * 4, limit)
    except Exception:
        pass
    return data


def read_exth(path):
    """读 MOBI/AZW3 的 EXTH 元数据（按需读取，不写死读取长度）"""
    data = read_head(path)
    if not data:
        return {}
    i = data.find(b"EXTH")
    if i < 0:
        return {}
    count = struct.unpack(">I", data[i + 8:i + 12])[0]
    pos, out = i + 12, {}
    for _ in range(count):
        if pos + 8 > len(data):
            break
        t, l = struct.unpack(">II", data[pos:pos + 8])
        if l < 8:
            break
        out[t] = data[pos + 8:pos + l]
        pos += l
    return out


def cde_type(path):
    """读 501 记录：EBOK / PDOC / EBSP。读不到返回空串"""
    return read_exth(path).get(501, b"").decode("ascii", "replace")


def set_cde_type(path, value=b"PDOC"):
    """
    把 501(CDE Type) 改成 PDOC。
    原因：Calibre 转出来的书是 EBOK + 随机 UUID 假 ASIN，Kindle 一联网就
    拿这个假 ASIN 去亚马逊查封面，查不到就把封面替换成“暂无图片”。
    标成 PDOC（个人文档）后，亚马逊不校验，Kindle 直接读书里自带的封面。
    EBOK 和 PDOC 都是 4 字节，直接原地替换，不用重写整个文件头。
    """
    try:
        data = read_head(path)
        i = data.find(b"EXTH")
        if i < 0:
            return False
        count = struct.unpack(">I", data[i + 8:i + 12])[0]
        pos = i + 12
        target = None
        for _ in range(count):
            if pos + 8 > len(data):
                break
            t, l = struct.unpack(">II", data[pos:pos + 8])
            if l < 8:
                break
            if t == 501 and data[pos + 8:pos + 12] == b"EBOK":
                target = pos + 8           # 记录值的绝对偏移
                break
            pos += l
        if target is None:
            return False
        with open(path, "r+b") as f:
            f.seek(target)
            f.write(value)
            f.flush()
        return True
    except Exception:
        return False


def book_title(path):
    """读成书元数据里的标题（中文书名）"""
    try:
        r = subprocess.run([EBOOK_META, path],
                           capture_output=True, text=True, timeout=60)
        for line in r.stdout.splitlines():
            if line.startswith("Title"):
                t = line.split(":", 1)[1].strip()
                if t and t.lower() != "unknown":
                    return t
    except Exception:
        pass
    return ""


def safe_name(title, default, limit=60):
    """书名转合法文件名"""
    if not title:
        return default
    for c in '/\\:*?"<>|\n\r\t':
        title = title.replace(c, "")
    title = title.strip().strip(".").strip()
    if not title:
        return default
    return title[:limit]


# ---------------- 转换 ----------------

def convert_to_azw3(src, dst, cover=None):
    """
    转成 azw3。
    --filter-css=font-family 去掉 CSS 里的字体声明，这样 Kindle 才能用你选的字体（宋体等）
    --cover 强制嵌入封面
    """
    cmd = [EBOOK_CONVERT, src, dst, "--filter-css=font-family"]
    if cover and os.path.exists(cover):
        cmd.append("--cover=" + cover)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return False
    return r.returncode == 0 and os.path.exists(dst) and os.path.getsize(dst) > 0


def copy_to_kindle(src, dst):
    """
    复制到 Kindle。File Provider 写入有可见性延迟（写完立刻 ls 可能看不到），
    所以写完要轮询校验几次，确认真的落盘了才算成功。
    """
    shutil.copy2(src, dst)
    for _ in range(10):
        try:
            if os.path.exists(dst) and os.path.getsize(dst) > 0:
                return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


# ---------------- 日志 ----------------

def entry_name(entry):
    """从日志行里取书名（用于去重）"""
    parts = [p for p in entry.split("  ") if p.strip()]
    return parts[2].strip() if len(parts) > 2 else entry


def read_log_entries():
    if not os.path.exists(LOG_PATH):
        return []
    out = []
    with open(LOG_PATH, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line[:2] == "20" and line[4:5] == "-":   # 记录行以日期开头
                out.append(line)
    return out


def write_log(entries):
    """
    写入日志：最新在最上面。
    同一本书只留一条（重传就更新时间戳并挪到最上面），
    这样“共 N 本”数的是书，不是传书次数。
    """
    old = read_log_entries()
    fresh = set(entry_name(e) for e in entries)
    kept = [e for e in old if entry_name(e) not in fresh]
    all_entries = entries + kept
    with open(LOG_PATH, "w", encoding="utf-8") as f:
        f.write("Kindle 传书日志  ·  共 %d 本\n" % len(all_entries))
        f.write("最新的在最上面  ·  更新于 %s\n\n" % time.strftime("%Y-%m-%d %H:%M"))
        for e in all_entries:
            f.write(e + "\n")
    return len(all_entries)


def make_entry(name, size, cover, font, note=""):
    ts = time.strftime("%Y-%m-%d %H:%M")
    line = "%s  ✓  %s  %s  封面%s 字体%s" % (
        ts, name.ljust(34), human_size(size).rjust(7),
        "✓" if cover else "✗", "✓" if font else "✗")
    if note:
        line += "  " + note
    return line


# ---------------- 主流程 ----------------

def process_file(p, docs, force=False):
    """处理单个文件，返回结果 dict。force=True 时连 azw3 也重新转换（用于修封面）"""
    p = os.path.abspath(p)
    if not os.path.isfile(p):
        return {"ok": False, "name": os.path.basename(p), "err": "不是文件"}

    filename = os.path.basename(p)
    stem, ext = os.path.splitext(filename)
    ext = ext.lower()

    if ext not in NEED_CONVERT and ext not in DIRECT:
        return {"ok": False, "name": filename, "err": "不支持的格式" + ext}

    os.makedirs(TMPDIR, exist_ok=True)
    raw_cover = os.path.join(TMPDIR, "cover_raw.jpg")
    fixed_cover = os.path.join(TMPDIR, "cover_fixed.jpg")
    cover_path = None
    cover_ok = False

    # 1. 取封面并修复尺寸
    if extract_cover(p, raw_cover):
        w = cover_width(raw_cover)
        if w == 0 or w < COVER_MIN or w > COVER_TARGET * 2:
            if fix_cover(raw_cover, fixed_cover):
                cover_path = fixed_cover
            else:
                cover_path = raw_cover
        else:
            cover_path = raw_cover

    if ext in DIRECT and not force:
        # 直传：azw3/kfx/pdf/txt
        dst = os.path.join(docs, filename)
        existed = os.path.exists(dst)
        src = p
        if ext in (".azw3", ".mobi", ".azw"):
            # 先在临时副本上改类型，不动你原来的文件
            tmp_copy = os.path.join(TMPDIR, "direct" + ext)
            shutil.copy2(p, tmp_copy)
            set_cde_type(tmp_copy)
            src = tmp_copy
        if copy_to_kindle(src, dst):
            cover_ok = book_has_cover(dst)
            return {
                "ok": True,
                "name": filename,
                "size": os.path.getsize(dst),
                "cover": cover_ok,
                "font": ext not in (".pdf",),     # pdf 固定版式，改不了字体
                "note": ("覆盖" if existed else "") + ("·PDOC" if ext != ".pdf" else ""),
            }
        return {"ok": False, "name": filename, "err": "写入 Kindle 失败"}

    # 需要转换
    tmp_out = os.path.join(TMPDIR, "out.azw3")
    if os.path.exists(tmp_out):
        os.remove(tmp_out)

    if not convert_to_azw3(p, tmp_out, cover_path):
        return {"ok": False, "name": filename, "err": "转换失败"}

    # 标成个人文档，挡掉亚马逊的封面替换
    set_cde_type(tmp_out)

    # 用中文书名做文件名（Kindle 上好认）
    title = book_title(tmp_out)
    dst_name = safe_name(title, stem) + ".azw3"
    dst = os.path.join(docs, dst_name)
    existed = os.path.exists(dst)

    if not copy_to_kindle(tmp_out, dst):
        return {"ok": False, "name": filename, "err": "写入 Kindle 失败"}

    size = os.path.getsize(dst)
    cover_ok = book_has_cover(dst)
    note = "已转azw3"
    if cover_path and os.path.exists(raw_cover):
        note += "·修封面"
    if existed:
        note += "·覆盖"

    # 清临时文件
    for f in (tmp_out, raw_cover, fixed_cover):
        if os.path.exists(f):
            try:
                os.remove(f)
            except OSError:
                pass

    return {"ok": True, "name": dst_name, "size": size,
            "cover": cover_ok, "font": True, "note": note}


def usb_ok_or_skip():
    """USB 检测：确认 Kindle 真插着。环境变量 KINDLE_SKIP_USB_CHECK=1 可强制跳过（调试用）"""
    if os.environ.get("KINDLE_SKIP_USB_CHECK") == "1":
        return True
    return usb_has_kindle() is not False


def run(paths):
    # 先确认 Kindle 真的插着，否则写入会“假成功”（File Provider 骗人）
    if not usb_ok_or_skip():
        print("❌ Kindle 没连上\n\n"
              "USB 上找不到 Kindle —— 线没插好，或者 MacDroid 里已经断开了。\n"
              "先把 Kindle 插好、在 MacDroid 里连上，再拖书进来。")
        return

    docs = find_kindle_docs()
    if not docs:
        print("没找到 Kindle 目录。\n\n请先在 MacDroid 里连好 Kindle，\n再把书拖到框里。")
        return

    os.makedirs(TMPDIR, exist_ok=True)
    results = []
    n = len(paths)
    for i, p in enumerate(paths, 1):
        print("@@PROGRESS:%d/%d|%s" % (i, n, os.path.basename(p)), flush=True)
        try:
            results.append(process_file(p, docs))
        except Exception as e:
            results.append({"ok": False, "name": os.path.basename(p),
                            "err": str(e)[:30]})

    entries = []
    ok_count = 0
    for r in results:
        if r["ok"]:
            ok_count += 1
            entries.append(make_entry(r["name"], r["size"],
                                      r.get("cover", False),
                                      r.get("font", False),
                                      r.get("note", "")))

    total = write_log(entries) if entries else len(read_log_entries())

    # 给悬浮窗看的汇总
    lines = []
    if ok_count:
        lines.append("【已传到 Kindle】本次 %d 本" % ok_count)
        for r in results:
            if r["ok"]:
                mark = "✓"
                extra = ""
                if not r.get("cover"):
                    extra = "（无封面）"
                if not r.get("font"):
                    extra += "（PDF，不能改字体）"
                lines.append("  %s  %s%s" % (mark, r["name"], extra))
    failed = [r for r in results if not r["ok"]]
    if failed:
        if lines:
            lines.append("")
        lines.append("【失败】共 %d 个" % len(failed))
        for r in failed:
            lines.append("  ✗  %s（%s）" % (r["name"], r["err"]))
    if not lines:
        lines.append("没有处理任何文件。")

    print("\n".join(lines))
    print("@@TOTAL:%d" % total)


def fix_existing():
    """修复 Kindle 上已有的书：mobi 转 azw3（解锁字体）、封面缺失/过小的补上"""
    if not usb_ok_or_skip():
        print("❌ Kindle 没连上\n\nUSB 上找不到 Kindle，先把设备连好再修复。")
        return

    docs = find_kindle_docs()
    if not docs:
        print("没找到 Kindle。")
        return

    os.makedirs(TMPDIR, exist_ok=True)
    targets = []
    for ext in ("*.mobi", "*.azw", "*.prc", "*.azw3"):
        targets.extend(glob.glob(os.path.join(docs, ext)))

    todo = []
    for f in sorted(targets):
        stem, ext = os.path.splitext(f)
        ext = ext.lower()
        probe = os.path.join(TMPDIR, "_p.jpg")
        has = extract_cover(f, probe)
        w = cover_width(probe) if has else 0
        if os.path.exists(probe):
            os.remove(probe)
        need_font_fix = ext in (".mobi", ".azw", ".prc")
        need_cover_fix = (not has) or (0 < w < COVER_MIN)
        need_type_fix = (cde_type(f) == "EBOK")   # 会被亚马逊换掉封面
        if need_font_fix or need_cover_fix or need_type_fix:
            todo.append((f, need_font_fix, need_cover_fix, w, need_type_fix))

    if not todo:
        print("Kindle 上的书都正常，无需修复。")
        print("@@TOTAL:%d" % len(read_log_entries()))
        return

    print("需要修复 %d 本：" % len(todo))
    for f, nf, nc, w, nt in todo:
        reason = []
        if nf:
            reason.append("老格式不能改字体")
        if nc:
            reason.append("封面缺失/过小(%dpx)" % w)
        if nt:
            reason.append("EBOK 封面会被亚马逊替换")
        print("  · %s —— %s" % (os.path.basename(f), "，".join(reason)))
    print("")

    results = []
    total_n = len(todo)
    for idx, (f, nf, nc, w, nt) in enumerate(todo, 1):
        print("@@PROGRESS:%d/%d|%s" % (idx, total_n, os.path.basename(f)), flush=True)
        stem_f, ext_f = os.path.splitext(f)
        ext_f = ext_f.lower()

        # 已经有同名 azw3 的老格式文件 -> 直接删掉，免得 Kindle 上出现重复的两本
        if ext_f in (".mobi", ".azw", ".prc") and os.path.exists(stem_f + ".azw3"):
            try:
                os.remove(f)
                print("  删除重复的旧格式：%s" % os.path.basename(f), flush=True)
                continue
            except OSError:
                pass

        r = process_file(f, docs, force=nc)   # 只有封面有问题才强制重转
        if r["ok"] and os.path.abspath(f) != os.path.join(docs, r["name"]):
            try:
                os.remove(f)                   # 转换出了新文件，删掉旧的
            except OSError:
                pass
        results.append(r)
        print("  处理完：%s" % os.path.basename(f), flush=True)

    entries = []
    for r in results:
        if r["ok"]:
            entries.append(make_entry(r["name"], r["size"],
                                      r.get("cover", False),
                                      r.get("font", False),
                                      "修复"))
    total = write_log(entries) if entries else len(read_log_entries())
    print("")
    print("修复完成，共 %d 本。" % sum(1 for r in results if r["ok"]))
    print("@@TOTAL:%d" % total)


if __name__ == "__main__":
    args = sys.argv[1:]
    if FIX_EXISTING in args:
        fix_existing()
    else:
        run([a for a in args if not a.startswith("--")])
