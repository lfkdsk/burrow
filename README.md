# Burrow 🪐

> Mac 原生系统维护工具 — 清理 · 软件 · 优化 · 分析 · 状态
>
> 灵感来自开源项目 [Mole](https://github.com/tw93/mole)(鼹鼠),Burrow 是鼹鼠深挖的洞穴。
> 纯 SwiftUI 实现,无第三方依赖。

## 五大模块(行星主题)

| 模块 | 行星 | 功能 |
|------|------|------|
| 清理 | Earth | 扫描应用缓存、日志、开发者缓存(DerivedData / npm / gradle / cargo)、系统残留、废纸篓;逐项确认后清理,默认移入废纸篓可恢复 |
| 软件 | Mars | 应用卸载:在 15+ 个 Library 目录中检测残留(Application Support、Containers、Preferences、LaunchAgents 等);启动项管理 |
| 优化 | Mercury | 重建 Quick Look / Launch Services / Spotlight、刷新 DNS、释放内存、清理 .DS_Store,带执行日志,需要管理员权限的任务由系统弹窗授权 |
| 分析 | Jupiter | Squarified 树图磁盘可视化,单击钻取目录、面包屑导航、右键 Finder 显示 / 移到废纸篓 |
| 状态 | Sun | 实时监控:CPU(host_processor_info)、内存 / 交换(vm_statistics64)、网络速率(getifaddrs)、磁盘、电池(IOKit,循环次数与健康度)、Top 进程,60 秒走势图 |

另有 **菜单栏 HUD**:常驻显示 CPU 占用,下拉面板展示迷你 bento 指标卡。

## 安全设计

- 清理默认「移到废纸篓」,可随时恢复;仅清空废纸篓为永久删除且默认不勾选、需二次确认
- 关键系统缓存(CloudKit、FileProvider、HomeKit 等)硬编码保护,绝不列出
- 白名单:右键任意扫描条目「加入白名单」,设置窗口可管理
- 应用名残留匹配要求精确,bundle id 匹配要求前缀/包含,避免误伤

## 构建与运行

```bash
# 调试运行
swift run

# 打包 Burrow.app(含图标、ad-hoc 签名)
./scripts/package.sh
open dist/Burrow.app
```

要求 macOS 14+、Xcode 命令行工具。

> 部分目录(如 Safari 容器)受系统隐私保护,如需完整扫描请在
> 「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权 Burrow。

## 签名与发布

`scripts/package.sh` 自动检测钥匙串中的 **Developer ID Application** 证书:找到则以
hardened runtime + timestamp 真实签名,否则回退 ad-hoc(可用 `SIGN_IDENTITY` 环境变量指定身份)。

**CI / CD**(`.github/workflows/build.yml`):push 到 `main` 自动构建打包并上传产物;
推送 `v*` tag 自动创建 GitHub Release。要让 CI 使用真实签名与公证,配置以下 Secrets(均可选,缺省时 CI 用 ad-hoc 签名照常跑通):

```bash
# 1. 从钥匙串导出 Developer ID 证书(本机执行,会提示设置导出密码)
#    钥匙串访问.app → 我的证书 → Developer ID Application → 导出为 cert.p12
base64 -i cert.p12 | gh secret set DEVELOPER_ID_P12_BASE64
gh secret set DEVELOPER_ID_P12_PASSWORD   # 输入导出密码

# 2a. 公证方式一(推荐):App Store Connect API Key
#     App Store Connect → 用户和访问 → 集成 → 创建 API 密钥(.p8 只能下载一次)
gh secret set APPLE_API_KEY      # Key ID,10 位字母数字
gh secret set APPLE_API_ISSUER   # Issuer ID(UUID,页面顶部)
gh secret set APPLE_API_KEY_P8 < AuthKey_XXXXXXXXXX.p8

# 2b. 公证方式二(后备):Apple ID + App 专用密码(appleid.apple.com 生成)
gh secret set NOTARY_APPLE_ID NOTARY_TEAM_ID NOTARY_PASSWORD  # 逐个设置

# 3. 发版
git tag v1.0.0 && git push origin v1.0.0
```

## 项目结构

```
Sources/Burrow/
├── BurrowApp.swift          # App 入口:主窗口 + MenuBarExtra + Settings
├── Theme.swift              # 模块/行星定义、bento 卡片样式
├── Services/
│   ├── DiskUtils.swift      # 磁盘大小计算、废纸篓、Shell(含管理员授权)、白名单
│   ├── CleanService.swift   # 清理扫描引擎(5 类目标)
│   ├── UninstallService.swift # 应用列表、残留检测、启动项
│   ├── OptimizeService.swift  # 7 项维护任务
│   ├── AnalyzeService.swift   # 文件树扫描 + squarified treemap 布局
│   └── StatusMonitor.swift    # mach / sysctl / IOKit 系统采样
└── Views/                   # 各模块 SwiftUI 视图 + 行星动画
```
