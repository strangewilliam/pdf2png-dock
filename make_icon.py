#!/opt/anaconda3/bin/python
"""生成 PDF2PNG Dock 的应用图标（AppIcon.icns）。

用 Pillow 在 1024x1024 画布上绘制，再缩放成 macOS iconset 的各尺寸，
最后调用 iconutil 打包成 .icns。可重复运行。
"""
import os
import subprocess
import shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))

# ---- 配色 ----
BG_TOP = (58, 122, 255)      # 蓝色渐变上
BG_BOTTOM = (36, 78, 208)    # 蓝色渐变下
PAPER = (255, 255, 255)
INK = (60, 72, 96)
ACCENT = (255, 159, 67)      # 橙色裁剪角
ARROW = (255, 255, 255)


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    path = next((p for p in candidates if os.path.exists(p)), None)
    return ImageFont.truetype(path, size) if path else ImageFont.load_default()


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def draw_master(size=1024):
    """绘制 1024x1024 主图。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 圆角背景 + 垂直渐变
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = bg.load()
    for y in range(size):
        t = y / (size - 1)
        r = int(BG_TOP[0] * (1 - t) + BG_BOTTOM[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOTTOM[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOTTOM[2] * t)
        for x in range(size):
            px[x, y] = (r, g, b, 255)
    corner = int(size * 0.22)
    img.paste(bg, (0, 0), rounded_mask((size, size), corner))

    d = ImageDraw.Draw(img)

    # 纸张本体（带轻微阴影）
    pw, ph = int(size * 0.46), int(size * 0.56)
    px0 = (size - pw) // 2
    py0 = int(size * 0.17)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        [px0 + 10, py0 + 14, px0 + pw + 10, py0 + ph + 14],
        radius=int(size * 0.035), fill=(0, 0, 0, 90),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(size * 0.03)))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [px0, py0, px0 + pw, py0 + ph],
        radius=int(size * 0.035), fill=PAPER,
    )

    # 纸张上的文本行
    f = font(int(size * 0.062))
    line_x = px0 + int(pw * 0.16)
    text_y = py0 + int(ph * 0.20)
    d.text((line_x, text_y), "PDF", font=font(int(size * 0.11), bold=True), fill=(232, 76, 61))
    for i in range(4):
        y = text_y + int(size * 0.115) + i * int(size * 0.072)
        width = int(pw * (0.62 if i % 2 == 0 else 0.46))
        d.rounded_rectangle([line_x, y, line_x + width, y + int(size * 0.022)],
                            radius=int(size * 0.011), fill=(205, 212, 225))

    # 橙色裁剪角标（去白边的视觉隐喻）：四个 L 形角
    m = int(size * 0.05)  # 裁剪框相对纸张的外扩
    cx0, cy0 = px0 - m, py0 - m
    cx1, cy1 = px0 + pw + m, py0 + ph + m
    arm = int(size * 0.055)
    w = max(6, int(size * 0.016))
    # 左上
    d.line([cx0, cy0 + arm, cx0, cy0, cx0 + arm, cy0], fill=ACCENT, width=w, joint="curve")
    # 右上
    d.line([cx1 - arm, cy0, cx1, cy0, cx1, cy0 + arm], fill=ACCENT, width=w, joint="curve")
    # 左下
    d.line([cx0, cy1 - arm, cx0, cy1, cx0 + arm, cy1], fill=ACCENT, width=w, joint="curve")
    # 右下
    d.line([cx1 - arm, cy1, cx1, cy1, cx1, cy1 - arm], fill=ACCENT, width=w, joint="curve")

    # 底部向下箭头（导出到 PNG），锚定在画布底部安全区内
    ax = size // 2
    ay1 = int(size * 0.90)
    ay0 = ay1 - int(size * 0.105)
    half = int(size * 0.032)
    d.line([ax, ay0, ax, ay1 - half], fill=ARROW, width=int(size * 0.026))
    d.polygon([(ax - half, ay1 - half), (ax + half, ay1 - half), (ax, ay1)], fill=ARROW)

    return img


def build_icns():
    master = draw_master(1024)
    iconset = os.path.join(HERE, "AppIcon.iconset")
    if os.path.exists(iconset):
        shutil.rmtree(iconset)
    os.makedirs(iconset)

    spec = [
        (16, 1), (16, 2), (32, 1), (32, 2),
        (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
    ]
    for base, scale in spec:
        s = base * scale
        resized = master.resize((s, s), Image.LANCZOS)
        suffix = "" if scale == 1 else "@2x"
        resized.save(os.path.join(iconset, f"icon_{base}x{base}{suffix}.png"))

    out = os.path.join(HERE, "AppIcon.icns")
    if os.path.exists(out):
        os.remove(out)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
    shutil.rmtree(iconset)
    print(f"图标已生成: {out}")


if __name__ == "__main__":
    build_icns()
