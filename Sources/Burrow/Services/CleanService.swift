import Foundation

// MARK: - 模型

enum CleanCategory: String, CaseIterable, Identifiable {
    case appCaches = "应用缓存"
    case logs = "日志文件"
    case developer = "开发者缓存"
    case system = "系统残留"
    case orphaned = "孤儿启动项"
    case trash = "废纸篓"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appCaches: return "shippingbox.fill"
        case .logs: return "doc.text.fill"
        case .developer: return "hammer.fill"
        case .system: return "gearshape.2.fill"
        case .orphaned: return "bolt.slash.fill"
        case .trash: return "trash.fill"
        }
    }

    var blurb: String {
        switch self {
        case .appCaches: return "~/Library/Caches 下的应用缓存,删除后应用会自动重建"
        case .logs: return "应用与系统日志,可安全清除"
        case .developer: return "Xcode、npm / pnpm / gradle / cargo / VS Code 等开发者缓存与包索引"
        case .system: return "窗口恢复状态、崩溃报告等系统残留"
        case .orphaned: return "指向已删除程序的登录启动代理,可安全移除"
        case .trash: return "清空废纸篓将永久删除文件,不可恢复"
        }
    }

    /// 是否为不可恢复的删除(仅废纸篓)
    var isDestructive: Bool { self == .trash }
}

struct CleanItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let size: Int64
    var isSelected: Bool
}

struct CleanGroup: Identifiable {
    let category: CleanCategory
    var items: [CleanItem]
    var id: String { category.id }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.isSelected).count }
}

struct CleanReport {
    var freedBytes: Int64 = 0
    var itemCount: Int = 0
    var errors: [String] = []
}

// MARK: - 引擎

