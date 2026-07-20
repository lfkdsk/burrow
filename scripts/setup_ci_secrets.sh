#!/bin/bash
# 交互式配置 CI 签名与公证 Secrets。
# 所有密码均由本终端隐藏输入直传 GitHub,不落盘、不出现在命令行参数中。
set -euo pipefail

REPO=${1:-lfkdsk/burrow}
P12=${2:-$HOME/Desktop/cert.p12}

if [ ! -f "$P12" ]; then
  echo "未找到 $P12"
  echo "请先在「钥匙串访问」→ 我的证书 → 右键 Developer ID Application 证书"
  echo "→ 导出为 $P12(设置一个新的导出密码)"
  open -a "Keychain Access" 2>/dev/null || true
  exit 1
fi

echo "==> 上传证书(base64)"
base64 -i "$P12" | gh secret set DEVELOPER_ID_P12_BASE64 --repo "$REPO"

echo "==> 粘贴/输入证书导出密码:"
gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO"

echo "==> 输入开发者账号的 Apple ID 邮箱:"
gh secret set NOTARY_APPLE_ID --repo "$REPO"

echo "==> 输入 App 专用密码(account.apple.com → 登录与安全 → App 专用密码):"
gh secret set NOTARY_PASSWORD --repo "$REPO"

gh secret set NOTARY_TEAM_ID --repo "$REPO" --body R6QM7B7GB7

echo "==> 删除本地证书文件"
rm -f "$P12"

echo ""
echo "✓ 全部配置完成!发一个真签 + 公证的版本:"
echo "  git tag v1.0.1 && git push origin v1.0.1"
