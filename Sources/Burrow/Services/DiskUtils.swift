import Foundation

enum DiskUtils {
    /// 递归计算文件/目录的磁盘占用(分配大小),跳过符号链接与无权限项。
    static func allocatedSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        guard let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey,
                                                         .totalFileAllocatedSizeKey]) else { return 0 }
        if rv.isSymbolicLink == true { return 0 }
        if rv.isDirectory != true {
            return Int64(rv.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let file as URL in en {
            guard let v = try? file.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// 列出目录一级子项(不解析符号链接),失败返回空。
    static func children(of url: URL, includeFiles: Bool = true) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants]
        ) else { return [] }
        return items.filter { item in
            guard let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            if v.isSymbolicLink == true { return false }
            return includeFiles || v.isDirectory == true
        }
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// 移到废纸篓
    @discardableResult
    static func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspaceReveal(url)
    }
}

import AppKit
func NSWorkspaceReveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

// MARK: - Shell 执行

struct ShellResult {
    let status: Int32
    let output: String
}

enum Shell {
    /// 运行普通命令(不需要管理员权限)
    @discardableResult
    static func run(_ command: String) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: "无法启动:\(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return ShellResult(status: process.terminationStatus, output: out)
    }

    /// 以管理员权限运行(系统弹出授权对话框)。命令中避免使用引号。
    @discardableResult
    static func runAsAdmin(_ command: String) -> ShellResult {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: "无法启动:\(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return ShellResult(status: process.terminationStatus, output: out)
    }
}

// MARK: - 白名单

final class WhitelistStore: ObservableObject {
    static let shared = WhitelistStore()
    private static let key = "burrow.whitelist.paths"

    @Published private(set) var paths: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        paths = Set(saved)
    }

    func contains(_ url: URL) -> Bool { paths.contains(url.path) }

    func add(_ url: URL) {
        paths.insert(url.path)
        persist()
    }

    func remove(_ path: String) {
        paths.remove(path)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(paths).sorted(), forKey: Self.key)
    }
}
