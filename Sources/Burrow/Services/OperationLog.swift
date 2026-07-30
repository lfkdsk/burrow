import Foundation

/// 一条操作记录(清理 / 工程 / 安装包 / 软件卸载),对标 mole `history`。
struct OperationRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    let date: Date
    let module: String      // 模块标题,如「清理」
    let detail: String      // 人类可读摘要
    let itemCount: Int
    let freedBytes: Int64
}

/// 全局操作历史,持久化到 ~/Library/Application Support/Burrow/history.json。
final class OperationLog: ObservableObject {
    static let shared = OperationLog()

    @Published private(set) var records: [OperationRecord] = []

    private let fileURL: URL
    private let maxRecords = 200

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Burrow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    /// 记录一次操作。可从任意线程调用,内部切回主线程更新。
    func record(module: String, detail: String, itemCount: Int, freedBytes: Int64) {
        guard itemCount > 0 else { return }
        let rec = OperationRecord(date: Date(), module: module, detail: detail,
                                  itemCount: itemCount, freedBytes: freedBytes)
        Task { @MainActor in
            self.records.insert(rec, at: 0)
            if self.records.count > self.maxRecords {
                self.records.removeLast(self.records.count - self.maxRecords)
            }
            self.persist()
        }
    }

    @MainActor
    func clear() {
        records = []
        persist()
    }

    var totalFreed: Int64 { records.reduce(0) { $0 + $1.freedBytes } }

    // MARK: 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([OperationRecord].self, from: data) else { return }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
