import Foundation

// MARK: - 文件树节点

final class FileNode: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    var size: Int64 = 0
    var children: [FileNode] = []
    weak var parent: FileNode?
    var isAggregate = false // 树图中的「其他」聚合块

    init(name: String, url: URL, isDirectory: Bool, parent: FileNode? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.parent = parent
    }

    var pathChain: [FileNode] {
        var chain: [FileNode] = []
        var node: FileNode? = self
        while let n = node { chain.append(n); node = n.parent }
        return chain.reversed()
    }
}

// MARK: - 扫描引擎

final class AnalyzeEngine: ObservableObject {
    @Published var root: FileNode?
    @Published var current: FileNode?
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var scanTarget: String = ""

    private var cancelled = false
    private var counter = 0

    func scan(url: URL) {
        cancelled = false
        counter = 0
        scannedCount = 0
        scanTarget = url.path
        root = nil
        current = nil
        isScanning = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let node = self.build(url: url, parent: nil)
            await MainActor.run {
                self.root = node
                self.current = node
                self.isScanning = false
            }
        }
    }

    func cancel() { cancelled = true }

    private func build(url: URL, parent: FileNode?) -> FileNode {
        let node = FileNode(name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                            url: url, isDirectory: true, parent: parent)
        guard !cancelled else { return node }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .isVolumeKey]
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
                                                         options: []) else { return node }
        for child in contents {
            if cancelled { break }
            guard let rv = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.isSymbolicLink == true { continue }
            if rv.isVolume == true { continue } // 不跨挂载点

            if rv.isDirectory == true {
                let sub = build(url: child, parent: node)
                if sub.size > 0 || !sub.children.isEmpty {
                    node.children.append(sub)
                    node.size += sub.size
                }
            } else {
                let size = Int64(rv.totalFileAllocatedSize ?? 0)
                if size > 0 {
                    let leaf = FileNode(name: child.lastPathComponent, url: child,
                                        isDirectory: false, parent: node)
                    leaf.size = size
                    node.children.append(leaf)
                    node.size += size
                }
            }

            counter += 1
            if counter % 2000 == 0 {
                let count = counter
                DispatchQueue.main.async { self.scannedCount = count }
            }
        }
        node.children.sort { $0.size > $1.size }
        return node
    }

    // MARK: 导航

    func drill(into node: FileNode) {
        guard node.isDirectory, !node.isAggregate else { return }
        current = node
    }

    func goUp() {
        if let parent = current?.parent { current = parent }
    }

    // MARK: 删除

    func trash(_ node: FileNode) {
        guard !node.isAggregate else { return }
        do {
            try DiskUtils.trash(node.url)
            // 从树中摘除并向上修正尺寸
            if let parent = node.parent {
                parent.children.removeAll { $0.id == node.id }
                var p: FileNode? = parent
                while let n = p { n.size -= node.size; p = n.parent }
            }
            objectWillChange.send()
        } catch {
            NSLog("trash failed: \(error)")
        }
    }
}

// MARK: - Squarified Treemap 布局

struct TreemapCell: Identifiable {
    let id: UUID
    let node: FileNode
    let rect: CGRect
}

enum Treemap {
    /// 经典 squarified 算法:让矩形尽量接近正方形
    static func layout(nodes: [FileNode], in rect: CGRect) -> [TreemapCell] {
        let valid = nodes.filter { $0.size > 0 }
        guard !valid.isEmpty, rect.width > 4, rect.height > 4 else { return [] }
        let total = Double(valid.reduce(Int64(0)) { $0 + $1.size })
        let scale = rect.width * rect.height / total

        var cells: [TreemapCell] = []
        var remaining = rect
        var row: [(FileNode, Double)] = []
        var index = 0

        func worst(_ row: [(FileNode, Double)], side: Double) -> Double {
            guard !row.isEmpty, side > 0 else { return .infinity }
            let sum = row.reduce(0) { $0 + $1.1 }
            guard sum > 0 else { return .infinity }
            let maxA = row.map(\.1).max()!
            let minA = row.map(\.1).min()!
            let s2 = sum * sum
            let w2 = side * side
            return max(w2 * maxA / s2, s2 / (w2 * minA))
        }

        func flush() {
            guard !row.isEmpty else { return }
            let sum = row.reduce(0) { $0 + $1.1 }
            if remaining.width >= remaining.height {
                // 竖直条带,靠左
                let stripW = min(sum / remaining.height, remaining.width)
                var y = remaining.minY
                for (node, area) in row {
                    let h = stripW > 0 ? area / stripW : 0
                    cells.append(TreemapCell(id: node.id, node: node,
                                             rect: CGRect(x: remaining.minX, y: y,
                                                          width: stripW, height: h)))
                    y += h
                }
                remaining = CGRect(x: remaining.minX + stripW, y: remaining.minY,
                                   width: max(remaining.width - stripW, 0), height: remaining.height)
            } else {
                // 水平条带,靠上
                let stripH = min(sum / remaining.width, remaining.height)
                var x = remaining.minX
                for (node, area) in row {
                    let w = stripH > 0 ? area / stripH : 0
                    cells.append(TreemapCell(id: node.id, node: node,
                                             rect: CGRect(x: x, y: remaining.minY,
                                                          width: w, height: stripH)))
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + stripH,
                                   width: remaining.width, height: max(remaining.height - stripH, 0))
            }
            row = []
        }

        while index < valid.count {
            let node = valid[index]
            let area = Double(node.size) * scale
            let side = min(remaining.width, remaining.height)
            if row.isEmpty || worst(row + [(node, area)], side: side) <= worst(row, side: side) {
                row.append((node, area))
                index += 1
            } else {
                flush()
            }
        }
        flush()
        return cells
    }

    /// 取前 N 大子项,其余聚合为「其他」
    static func displayNodes(for parent: FileNode, limit: Int = 60) -> [FileNode] {
        let children = parent.children
        guard children.count > limit else { return children }
        let head = Array(children.prefix(limit))
        let restSize = children.dropFirst(limit).reduce(Int64(0)) { $0 + $1.size }
        let rest = FileNode(name: "其他(\(children.count - limit) 项)",
                            url: parent.url, isDirectory: false, parent: parent)
        rest.size = restSize
        rest.isAggregate = true
        return head + [rest]
    }
}
