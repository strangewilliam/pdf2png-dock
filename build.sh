#!/bin/zsh
set -e

SRC="${0:A:h}"
APP="$HOME/Applications/PDF2PNG Dock.app"

# 先退出正在运行的旧版本，避免文件占用
pkill -f "$APP/Contents/MacOS/pdf2pngdock" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
cp "$SRC/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$SRC/pdf2png.py" "$APP/Contents/Resources/pdf2png.py"

swiftc -O "$SRC/main.swift" -o "$APP/Contents/MacOS/pdf2pngdock"

echo "已生成: $APP"
