#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 design/app_icon.svg 生成 Android / Windows 全套图标。

原理：无头 Edge(Chromium) 把 SVG 渲染成 PNG；由于无头截图不带 alpha，
对同一张图分别铺白底和黑底各渲染一次，再用
    alpha = 1 - (C_white - C_black) / 255
反解出精确的透明度，并在预乘空间做 LANCZOS 缩放，避免白边/黑边。

用法：
    python tool/gen_app_icons.py
    python tool/gen_app_icons.py --edge "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
    python tool/gen_app_icons.py --preview C:\\Temp\\icon_preview

产物：
    android/app/src/main/res/mipmap-*/ic_launcher.png             48 / 72 / 96 / 144 / 192
    android/app/src/main/res/mipmap-*/ic_launcher_background.png  108 / 162 / 216 / 324 / 432
    android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  108 / 162 / 216 / 324 / 432
    android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
    windows/runner/resources/app_icon.ico                         16 / 24 / 32 / 48 / 64 / 128 / 256
    design/app_icon_1024.png                                      预览母版（带 alpha）

依赖：Pillow、numpy（DSH 自带运行时已含）、本机 Edge 或 Chrome。
"""

from __future__ import annotations

import argparse
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SVG_PATH = ROOT / "design" / "app_icon.svg"
RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"
ICO_PATH = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
MASTER_PATH = ROOT / "design" / "app_icon_1024.png"

CANVAS = 1024
GLYPH_SCALE = 1.20  # 自适应前景把主体放到画布约 60%，稳在 72dp 安全区内

# 密度 -> (legacy 尺寸, 自适应图层尺寸)   108dp 基准
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

EDGE_CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
]

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""


# --------------------------------------------------------------------------- #
# SVG 变体
# --------------------------------------------------------------------------- #
def build_variants(svg_text: str) -> dict[str, str]:
    """切出三份 SVG：full（原图）、bg（去主体、满幅无圆角）、fg（只有主体）。"""
    marker = "<!-- 半透明图标主体 -->"
    cut = svg_text.index(marker)
    g_start = svg_text.index('<g filter="url(#floatShadow)"', cut)
    g_end = svg_text.index("</g>", g_start) + len("</g>")

    glyph = svg_text[g_start:g_end]
    defs = svg_text[svg_text.index("<defs>"): svg_text.index("</defs>") + len("</defs>")]

    full = svg_text

    # 背景层：去掉主体，外框改为满幅（rx=224 只出现一次）。
    # 自适应图标会被启动器按圆形/方形遮罩裁切，玻璃卡片和它的描边会切出硬边，
    # 因此背景层只保留底色 + 光斑 + 满幅噪点。
    bg = svg_text[:cut] + svg_text[g_end:]
    bg = bg.replace('rx="224"', 'rx="0"', 1)
    bg = re.sub(r"\n\s*<!-- 毛玻璃卡片 -->.*?fill-opacity=\"0\.30\"/>", "", bg, count=1, flags=re.S)
    bg = re.sub(r"\n\s*<!-- 玻璃边缘高光 -->.*?stroke-width=\"2\.5\"/>", "", bg, count=1, flags=re.S)
    bg = bg.replace('<g clip-path="url(#glassClip)">', "<g>")
    bg = bg.replace(
        '<rect x="112" y="112" width="800" height="800" filter="url(#noise)"/>',
        f'<rect width="{CANVAS}" height="{CANVAS}" filter="url(#noise)"/>',
    )

    # 前景层：只要主体，围绕画布中心放大
    fg = (
        f'<svg width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}"\n'
        '     xmlns="http://www.w3.org/2000/svg">\n'
        f"{defs}\n"
        f'  <g transform="translate({CANVAS / 2} {CANVAS / 2}) scale({GLYPH_SCALE}) '
        f'translate({-CANVAS / 2} {-CANVAS / 2})">\n'
        f"{glyph}\n"
        "  </g>\n"
        "</svg>\n"
    )
    return {"full": full, "bg": bg, "fg": fg}


# --------------------------------------------------------------------------- #
# 无头渲染
# --------------------------------------------------------------------------- #
def find_browser(explicit: str | None) -> Path:
    for cand in ([explicit] if explicit else []) + [os.environ.get("EDGE_PATH")] + EDGE_CANDIDATES:
        if cand and Path(cand).is_file():
            return Path(cand)
    for name in ("msedge", "chrome", "chromium", "google-chrome"):
        found = shutil.which(name)
        if found:
            return Path(found)
    raise SystemExit("找不到 Edge/Chrome，请用 --edge 指定可执行文件路径")


def render_once(browser: Path, workdir: Path, svg_name: str, background: str, out_png: Path) -> np.ndarray:
    """把同目录下的 svg 用指定底色渲染成 CANVAS×CANVAS 的 RGB 数组。"""
    html = workdir / "wrapper.html"
    html.write_text(
        "<!doctype html><html><head><meta charset='utf-8'><style>\n"
        "html,body{margin:0;padding:0;overflow:hidden;width:%dpx;height:%dpx;background:#%s}\n"
        "img{display:block;width:%dpx;height:%dpx}\n"
        "</style></head><body><img src='%s'></body></html>\n"
        % (CANVAS, CANVAS, background, CANVAS, CANVAS, svg_name),
        encoding="utf-8",
    )
    if out_png.exists():
        out_png.unlink()

    cmd = [
        str(browser),
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--virtual-time-budget=3000",
        f"--window-size={CANVAS},{CANVAS}",
        f"--user-data-dir={workdir / 'profile'}",
        f"--screenshot={out_png}",
        html.as_uri(),
    ]
    subprocess.run(cmd, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    deadline = time.time() + 30
    while time.time() < deadline:
        if out_png.exists() and out_png.stat().st_size > 0:
            break
        time.sleep(0.1)
    else:
        raise RuntimeError(f"渲染失败：{out_png} 未生成")

    with Image.open(out_png) as im:
        im.load()
        if im.size != (CANVAS, CANVAS):
            raise RuntimeError(f"渲染尺寸异常：{im.size}（期望 {CANVAS}×{CANVAS}）")
        return np.asarray(im.convert("RGB"), dtype=np.float32) / 255.0


def render_rgba(browser: Path, workdir: Path, name: str, svg_text: str) -> np.ndarray:
    """白底 + 黑底各渲一次，反解出预乘 RGBA（float32, 0..1）。"""
    svg_file = workdir / f"{name}.svg"
    svg_file.write_text(svg_text, encoding="utf-8")

    cw = render_once(browser, workdir, svg_file.name, "FFFFFF", workdir / f"{name}_w.png")
    cb = render_once(browser, workdir, svg_file.name, "000000", workdir / f"{name}_b.png")

    alpha = np.clip(1.0 - (cw - cb).mean(axis=2), 0.0, 1.0)
    # 极低 alpha 处的颜色不可信，直接归零，避免缩放时出现脏点
    alpha[alpha < 2.0 / 255.0] = 0.0
    return np.dstack([cb * alpha[..., None], alpha]).astype(np.float32)


# --------------------------------------------------------------------------- #
# 缩放 / 输出
# --------------------------------------------------------------------------- #
def resize_rgba(premultiplied: np.ndarray, size: int) -> Image.Image:
    """在预乘空间做 LANCZOS 缩放，再还原成直通 alpha 的 RGBA 图。"""
    chans = []
    for i in range(4):
        plane = np.ascontiguousarray(premultiplied[:, :, i], dtype=np.float32)
        im = Image.fromarray(plane, mode="F").resize((size, size), Image.LANCZOS)
        chans.append(np.asarray(im, dtype=np.float32))

    alpha = np.clip(chans[3], 0.0, 1.0)
    safe = np.maximum(alpha, 1e-6)
    rgb = np.dstack([np.clip(chans[i] / safe, 0.0, 1.0) for i in range(3)])
    rgba = np.dstack([rgb, alpha])
    return Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), mode="RGBA")


def save_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


# --------------------------------------------------------------------------- #
# ICO：≤64 用 32bpp BMP，128/256 用 PNG（兼顾老 shell 与 Vista+）
# --------------------------------------------------------------------------- #
def _bmp_entry(img: Image.Image) -> bytes:
    w, h = img.size
    px = np.asarray(img, dtype=np.uint8)
    bgra = np.ascontiguousarray(px[::-1][:, :, [2, 1, 0, 3]])  # 自下而上 + BGRA
    header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, bgra.nbytes, 0, 0, 0, 0)
    row = ((w + 31) // 32) * 4
    mask = b"\x00" * (row * h)  # 32bpp 有 alpha，AND 掩码全 0
    return header + bgra.tobytes() + mask


def _png_entry(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def write_ico(master: Image.Image, path: Path) -> None:
    images = [(s, resize_rgba_from(master, s)) for s in ICO_SIZES]
    blobs = [(s, _png_entry(im) if s >= 128 else _bmp_entry(im)) for s, im in images]

    header = struct.pack("<HHH", 0, 1, len(blobs))
    offset = 6 + 16 * len(blobs)
    entries, payload = b"", b""
    for size, data in blobs:
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
        payload += data
        offset += len(data)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + entries + payload)


def resize_rgba_from(img: Image.Image, size: int) -> Image.Image:
    """把已带 alpha 的图在预乘空间缩放到 size×size。"""
    arr = np.asarray(img, dtype=np.float32) / 255.0
    return resize_rgba(np.dstack([arr[:, :, :3] * arr[:, :, 3:4], arr[:, :, 3]]), size)


# --------------------------------------------------------------------------- #
# 预览：模拟启动器圆形遮罩 + 各尺寸排排站
# --------------------------------------------------------------------------- #
def write_preview(legacy_192: Image.Image, fg_full: Image.Image, bg_full: Image.Image, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    tile = 256
    sheet = Image.new("RGBA", (tile * 2 + 30, tile + 20), (244, 241, 234, 255))

    legacy = legacy_192.resize((tile, tile), Image.LANCZOS)
    sheet.alpha_composite(legacy, (10, 10))

    # 自适应图标：把前景缩到 108dp 画布内并叠在背景上，再套 72dp 圆遮罩
    fg = fg_full.resize((tile, tile), Image.LANCZOS)
    bg = bg_full.resize((tile, tile), Image.LANCZOS)
    adaptive = Image.alpha_composite(bg, fg)
    mask = Image.new("L", (tile * 4, tile * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, tile * 4 - 1, tile * 4 - 1), fill=255)
    mask = mask.resize((tile, tile), Image.LANCZOS)
    circle = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    circle.paste(adaptive, (0, 0), mask)
    sheet.alpha_composite(circle, (tile + 20, 10))

    sheet.convert("RGB").save(out_dir / "preview.png", format="PNG")
    legacy_192.resize((48, 48), Image.LANCZOS).save(out_dir / "preview_48.png", format="PNG")
    print(f"预览：{out_dir / 'preview.png'}")


# --------------------------------------------------------------------------- #
def main() -> None:
    ap = argparse.ArgumentParser(description="生成 recipe_book 的 Android / Windows 图标")
    ap.add_argument("--edge", help="Edge/Chrome 可执行文件路径")
    ap.add_argument("--preview", help="额外输出预览图的目录")
    args = ap.parse_args()

    if not SVG_PATH.is_file():
        raise SystemExit(f"缺少源文件：{SVG_PATH}")

    browser = find_browser(args.edge)
    svg_text = SVG_PATH.read_text(encoding="utf-8")
    variants = build_variants(svg_text)

    with tempfile.TemporaryDirectory(prefix="rb_icons_") as tmp:
        workdir = Path(tmp)
        print(f"渲染引擎：{browser}")
        rendered = {}
        for name in ("full", "bg", "fg"):
            rendered[name] = render_rgba(browser, workdir, name, variants[name])
            print(f"  已渲染 {name}")

    master = resize_rgba(rendered["full"], CANVAS)
    save_png(master, MASTER_PATH)

    rows = []
    for density, (legacy_size, adaptive_size) in DENSITIES.items():
        folder = RES_DIR / f"mipmap-{density}"

        legacy = resize_rgba(rendered["full"], legacy_size)
        save_png(legacy, folder / "ic_launcher.png")
        rows.append((f"mipmap-{density}/ic_launcher.png", legacy.size[0]))

        fg = resize_rgba(rendered["fg"], adaptive_size)
        save_png(fg, folder / "ic_launcher_foreground.png")
        rows.append((f"mipmap-{density}/ic_launcher_foreground.png", fg.size[0]))

        bg = resize_rgba(rendered["bg"], adaptive_size)
        save_png(bg, folder / "ic_launcher_background.png")
        rows.append((f"mipmap-{density}/ic_launcher_background.png", bg.size[0]))

    xml_path = RES_DIR / "mipmap-anydpi-v26" / "ic_launcher.xml"
    xml_path.parent.mkdir(parents=True, exist_ok=True)
    xml_path.write_text(ADAPTIVE_XML, encoding="utf-8", newline="\n")

    write_ico(master, ICO_PATH)

    for rel, size in rows:
        path = RES_DIR / rel
        print(f"  {rel:<44} {size:>4}px  {path.stat().st_size / 1024:7.1f} KiB")
    print(f"  {'mipmap-anydpi-v26/ic_launcher.xml':<44}   adaptive-icon")
    print(f"  {'windows/runner/resources/app_icon.ico':<44} {ICO_PATH.stat().st_size / 1024:7.1f} KiB  "
          f"{','.join(map(str, ICO_SIZES))}")
    print(f"  {'design/app_icon_1024.png':<44} 1024px  {MASTER_PATH.stat().st_size / 1024:7.1f} KiB")

    if args.preview:
        write_preview(
            resize_rgba(rendered["full"], 192),
            resize_rgba(rendered["fg"], 108),
            resize_rgba(rendered["bg"], 108),
            Path(args.preview),
        )


if __name__ == "__main__":
    sys.exit(main())
