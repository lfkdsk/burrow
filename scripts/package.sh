#!/bin/bash
# 构建并打包 Burrow.app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

APP="dist/Burrow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/Burrow "$APP/Contents/MacOS/Burrow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SPM 资源包(行星贴图),Bundle.module 会在 Contents/Resources 下查找
if [ -d .build/release/Burrow_Burrow.bundle ]; then
  cp -R .build/release/Burrow_Burrow.bundle "$APP/Contents/Resources/"
fi

# Sparkle 自动更新框架:SPM 会把 Sparkle.framework 拷进构建产物目录
# (.build/release),本地与 CI 一致;兜底再从 xcframework artifact 定位。
echo "==> 嵌入 Sparkle.framework"
SPARKLE_FW=".build/release/Sparkle.framework"
if [ ! -d "$SPARKLE_FW" ]; then
  SPARKLE_FW=$(find .build -type d \
    -path '*Sparkle.xcframework/macos-*/Sparkle.framework' 2>/dev/null | head -1)
fi
if [ -z "$SPARKLE_FW" ] || [ ! -d "$SPARKLE_FW" ]; then
  echo "!! 未找到 Sparkle.framework,请先执行 swift build 拉取依赖" >&2
  exit 1
fi
# ditto 保留 Versions/B、Current 符号链接、Autoupdate、Updater.app、XPCServices 结构
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
# 让主可执行文件能通过 @rpath 找到嵌入的框架
# (Sparkle dylib 的 install name 为 @rpath/Sparkle.framework/Versions/B/Sparkle)
install_name_tool -add_rpath @executable_path/../Frameworks \
  "$APP/Contents/MacOS/Burrow" 2>/dev/null || true

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

# 统一签名封装:Developer ID 带 hardened runtime + timestamp,否则 ad-hoc
sign() {
  if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"
  else
    codesign --force --sign - "$1"
  fi
}

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> codesign ($SIGN_IDENTITY)"
else
  echo "==> codesign (ad-hoc)"
fi

# 由内向外签名:先签 Sparkle 内嵌的辅助程序/服务,再签框架,最后整包
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  for xpc in "$FW/Versions/B/XPCServices/"*.xpc; do
    [ -e "$xpc" ] && sign "$xpc"
  done
  [ -e "$FW/Versions/B/Autoupdate" ] && sign "$FW/Versions/B/Autoupdate"
  [ -e "$FW/Versions/B/Updater.app" ] && sign "$FW/Versions/B/Updater.app"
  sign "$FW"
fi
sign "$APP"

codesign --verify --deep --strict "$APP" && echo "==> 签名校验通过"

echo "==> 完成:$APP"