final class CleanEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning(String)
        case ready
        case cleaning
    }

    @Published var phase: Phase = .idle
    @Published var groups: [CleanGroup] = []
    @Published var report: CleanReport?

    /// 缓存目录中绝不列出的关键系统项
    private let protectedNames: Set<String> = [
        "CloudKit", "com.apple.bird", "FileProvider", "com.apple.fileproviderd",
        "com.apple.homed", "com.apple.HomeKit", "com.apple.Safari.SafeBrowsing",
        "com.apple.containermanagerd", "com.apple.akd",
    ]

    var totalSelectedSize: Int64 { groups.reduce(0) { $0 + $1.selectedSize } }
    var totalSelectedCount: Int { groups.reduce(0) { $0 + $1.selectedCount } }

    // MARK: 扫描

    func scan() {
        guard phase != .cleaning else { return }
        phase = .scanning("准备中…")
        report = nil
        groups = []

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var result: [CleanGroup] = []
            for category in CleanCategory.allCases {
                await MainActor.run { self.phase = .scanning("正在扫描 \(category.rawValue)…") }
                let items = self.scanCategory(category)
                if !items.isEmpty {
                    result.append(CleanGroup(category: category, items: items))
                }
            }
            let final = result
            await MainActor.run {
                self.groups = final
                self.phase = .ready
            }
        }
    }

    private func scanCategory(_ category: CleanCategory) -> [CleanItem] {
        let home = DiskUtils.home
        let whitelist = WhitelistStore.shared
        var items: [CleanItem] = []

        func append(_ url: URL, name: String? = nil, selected: Bool = true, minSize: Int64 = 1) {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            guard !whitelist.contains(url) else { return }
            let size = DiskUtils.allocatedSize(of: url)
            guard size >= minSize else { return }
            items.append(CleanItem(name: name ?? url.lastPathComponent,
                                   url: url, size: size, isSelected: selected))
        }

        switch category {
        case .appCaches:
            let cachesDir = home.appendingPathComponent("Library/Caches")
            for child in DiskUtils.children(of: cachesDir) {
                guard !protectedNames.contains(child.lastPathComponent) else { continue }
                append(child, minSize: 1024)
            }

        case .logs:
            let logsDir = home.appendingPathComponent("Library/Logs")
            for child in DiskUtils.children(of: logsDir) {
                append(child, minSize: 1024)
            }

        case .developer:
            let candidates: [(String, String)] = [
                ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
                ("Library/Developer/Xcode/iOS DeviceSupport", "iOS 设备调试符号"),
                ("Library/Developer/CoreSimulator/Caches", "模拟器缓存"),
                (".npm/_cacache", "npm 缓存"),
                (".yarn/berry/cache", "Yarn 缓存"),
                ("Library/pnpm/store", "pnpm 全局存储"),
                (".gradle/caches", "Gradle 缓存"),
                (".cargo/registry/cache", "Cargo 缓存"),
                (".m2/repository", "Maven 仓库缓存"),
                (".ivy2/cache", "Ivy / sbt 缓存"),
                ("go/pkg/mod/cache", "Go 模块下载缓存"),
                (".pub-cache", "Dart / Flutter 缓存"),
                (".android/cache", "Android 构建缓存"),
                ("Library/Application Support/Code/CachedData", "VS Code 缓存"),
                (".cache", "XDG 通用缓存 (~/.cache)"),
            ]
            for (path, name) in candidates {
                append(home.appendingPathComponent(path), name: name, minSize: 1024)
            }

        case .system:
            append(home.appendingPathComponent("Library/Saved Application State"),
                   name: "窗口恢复状态", minSize: 1024)
            append(home.appendingPathComponent("Library/Application Support/CrashReporter"),
                   name: "崩溃报告", minSize: 1)

        case .orphaned:
            let agentsDir = home.appendingPathComponent("Library/LaunchAgents")
            for child in DiskUtils.children(of: agentsDir) where child.pathExtension == "plist" {
                guard let dict = NSDictionary(contentsOf: child),
                      let program = Self.launchProgramPath(dict),
                      !FileManager.default.fileExists(atPath: program) else { continue }
                let label = (dict["Label"] as? String) ?? child.deletingPathExtension().lastPathComponent
                append(child, name: "\(label)(指向已删除程序)", minSize: 0)
            }

        case .trash:
            // 默认不勾选:清空废纸篓是永久删除
            append(home.appendingPathComponent(".Trash"), name: "废纸篓", selected: false, minSize: 1)
        }

        return items.sorted { $0.size > $1.size }
    }

    // MARK: 清理

    func clean() {
        guard phase == .ready else { return }
        phase = .cleaning

        let selected: [(CleanCategory, CleanItem)] = groups.flatMap { group in
            group.items.filter(\.isSelected).map { (group.category, $0) }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var report = CleanReport()
            let fm = FileManager.default

            for (category, item) in selected {
                do {
                    if category.isDestructive {
                        // 清空废纸篓:逐项永久删除
                        for child in DiskUtils.children(of: item.url) {
                            try fm.removeItem(at: child)
                        }
                    } else {
                        try DiskUtils.trash(item.url)
                    }
                    report.freedBytes += item.size
                    report.itemCount += 1
                } catch {
                    report.errors.append("\(item.name):\(error.localizedDescription)")
                }
            }

            OperationLog.shared.record(module: Module.clean.title,
                                       detail: "清理缓存、日志与残留 \(report.itemCount) 项",
                                       itemCount: report.itemCount, freedBytes: report.freedBytes)
            let final = report
            await MainActor.run {
                self.report = final
                self.phase = .idle
                self.groups = []
            }
        }
    }

    /// 从 LaunchAgent plist 解析出可执行文件的绝对路径;无法确定绝对路径时返回 nil
    /// (相对命令 / PATH 查找的程序无法可靠判定存在性,保守跳过,避免误判为孤儿)。
    static func launchProgramPath(_ dict: NSDictionary) -> String? {
        func absolute(_ p: String) -> String? {
            if p.hasPrefix("/") { return p }
            if p.hasPrefix("~") { return (p as NSString).expandingTildeInPath }
            return nil
        }
        if let program = dict["Program"] as? String { return absolute(program) }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first {
            return absolute(first)
        }
        return nil
    }

    // MARK: 选择操作

    func setAll(in categoryID: String, selected: Bool) {
        guard let gi = groups.firstIndex(where: { $0.id == categoryID }) else { return }
        for ii in groups[gi].items.indices {
            groups[gi].items[ii].isSelected = selected
        }
    }

    func addToWhitelist(_ item: CleanItem) {
        WhitelistStore.shared.add(item.url)
        for gi in groups.indices {
            groups[gi].items.removeAll { $0.id == item.id }
        }
        groups.removeAll { $0.items.isEmpty }
    }
}
