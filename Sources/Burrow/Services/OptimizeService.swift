import Foundation

struct MaintenanceTask: Identifiable {
    let id: String
    let name: String
    let detail: String
    let command: String
    let needsAdmin: Bool
    var defaultOn: Bool = true
}

final class OptimizeEngine: ObservableObject {
    @Published var enabled: Set<String>
    @Published var isRunning = false
    @Published var log: [LogLine] = []

    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    let tasks: [MaintenanceTask] = [
        MaintenanceTask(
            id: "quicklook",
            name: "重建 Quick Look 缓存",
            detail: "修复预览空白、缩略图不更新的问题",
            command: "qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1; echo OK",
            needsAdmin: false
        ),
        MaintenanceTask(
            id: "dns",
            name: "刷新 DNS 缓存",
            detail: "解决域名解析异常;使用 VPN 时建议跳过",
            command: "dscacheutil -flushcache; killall -HUP mDNSResponder",
            needsAdmin: true
        ),
        MaintenanceTask(
            id: "launchservices",
            name: "重建 Launch Services 数据库",
            detail: "修复「打开方式」重复项、文件关联错乱",
            command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain user >/dev/null 2>&1; echo OK",
            needsAdmin: false
        ),
        MaintenanceTask(
            id: "dsstore",
            name: "清理 .DS_Store(桌面 / 文稿 / 下载)",
            detail: "移除 Finder 视图配置碎片文件,无副作用",
            command: "find ~/Desktop ~/Documents ~/Downloads -name .DS_Store -delete 2>/dev/null; echo OK",
            needsAdmin: false
        ),
        MaintenanceTask(
            id: "purge",
            name: "释放不活跃内存",
            detail: "运行 purge,强制回收磁盘缓存内存",
            command: "purge",
            needsAdmin: true
        ),
        MaintenanceTask(
            id: "simctl",
            name: "删除不可用的模拟器",
            detail: "移除 Xcode 升级后残留的旧模拟器设备",
            command: "xcrun simctl delete unavailable",
            needsAdmin: false,
            defaultOn: false
        ),
        MaintenanceTask(
            id: "spotlight",
            name: "重建 Spotlight 索引",
            detail: "耗时较长,后台重建期间搜索不完整",
            command: "mdutil -E / >/dev/null 2>&1; echo 已开始重建",
            needsAdmin: true,
            defaultOn: false
        ),
    ]

    init() {
        enabled = Set(tasks.filter(\.defaultOn).map(\.id))
    }

    var hasAdminTask: Bool {
        tasks.contains { enabled.contains($0.id) && $0.needsAdmin }
    }

    func toggle(_ task: MaintenanceTask) {
        if enabled.contains(task.id) { enabled.remove(task.id) } else { enabled.insert(task.id) }
    }

    func run() {
        guard !isRunning else { return }
        let selected = tasks.filter { enabled.contains($0.id) }
        guard !selected.isEmpty else { return }
        isRunning = true
        log = []

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for task in selected {
                await self.append("▶ \(task.name)" + (task.needsAdmin ? "(需要管理员权限)" : ""))
                let start = Date()
                let result = task.needsAdmin
                    ? Shell.runAsAdmin(task.command)
                    : Shell.run(task.command)
                let elapsed = String(format: "%.1fs", Date().timeIntervalSince(start))
                let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.status == 0 {
                    await self.append("  ✓ 完成(\(elapsed))" + (output.isEmpty || output == "OK" ? "" : " \(output)"))
                } else {
                    await self.append("  ✗ 失败:\(output.isEmpty ? "退出码 \(result.status)" : output)", isError: true)
                }
            }
            await self.append("全部任务执行完毕 ✨")
            await MainActor.run { self.isRunning = false }
        }
    }

    @MainActor
    private func append(_ text: String, isError: Bool = false) {
        log.append(LogLine(text: text, isError: isError))
    }
}
