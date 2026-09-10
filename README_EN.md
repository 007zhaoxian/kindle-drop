# Kindle Drop

> Drag a book onto the floating box. That's it — format conversion, cover repair and
> transfer to your Kindle all happen automatically.

[![Release](https://img.shields.io/github/v/release/007zhaoxian/kindle-drop?label=download&color=blue)](../../releases/latest)
[![Build](https://img.shields.io/github/actions/workflow/status/007zhaoxian/kindle-drop/build.yml?label=build)](../../actions)
[![License](https://img.shields.io/github/license/007zhaoxian/kindle-drop?label=license&color=green)](LICENSE)

![preview](docs/preview.png)

*[中文说明请点这里 →](README.md)*

Sideloading books to a Kindle from a Mac is a minefield: Finder can't see the device at all,
everything you copy over shows up with a blank cover, `mobi` files refuse to change fonts on
the Kindle, and Calibre happily writes books into a folder the Kindle never reads.
This little tool takes care of all of it.

---

## What it does

| Step | Detail |
|---|---|
| **Format** | `epub / doc / docx / html / rtf / fb2 / mobi / azw / prc` → converted to **azw3**; `azw3 / kfx / pdf / txt` copied as-is |
| **Cover** | Extract → normalize to 800px (the Kindle ignores tiny thumbnails) → force-embed → re-tag as a **personal document** so Amazon stops replacing it |
| **Fonts** | Strip `font-family` locks from the CSS so the Kindle's Aa menu actually works |
| **Right folder** | Writes only into `documents/`, which is the only folder the Kindle reads |
| **Real verification** | Polls until the file truly lands on disk, and checks the device is physically connected first — **no fake "success"** |
| **Log** | `~/Desktop/传到Kindle日志.txt`, newest first, with cover/font status per book |

---

## Requirements

| | |
|---|---|
| **macOS 13+** | Universal binary (Apple Silicon + Intel) |
| **MacDroid** | Mounts the Kindle as a filesystem. Kindles from 2024 onward speak **MTP**, which macOS does not support natively — this is required |
| **Calibre** | Does the actual conversion. Looks in `/Applications/calibre.app` by default; override with `KINDLE_CALIBRE_DIR` |
| **Xcode Command Line Tools** | Only needed when building from source (`swiftc`, `/usr/bin/python3`) |

> MacDroid is commercial software; writing *to* the device is documented as a Pro feature.
> The app doesn't check your license — just try it.

---

## Install

**Download:** grab `KindleDrop-v2.1.zip` from [Releases](../../releases), unzip, drag
`传到Kindle.app` into `/Applications`.

The app is ad-hoc signed (no paid Apple certificate), so Gatekeeper will complain the first time:

```bash
xattr -dr com.apple.quarantine /Applications/传到Kindle.app
```

**Or build it yourself:**

```bash
git clone https://github.com/007zhaoxian/kindle-drop.git
cd kindle-drop
bash build.sh            # → dist/传到Kindle.app
bash build.sh --zip      # also produce a release zip
bash build.sh --install  # install into /Applications
```

Only Xcode Command Line Tools are required — **no full Xcode**.

---

## Usage

1. Plug in the Kindle, **wake and unlock it**, and connect it in MacDroid using **MTP** mode
2. Double-click **传到Kindle.app** — a floating dashed box appears
3. **Drag books onto it**
4. A progress bar shows what's happening; it finishes with "✓ 已传 N 本到 Kindle"
5. Disconnect the Kindle — it rescans and your books show up

The box always floats above other windows, can be dragged anywhere (position is remembered),
and doesn't take a Dock icon.

**Right-click menu:** open the log · repair books already on the Kindle · (re)start MacDroid ·
toggle "delay MacDroid launch until the device settles" · quit.

---

## How it works (the interesting parts)

**1. Why sideloaded books have no cover.**
Calibre writes `EXTH 501 (CDE Type) = EBOK` plus a randomly generated fake `ASIN`. When the
Kindle goes online it asks Amazon for the cover of that ASIN, gets nothing, and swaps in a
"no image" placeholder. Books from the store have real ASINs, which is why only sideloaded
books break. The fix is to re-tag the file as **`PDOC`** (personal document) — Amazon doesn't
validate those, so the Kindle just reads the embedded cover. `EBOK` and `PDOC` are both 4 bytes,
so it's an in-place patch.

> Calibre's own `--share-not-sync` option *deletes* the 501 record, which leaves you with a
> title-only placeholder. Not useful.

*Subtlety:* Calibre embeds the cover thumbnail in the MOBI header, which can push the EXTH
record past **14 KB**. Code that blindly reads the first 8 KB silently fails to find it — so
this reads progressively (64 KB, doubling, up to 8 MB).

**2. Why `mobi` can't change fonts.**
`mobi`/`azw`/`prc` are **KF7** — the Kindle simply doesn't offer font switching for them.
Converting to **azw3 (KF8)** fixes it. On top of that, hard-coded `font-family` rules in the
book's CSS also block the Aa menu, hence `--filter-css=font-family`.
(PDF is fixed-layout and can never change fonts.)

**3. Why writes "succeed" without reaching the device.**
MacDroid uses macOS **File Provider**. After the device is unplugged, the mount path still
exists and still accepts reads, writes and deletes — all served from a local cache. Writing
2000 bytes and reading it back looks perfectly successful while the device is gone. Since the
File Provider API exposes no connection state, this checks the **USB bus** for an Amazon device
(Vendor ID `6473`) instead.

**4. Why the Kindle flashes "connected" and jumps back to the library.**
From MacDroid's own log:

```
PTP_ERROR_IO: failed to open session        ← first MTP session attempt fails
LIBMTP libusb: Attempt to reset device      ← so it force-resets the USB device
libusb left  →  libusb arrived              ← the Kindle is ejected and re-enumerated
mounted disk ... via FileProvider           ← second attempt succeeds
```

That forced USB reset is what throws the Kindle back to the library. MacDroid grabs the device
the instant it appears, before the Kindle has finished switching USB modes. Letting the device
sit idle for a few seconds makes it succeed on the first try, with zero resets.

So the app manages MacDroid's lifecycle: it stays out of the way when no Kindle is attached,
and launches it **4 seconds after** you plug one in. (Toggleable from the right-click menu.)

**5. Two smaller traps.** On a File Provider path, `move` fakes success (it copies but doesn't
delete the source), so everything uses `copy2`. And freshly written files can be invisible for
a moment, so writes are polled until confirmed.

---

## Troubleshooting

- **"Unidentified developer"** → `xattr -dr com.apple.quarantine /Applications/传到Kindle.app`
- **Box stays red with "Kindle 没连上"** → Kindle must be awake and unlocked; use a real data
  cable (many are charge-only); connect directly, not through a hub; make sure MacDroid shows
  the device
- **Books don't appear on the Kindle** → disconnect/plug the cable so it rescans `documents/`.
  Still nothing? Hold the power button for 40 seconds to force a reboot
- **Covers still missing** → covers are generated when the Kindle indexes. Reconnect, or force a
  reboot. For books already on the device, use "repair books already on the Kindle" in the
  right-click menu
- **macOS asks to control MacDroid** → that's the fallback mount call; allow it

---

## CLI only

`src/kindle_send.py` is the whole engine and works standalone:

```bash
python3 src/kindle_send.py ~/books/some-book.epub
python3 src/kindle_send.py --fix-existing
```

| Env var | Purpose | Default |
|---|---|---|
| `KINDLE_CALIBRE_DIR` | Calibre CLI directory | `/Applications/calibre.app/Contents/MacOS` |
| `KINDLE_DOCS` | The Kindle `documents` folder | auto-detected under `~/Library/CloudStorage/MacDroid-*` |
| `KINDLE_LOG_PATH` | Log file path | `~/Desktop/传到Kindle日志.txt` |
| `KINDLE_SKIP_USB_CHECK` | `1` to skip the USB check (debug) | off |

Point `KINDLE_DOCS` at your mountpoint if you use something other than MacDroid (e.g. `simple-mtpfs`).

---

## Limitations

- Tightly coupled to **MacDroid** by default (override with `KINDLE_DOCS`)
- **No DRM support** — unencrypted books only
- PDF can never change fonts
- Not a library manager: no series/author renaming, no metadata downloading
- The Kindle must be awake and unlocked while transferring
- The delayed-launch fix only applies while this app is running

---

## Disclaimer

This tool moves **your own** ebooks onto **your own** Kindle. It does not break DRM or bypass
any protection. Please respect copyright law in your jurisdiction.

Not affiliated with Amazon, Calibre or MacDroid.

## License

[MIT](LICENSE)
