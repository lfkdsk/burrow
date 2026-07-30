import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            WhitelistSettings()
                .tabItem { Label("白名单", systemImage: "checkmark.shield") }
            HistorySettings()
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            AboutSettings()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
    }
}

private struct HistorySettings: View {
    @ObservedObject private var log = OperationLog.shared

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("累计释放 \(log.totalFreed.humanSize) · 共 \(log.records.count) 条记录")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !log.records.isEmpty {
                    Button("清空历史") { log.clear() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if log.records.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("暂无操作记录\n清理 / 卸载等操作会自动记录在这里")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                Spacer()
            } else {
                List(log.records) { rec in
                    HStack(spacing: 10) {
                        Text(rec.module)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rec.detail).font(.callout).lineLimit(1)
                            Text(Self.dateFormatter.string(from: rec.date))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(rec.freedBytes.humanSize)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct WhitelistSettings: View {
    @EnvironmentObject var whitelist: WhitelistStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("白名单中的路径不会出现在清理扫描结果里。")
                .font(.callout)
                .foregroundStyle(.secondary)
            if whitelist.paths.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("暂无白名单条目\n在清理结果中右键任意条目即可加入")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(whitelist.paths).sorted(), id: \.self) { path in
                        HStack {
                            Text(path)
                                .font(.callout)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                whitelist.remove(path)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct AboutSettings: View {
    @EnvironmentObject var updater: UpdaterViewModel

    /// 从 App 包读取真实版本号,避免硬编码与实际发布版本脱节。
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        if let build, !build.isEmpty {
            return "v\(short) (\(build))"
        }
        return "v\(short)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            PlanetView(planet: .clean, size: 72)
            Text("Burrow").font(.title.bold())
            Text(versionText).font(.caption).foregroundStyle(.secondary)
            Text("Mac 系统维护工具\n清理 · 工程 · 安装包 · 软件 · 优化 · 分析 · 状态")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!updater.canCheckForUpdates)

                Toggle("自动检查更新", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.callout)
            }
            .padding(.top, 4)

            Text("灵感来自开源项目 Mole")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}
