import Foundation

// MARK: - 规则

/// 一类可清理的工程产物目录:目录名 + 需在其父目录存在的「工程标记」文件。
/// markers 为空表示仅凭目录名即可判定(如 __pycache__)。
struct ArtifactRule {
    let dirName: String
    let markers: [String]
    let label: String
    let ecosystem: String
    /// 是否默认勾选;dist/build/vendor/venv 这类含义宽泛或重建代价高的默认不勾。
    var safeDefault: Bool = true
}

// MARK: - 模型

struct PurgeItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let projectName: String
    let label: String
    let ecosystem: String
    let size: Int64
    var isSelected: Bool
}

struct PurgeGroup: Identifiable {
    let ecosystem: String
    var items: [PurgeItem]
    var id: String { ecosystem }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.isSelected).count }
}

// MARK: - 引擎

final class PurgeEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning(String)
        case ready
        case cleaning
    }

    @Published var phase: Phase = .idle
    @Published var groups: [PurgeGroup] = []
    @Published var scannedCount = 0
    @Published var scanRoot: String = ""
    @Published var report: CleanReport?

    private var cancelled = false

    /// 已知的工程产物目录规则
    static let rules: [ArtifactRule] = [
        ArtifactRule(dirName: "node_modules", markers: ["package.json"], label: "node_modules", ecosystem: "Node.js"),
        ArtifactRule(dirName: ".next", markers: ["package.json"], label: ".next", ecosystem: "Next.js"),
        ArtifactRule(dirName: ".nuxt", markers: ["package.json"], label: ".nuxt", ecosystem: "Nuxt"),
        ArtifactRule(dirName: ".turbo", markers: ["package.json", "turbo.json"], label: ".turbo", ecosystem: "Turborepo"),
        ArtifactRule(dirName: "dist", markers: ["package.json"], label: "dist", ecosystem: "前端产物", safeDefault: false),
        ArtifactRule(dirName: ".build", markers: ["Package.swift"], label: ".build", ecosystem: "Swift"),
        ArtifactRule(dirName: "target", markers: ["Cargo.toml", "pom.xml", "build.sbt"], label: "target", ecosystem: "Rust / Maven"),
        ArtifactRule(dirName: "build", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "CMakeLists.txt", "pubspec.yaml"], label: "build", ecosystem: "Gradle / CMake", safeDefault: false),
        ArtifactRule(dirName: ".gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], label: ".gradle", ecosystem: "Gradle"),
        ArtifactRule(dirName: "Pods", markers: ["Podfile"], label: "Pods", ecosystem: "CocoaPods"),
        ArtifactRule(dirName: "Carthage", markers: ["Cartfile"], label: "Carthage", ecosystem: "Carthage"),
        ArtifactRule(dirName: "vendor", markers: ["composer.json", "go.mod", "Gemfile"], label: "vendor", ecosystem: "PHP / Go / Ruby", safeDefault: false),
        ArtifactRule(dirName: ".venv", markers: ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"], label: ".venv", ecosystem: "Python venv", safeDefault: false),
        ArtifactRule(dirName: "venv", markers: ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"], label: "venv", ecosystem: "Python venv", safeDefault: false),
        ArtifactRule(dirName: "__pycache__", markers: [], label: "__pycache__", ecosystem: "Python 缓存"),
        ArtifactRule(dirName: ".pytest_cache", markers: [], label: ".pytest_cache", ecosystem: "Python 缓存"),
        ArtifactRule(dirName: ".mypy_cache", markers: [], label: ".mypy_cache", ecosystem: "Python 缓存"),
        ArtifactRule(dirName: ".ruff_cache", markers: [], label: ".ruff_cache", ecosystem: "Python 缓存"),
        ArtifactRule(dirName: ".terraform", markers: [".terraform.lock.hcl"], label: ".terraform", ecosystem: "Terraform"),
    ]

    /// 不进入递归的重目录(与工程无关,避免误扫和性能问题)
    private static let skipNames: Set<String> = [
        "Library", "Applications", ".Trash", "Pictures", "Music", "Movies",
        "Photos Library.photoslibrary", ".git", ".svn", ".hg", ".cache",
    ]

    var totalSelectedSize: Int64 { groups.reduce(0) { $0 + $1.selectedSize } }
    var totalSelectedCount: Int { groups.reduce(0) { $0 + $1.selectedCount } }

    // MARK: 扫描

    func scan(root: URL) {
        guard phase != .cleaning else { return }
        cancelled = false
        scanRoot = root.path
        scannedCount = 0
        report = nil
        groups = []
        phase = .scanning("准备中…")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let items = self.walk(root: root)
            let grouped = Dictionary(grouping: items, by: \.ecosystem)
                .map { PurgeGroup(ecosystem: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
                .sorted { $0.totalSize > $1.totalSize }
            await MainActor.run {
                if !self.cancelled {
                    self.groups = grouped
                    self.phase = .ready
                }
            }
        }
    }

    func cancel() {
        cancelled = true
        phase = .idle
    }

    /// 深度优先遍历,命中产物目录即收录并剪枝(不再深入)。
    private func walk(root: URL) -> [PurgeItem] {
        let fm = FileManager.default
        let whitelist = WhitelistStore.shared
        var results: [PurgeItem] = []
        var stack: [(URL, Int)] = [(root, 0)]
        var scanned = 0

        while let (dir, depth) = stack.popLast() {
            if cancelled { break }
            if depth > 9 { continue }
            guard let children = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            ) else { continue }

            let siblingNames = Set(children.map(\.lastPathComponent))
            var descend: [URL] = []

            for child in children {
                guard let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      v.isSymbolicLink != true, v.isDirectory == true else { continue }
                let name = child.lastPathComponent

                if let rule = Self.rules.first(where: {
                    $0.dirName == name && ($0.markers.isEmpty || $0.markers.contains(where: siblingNames.contains))
                }) {
                    if !whitelist.contains(child) {
                        let size = DiskUtils.allocatedSize(of: child)
                        if size > 0 {
                            results.append(PurgeItem(url: child, projectName: dir.lastPathComponent,
                                                     label: rule.label, ecosystem: rule.ecosystem,
                                                     size: size, isSelected: rule.safeDefault))
                        }
                    }
                    continue // 剪枝:不深入产物目录内部
                }

                if Self.skipNames.contains(name) { continue }
                // 未命中规则的隐藏目录(.git/.idea/.config 等)不深入
                if name.hasPrefix(".") { continue }
                descend.append(child)
            }

            scanned += 1
            if scanned % 40 == 0 {
                let count = scanned
                let current = dir.lastPathComponent
                Task { @MainActor in
                    self.scannedCount = count
                    if case .scanning = self.phase { self.phase = .scanning("正在扫描 \(current)…") }
                }
            }
            stack.append(contentsOf: descend.map { ($0, depth + 1) })
        }
        return results
    }

    // MARK: 清理

    func clean() {
        guard phase == .ready else { return }
        phase = .cleaning

        let selected: [PurgeItem] = groups.flatMap { $0.items.filter(\.isSelected) }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var report = CleanReport()
            for item in selected {
                do {
                    try DiskUtils.trash(item.url)
                    report.freedBytes += item.size
                    report.itemCount += 1
                } catch {
                    report.errors.append("\(item.projectName)/\(item.label):\(error.localizedDescription)")
                }
            }
            OperationLog.shared.record(module: Module.purge.title,
                                       detail: "清理工程产物 \(report.itemCount) 项",
                                       itemCount: report.itemCount, freedBytes: report.freedBytes)
            let final = report
            await MainActor.run {
                self.report = final
                self.phase = .idle
                self.groups = []
            }
        }
    }

    // MARK: 选择操作

    func setAll(in ecosystem: String, selected: Bool) {
        guard let gi = groups.firstIndex(where: { $0.id == ecosystem }) else { return }
        for ii in groups[gi].items.indices { groups[gi].items[ii].isSelected = selected }
    }

    func addToWhitelist(_ item: PurgeItem) {
        WhitelistStore.shared.add(item.url)
        for gi in groups.indices { groups[gi].items.removeAll { $0.id == item.id } }
        groups.removeAll { $0.items.isEmpty }
    }
}
