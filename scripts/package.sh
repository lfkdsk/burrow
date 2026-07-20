#!/bin/bash
# 构建并打包 Burrow.app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

APP="dist/Burrow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Burrow "$APP/Contents/MacOS/Burrow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SPM 资源包(行星贴图),Bundle.module 会在 Contents/Resources 下查找
if [ -d .build/release/Burrow_Burrow.bundle ]; then
  cp -R .build/release/Burrow_Burrow.bundle "$APP/Contents/Resources/"
fi

# 图标:优先使用 SceneKit 渲染的 3D 图标(scripts/render_icon.swift),
# 不存在时回退到 SVG 平面图标
echo "==> 生成图标"
mkdir -p dist
ICON_SRC=""
if [ -f Resources/AppIcon3D.png ]; then
  ICON_SRC=Resources/AppIcon3D.png
else
  qlmanage -t -s 1024 -o dist Resources/AppIcon.svg >/dev/null 2>&1 || true
  [ -f dist/AppIcon.svg.png ] && ICON_SRC=dist/AppIcon.svg.png
fi
if [ -n "$ICON_SRC" ]; then
  ICONSET=dist/AppIcon.iconset
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    dbl=$((size * 2))
    sips -z $dbl $dbl "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o dist/AppIcon.icns
  rm -rf "$ICONSET" dist/AppIcon.svg.png
fi
[ -f dist/AppIcon.icns ] && cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 签名:优先 Developer ID(可用 SIGN_IDENTITY 环境变量覆盖),否则回退 ad-hoc
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
fi
if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> codesign ($SIGN_IDENTITY)"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  echo "==> codesign (ad-hoc)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP" && echo "==> 签名校验通过"

echo "==> 完成:$APP"
