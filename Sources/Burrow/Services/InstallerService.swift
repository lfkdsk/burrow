import Foundation

// MARK: - 模型

struct InstallerItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    let source: String   // 「下载」「桌面」「缓存」
    var isSelected: Bool

    var daysOld: Int {
        max(0, Int(Date().timeIntervalSince(modified) / 86400))
    }
}

// MARK: - 引擎

/// 查找并清理遗留的大安装包(.dmg / .pkg / .iso / .xip),对标 mole `installer`。
final class InstallerEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case cleaning
    }

    @Published var phase: Phase = .idle
    @Published var items: [InstallerItem] = []
    @Published var report: CleanReport?

    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
    private static let minSize: Int64 = 1_000_000        // 1 MB
    private static let staleThreshold: TimeInterval = 30 * 86400  // 30 天

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.isSelected).count }

    // MARK: 扫描

    func scan() {
        guard phase != .cleaning else { return }
        phase = .scanning
        report = nil
        items = []

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let home = DiskUtils.home
            let sources: [(URL, String, Int)] = [
                (home.appendingPathComponent("Downloads"), "下载", 4),
                (home.appendingPathComponent("Desktop"), "桌面", 2),
                (home.appendingPathComponent("Library/Caches"), "缓存", 3),
            ]
            var found: [InstallerItem] = []
            for (dir, source, depth) in sources {
                found.append(contentsOf: self.scanDir(dir, source: source, maxDepth: depth))
            }
            found.sort { $0.size > $1.size }
            let final = found
            await MainActor.run {
                self.items = final
                self.phase = .ready
            }
        }
    }

    private func scanDir(_ dir: URL, source: String, maxDepth: Int) -> [InstallerItem] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: keys,
                                     options: [.skipsHiddenFiles],
                                     errorHandler: { _, _ in true }) else { return [] }
        let whitelist = WhitelistStore.shared
        var result: [InstallerItem] = []
        for case let url as URL in en {
            if en.level > maxDepth { en.skipDescendants(); continue }
            guard Self.installerExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isSymbolicLink != true, v.isRegularFile == true else { continue }
            let size = Int64(v.totalFileAllocatedSize ?? 0)
            guard size >= Self.minSize, !whitelist.contains(url) else { continue }
            let modified = v.contentModificationDate ?? .distantPast
            let stale = Date().timeIntervalSince(modified) > Self.staleThreshold
            result.append(InstallerItem(url: url, size: size, modified: modified,
                                        source: source, isSelected: stale))
        }
        return result
    }

    // MARK: 清理

    func clean() {
        guard phase == .ready else { return }
        phase = .cleaning
        let selected = items.filter(\.isSelected)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var report = CleanReport()
            for item in selected {
                do {
                    try DiskUtils.trash(item.url)
                    report.freedBytes += item.size
                    report.itemCount += 1
                } catch {
                    report.errors.append("\(item.url.lastPathComponent):\(error.localizedDescription)")
                }
            }
            OperationLog.shared.record(module: Module.installer.title,
                                       detail: "清理安装包 \(report.itemCount) 个",
                                       itemCount: report.itemCount, freedBytes: report.freedBytes)
            let final = report
            await MainActor.run {
                self.report = final
                self.phase = .idle
                self.items = []
            }
        }
    }

    // MARK: 选择操作

    func setAll(_ selected: Bool) {
        for i in items.indices { items[i].isSelected = selected }
    }

    func addToWhitelist(_ item: InstallerItem) {
        WhitelistStore.shared.add(item.url)
        items.removeAll { $0.id == item.id }
    }
}
