import Foundation
import AppKit

// MARK: - 模型

struct AppInfo: Identifiable, Hashable {
    let id: String // bundle path
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    var size: Int64 = -1 // -1 = 未计算

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ResidueItem: Identifiable {
    let id = UUID()
    let kind: String
    let url: URL
    let size: Int64
    var isSelected: Bool = true
}

struct LaunchItem: Identifiable {
    let id = UUID()
    let label: String
    let url: URL
    let kind: Kind

    enum Kind: String {
        case userAgent = "用户启动代理"
        case globalAgent = "全局启动代理"
        case daemon = "启动守护进程"
    }

    var editable: Bool { kind == .userAgent }
}

// MARK: - 引擎

final class UninstallEngine: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var isLoadingApps = false
    @Published var selectedApp: AppInfo?
    @Published var residues: [ResidueItem] = []
    @Published var isScanningResidues = false
    @Published var includeAppBundle = true
    @Published var resultMessage: String?

    @Published var launchItems: [LaunchItem] = []

    // MARK: 应用列表

    func loadApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var found: [AppInfo] = []
            let dirs = [
                URL(fileURLWithPath: "/Applications"),
                DiskUtils.home.appendingPathComponent("Applications"),
            ]
            for dir in dirs {
                for child in DiskUtils.children(of: dir) where child.pathExtension == "app" {
                    let bundle = Bundle(url: child)
                    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? child.deletingPathExtension().lastPathComponent
                    let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    found.append(AppInfo(id: child.path, url: child, name: name,
                                         bundleID: bundle?.bundleIdentifier, version: version))
                }
            }
            found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let apps = found
            await MainActor.run {
                self.apps = apps
                self.isLoadingApps = false
            }
            // 后台补齐大小
            for app in apps {
                let size = DiskUtils.allocatedSize(of: app.url)
                await MainActor.run {
                    if let idx = self.apps.firstIndex(of: app) {
                        self.apps[idx].size = size
                    }
                }
            }
        }
    }

    // MARK: 残留扫描

    func scanResidues(for app: AppInfo) {
        selectedApp = app
        residues = []
        resultMessage = nil
        includeAppBundle = true
        isScanningResidues = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let items = Self.findResidues(app: app)
            await MainActor.run {
                self.residues = items
                self.isScanningResidues = false
            }
        }
    }

    /// 在 15+ 个 Library 目录中查找与应用相关的残留
    static func findResidues(app: AppInfo) -> [ResidueItem] {
        let home = DiskUtils.home
        let lib = home.appendingPathComponent("Library")
        var results: [ResidueItem] = []
        let bundleID = app.bundleID?.lowercased()
        let appName = app.name.lowercased()

        // 目录型残留:子项名精确等于应用名,或包含 bundle id
        let dirKinds: [(String, String)] = [
            ("Application Support", "应用支持文件"),
            ("Caches", "缓存"),
            ("Logs", "日志"),
            ("Saved Application State", "窗口状态"),
            ("WebKit", "WebKit 存储"),
            ("HTTPStorages", "HTTP 存储"),
            ("Cookies", "Cookies"),
            ("Containers", "沙盒容器"),
            ("Group Containers", "共享容器"),
            ("Application Scripts", "应用脚本"),
            ("Internet Plug-Ins", "网络插件"),
            ("PreferencePanes", "偏好设置面板"),
        ]

        func matches(_ name: String) -> Bool {
            let lower = name.lowercased()
            if let bundleID, lower.contains(bundleID) { return true }
            // 应用名匹配要求精确(去扩展名),避免短名误伤
            let base = (lower as NSString).deletingPathExtension
            return base == appName
        }

        for (dir, kind) in dirKinds {
            let parent = lib.appendingPathComponent(dir)
            for child in DiskUtils.children(of: parent) where matches(child.lastPathComponent) {
                // 沙盒容器目录名即 bundle id,已由 matches 精确覆盖
                results.append(ResidueItem(kind: kind, url: child,
                                           size: DiskUtils.allocatedSize(of: child)))
            }
        }

        // 偏好设置 plist:前缀必须是 bundle id
        if let bundleID {
            let prefs = lib.appendingPathComponent("Preferences")
            for child in DiskUtils.children(of: prefs)
            where child.lastPathComponent.lowercased().hasPrefix(bundleID) {
                results.append(ResidueItem(kind: "偏好设置", url: child,
                                           size: DiskUtils.allocatedSize(of: child)))
            }
            // LaunchAgents
            let agents = lib.appendingPathComponent("LaunchAgents")
            for child in DiskUtils.children(of: agents)
            where child.lastPathComponent.lowercased().contains(bundleID) {
                results.append(ResidueItem(kind: "启动代理", url: child,
                                           size: DiskUtils.allocatedSize(of: child)))
            }
        }

        return results.sorted { $0.size > $1.size }
    }

    // MARK: 卸载

    var totalSelectedSize: Int64 {
        var total = residues.filter(\.isSelected).reduce(0) { $0 + $1.size }
        if includeAppBundle, let app = selectedApp, app.size > 0 { total += app.size }
        return total
    }

    func uninstall() {
        guard let app = selectedApp else { return }
        let selected = residues.filter(\.isSelected)
        let includeBundle = includeAppBundle

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var errors: [String] = []
            var count = 0
            if includeBundle {
                do { try DiskUtils.trash(app.url); count += 1 } catch {
                    errors.append("应用本体:\(error.localizedDescription)")
                }
            }
            for item in selected {
                do { try DiskUtils.trash(item.url); count += 1 } catch {
                    errors.append("\(item.url.lastPathComponent):\(error.localizedDescription)")
                }
            }
            let message = errors.isEmpty
                ? "已将 \(count) 项移至废纸篓"
                : "完成 \(count) 项,失败:\(errors.joined(separator: ";"))"
            await MainActor.run {
                self.resultMessage = message
                self.residues = []
                self.selectedApp = nil
                self.loadApps()
            }
        }
    }

    // MARK: 启动项

    func loadLaunchItems() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var items: [LaunchItem] = []
            let sources: [(URL, LaunchItem.Kind)] = [
                (DiskUtils.home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
                (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
                (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
            ]
            for (dir, kind) in sources {
                for child in DiskUtils.children(of: dir) where child.pathExtension == "plist" {
                    let label = (NSDictionary(contentsOf: child)?["Label"] as? String)
                        ?? child.deletingPathExtension().lastPathComponent
                    items.append(LaunchItem(label: label, url: child, kind: kind))
                }
            }
            items.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            let final = items
            await MainActor.run { self.launchItems = final }
        }
    }

    func removeLaunchItem(_ item: LaunchItem) {
        guard item.editable else { return }
        // 先卸载再移除文件
        Shell.run("launchctl unload \(shellQuote(item.url.path)) 2>/dev/null")
        do {
            try DiskUtils.trash(item.url)
            launchItems.removeAll { $0.id == item.id }
        } catch {
            resultMessage = "移除失败:\(error.localizedDescription)"
        }
    }
}

func shellQuote(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
