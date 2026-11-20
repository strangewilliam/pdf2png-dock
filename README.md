# PDF2PNG Dock

一个常驻 macOS 菜单栏的小工具：把 **PDF 或图片拖到菜单栏图标上**，即可转换为 PNG、自动去掉白边，并保存到桌面。像 Seafile 的菜单栏图标一样安静地待在顶部，不占 Dock。

## 功能

- 拖放 PDF / PNG / JPG / TIFF / BMP 到菜单栏图标，批量处理
- PDF 每一页生成一张 PNG（2x 分辨率，带 alpha）
- 自动裁掉图像四周的纯白边（`PAD_RATIO` 可调留边比例）
- 点击图标可弹出菜单：选择文件、设置登录时启动、查看说明、退出
- 处理完成显示系统通知

## 依赖

需要 Python 3 及两个库：

```bash
pip install pymupdf pillow
```

App 会自动探测本机装有这两个库的 Python（依次尝试环境变量 `PDF2PNG_PYTHON`、`/opt/anaconda3/bin/python`、`/usr/local/bin/python3`、`/opt/homebrew/bin/python3`、`/usr/bin/python3`）。如需指定，可执行：

```bash
launchctl setenv PDF2PNG_PYTHON /path/to/python
```

## 安装

```bash
./build.sh
```

构建产物在 `~/Applications/PDF2PNG Dock.app`，首次使用请打开它。菜单中的「登录时启动」可让它开机自动运行。

## 自定义

- 去白边留白比例：编辑 `pdf2png.py` 顶部的 `PAD_RATIO`（默认 `0`，即完全去除；设为 `0.005` 可保留少量白边）
- 指定处理脚本：设置环境变量 `PDF2PNG_SCRIPT`（默认使用 App 内置脚本）
- 重新生成图标：`python3 make_icon.py`，会输出 `AppIcon.icns`

## 组成

| 文件 | 说明 |
| --- | --- |
| `main.swift` | 菜单栏 App：拖放接收、菜单、通知、登录自启 |
| `pdf2png.py` | 转换与去白边逻辑，同时支持命令行调用 |
| `make_icon.py` | 生成 App 图标的脚本 |
| `AppIcon.icns` | 应用图标 |
| `Info.plist` | App 配置 |
| `build.sh` | 编译并安装到 `~/Applications` |

## 命令行单独使用

用装有 PyMuPDF 与 Pillow 的那个 Python 解释器运行：

```bash
python3 pdf2png.py 文件1.pdf 文件2.png
# 例如本机：/opt/anaconda3/bin/python pdf2png.py 文件1.pdf
```

## License

MIT
