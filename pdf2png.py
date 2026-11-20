#!/usr/bin/env python3
"""PDF/图片 -> PNG（自动去白边）。

两种用法：
  1) 直接运行（无参数）：打开拖放窗口，把 PDF/图片拖进去即可处理。
  2) 命令行：pdf2png.py 文件1 文件2 ... —— 供菜单栏小组件调用，
     处理结果打印到标准输出，PNG 保存到桌面。
"""
import os
import sys
import fitz  # pip install pymupdf
import tkinter as tk
from tkinterdnd2 import DND_FILES, TkinterDnD  # pip install tkinterdnd2
from PIL import Image  # pip install pillow

DESKTOP = os.path.join(os.path.expanduser("~"), "Desktop")
PAD_RATIO = 0  # 白边占原图的比例，默认 0（完全去除）；如需留边可改为 0.005


def save_with_unique_name(image, output_path):
    base, ext = os.path.splitext(output_path)
    counter = 1
    candidate = output_path
    while os.path.exists(candidate):
        candidate = f"{base} ({counter}){ext}"
        counter += 1
    image.save(candidate)
    return candidate


def trim_white_border_from_pil(image: Image.Image, pad_ratio=PAD_RATIO):
    img = image.convert("RGBA")
    pixels = img.load()
    left, right = img.width, 0
    top, bottom = img.height, 0
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = pixels[x, y]
            if not (r == 255 and g == 255 and b == 255 and a == 255):
                if x < left: left = x
                if x > right: right = x
                if y < top: top = y
                if y > bottom: bottom = y
    if right < left or bottom < top:
        return img
    new_left = max(0, left - round(img.width * pad_ratio))
    new_right = min(img.width, right + round(img.width * pad_ratio))
    new_top = max(0, top - round(img.height * pad_ratio))
    new_bottom = min(img.height, bottom + round(img.height * pad_ratio))
    return img.crop((new_left, new_top, new_right, new_bottom))


def pdf_page_to_pil(pdf_path, page_no, zoom=2.0):
    doc = fitz.open(pdf_path)
    page = doc.load_page(page_no)
    mat = fitz.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat, alpha=True)
    mode = "RGBA" if pix.alpha else "RGB"
    img = Image.frombytes(mode, [pix.width, pix.height], pix.samples)
    doc.close()
    return img


def image_file_to_pil(image_path):
    return Image.open(image_path)


def process_file(file_path, desktop=DESKTOP, pad_ratio=PAD_RATIO):
    name, ext = os.path.splitext(os.path.basename(file_path))
    ext_lower = ext.lower()
    if ext_lower == ".pdf":
        try:
            doc = fitz.open(file_path)
            page_count = doc.page_count
            doc.close()
        except Exception as e:
            print(f"打开 PDF 失败: {file_path} -> {e}")
            return
        for i in range(page_count):
            try:
                pil = pdf_page_to_pil(file_path, i, zoom=2.0)
                trimmed = trim_white_border_from_pil(pil, pad_ratio)
                out_name = f"{name}_page_{i+1}.png"
                out_path = os.path.join(desktop, out_name)
                saved = save_with_unique_name(trimmed, out_path)
                print(f"保存: {saved}")
            except Exception as e:
                print(f"渲染/保存 PDF 页失败: {file_path} page {i+1} -> {e}")
    elif ext_lower in [".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp"]:
        try:
            pil = image_file_to_pil(file_path)
            trimmed = trim_white_border_from_pil(pil)
            out_path = os.path.join(desktop, os.path.basename(file_path))
            saved = save_with_unique_name(trimmed, out_path)
            print(f"保存: {saved}")
        except Exception as e:
            print(f"处理图片失败: {file_path} -> {e}")
    else:
        print(f"不支持的文件类型: {file_path}")


def process_paths(paths):
    """处理一批路径，供 GUI 拖放与命令行共用。"""
    for file_path in paths:
        if not os.path.exists(file_path):
            print(f"文件不存在: {file_path}")
            continue
        process_file(file_path, DESKTOP, PAD_RATIO)


def run_cli(paths):
    """命令行模式：处理文件后打印摘要行，供菜单栏 App 判断结果。"""
    if not paths:
        print("未提供文件")
        return
    process_paths(paths)
    print("__DONE__")


def run_gui():
    """图形界面模式：拖放窗口。"""
    root = TkinterDnD.Tk()
    root.title("PDF->PNG 并去白边（支持多文件拖放）")
    root.geometry("520x220")
    label = tk.Label(root, text="拖放 PDF 或 图片 到这里（支持一次多个文件）", font=("Helvetica", 14))
    label.pack(pady=40)

    def drop(event):
        # 使用 Tcl/Tk 的 splitlist 来稳健解析拖放路径（可处理含空格的路径）
        try:
            file_paths = root.tk.splitlist(event.data)
        except Exception:
            file_paths = event.data.strip('{}').split('} {')
        processed_paths = []
        for p in file_paths:
            p = p.strip('{}').strip()
            if p:
                processed_paths.append(p)
        print(f"拖放的文件路径: {processed_paths}")
        process_paths(processed_paths)
        label.config(text="处理完成，已保存到桌面（查看控制台输出）")

    root.drop_target_register(DND_FILES)
    root.dnd_bind('<<Drop>>', drop)

    # 如果在 notebook 中运行，避免阻塞 kernel：以普通方式运行主循环（在终端运行脚本请直接运行）
    try:
        root.mainloop()
    except Exception as e:
        print(f"GUI 运行异常: {e}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_cli(sys.argv[1:])
    else:
        run_gui()
