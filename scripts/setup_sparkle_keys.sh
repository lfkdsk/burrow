#!/bin/bash
# 一次性:生成 Sparkle 更新签名用的 EdDSA 密钥对。
#
#   · 私钥存入 macOS 登录钥匙串(供本机手动 sign_update 签名用)
#   · 打印公钥片段 —— 填入 Resources/Info.plist 的 SUPublicEDKey
#   · 导出私钥到 sparkle_private_key.txt —— 设为 GitHub secret SPARKLE_ED_PRIVATE_KEY(供 CI 签名 appcast)
#
# 密钥只需生成一次:同一把私钥可用于任意数量的 App 与后续所有版本。
# 若钥匙串中已有密钥,本脚本会复用而不覆盖。
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.4"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> 获取 Sparkle 工具(${SPARKLE_VERSION};SPM 二进制包不含 generate_keys,需取发行版)"
curl -fsSL -o "$WORK/sparkle.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
tar -xf "$WORK/sparkle.tar.xz" -C "$WORK"
GEN="$WORK/bin/generate_keys"
[ -x "$GEN" ] || { echo "!! 未找到 generate_keys" >&2; exit 1; }

echo
echo "======================================================================"
echo " 步骤 A:生成/读取签名密钥,并打印应填入 Info.plist 的公钥"
echo "         (新建密钥时钥匙串会弹窗请求授权,请点『允许』)"
echo "----------------------------------------------------------------------"
"$GEN"
echo "----------------------------------------------------------------------"
echo " 把上面 <key>SUPublicEDKey</key> 对应的 <string> 值,替换到"
echo " Resources/Info.plist 中 SUPublicEDKey 的占位符 REPLACE_WITH_SPARKLE_ED_PUBLIC_KEY"
echo

KEYOUT="$PWD/sparkle_private_key.txt"
echo "==> 步骤 B:导出私钥到 $KEYOUT(已在 .gitignore 中)"
"$GEN" -x "$KEYOUT"
chmod 600 "$KEYOUT"

echo
echo "======================================================================"
echo " 接下来的一次性配置:"
echo
echo " 1) 把私钥设为 GitHub secret(供 CI 签名 appcast),然后删除本地文件:"
echo "      gh secret set SPARKLE_ED_PRIVATE_KEY < \"$KEYOUT\""
echo "      rm \"$KEYOUT\""
echo
echo " 2) 把仓库设为公开(appcast 与更新包都由本仓库托管;"
echo "    先自查 git 历史无误提交的密钥/凭据):"
echo "      gh repo edit lfkdsk/burrow --visibility public"
echo
echo " 完成后,改版本号 → 打 v* tag → push,CI 自动发布并更新 appcast。"
echo "======================================================================"
