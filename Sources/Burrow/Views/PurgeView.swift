import SwiftUI
import AppKit

struct PurgeView: View {
    @StateObject private var engine = PurgeEngine()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .purge)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            switch engine.phase {
            case .idle:
                idleView
            case .scanning(let message):
                scanningView(message)
            case .ready, .cleaning:
                resultView
            }
        }
        .confirmationDialog("确认清理", isPresented: $showConfirm) {
            Button("清理 \(engine.totalSelectedCount) 项(释放 \(engine.totalSelectedSize.humanSize))",
                   role: .destructive) {
                engine.clean()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选构建产物与依赖将移至废纸篓,可随时恢复。下次构建 / 安装依赖时会自动重建。")
        }
    }

    // MARK: 初始态

    private var idleView: some View {
        VStack(spacing: 18) {
            Spacer()
            PlanetView(planet: .purge, size: 120)
            if let report = engine.report {
                VStack(spacing: 4) {
                    Text("已释放 \(report.freedBytes.humanSize)").font(.title3.bold())
                    Text("共处理 \(report.itemCount) 项"
                         + (report.errors.isEmpty ? "" : ",\(report.errors.count) 项失败"))
                        .font(.callout).foregroundStyle(.secondary)
                    if !report.errors.isEmpty {
                        Text(report.errors.prefix(3).joined(separator: "\n"))
                            .font(.caption).foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Text("扫描项目里的 node_modules、target、.build、Pods 等构建产物\n只匹配带工程标记的目录,清理前逐项可选")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            scanButtons
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanButtons: some View {
        HStack(spacing: 8) {
            Button {
                engine.scan(root: DiskUtils.home)
            } label: {
                Label("扫描主目录", systemImage: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Module.purge.accent)
            .controlSize(.large)

            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "扫描"
                if panel.runModal() == .OK, let url = panel.url { engine.scan(root: url) }
            } label: {
                Label("选择文件夹…", systemImage: "folder").padding(.vertical, 6)
            }
            .controlSize(.large)
        }
    }

    private func scanningView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            PlanetView(planet: .purge, size: 90)
            ProgressView()
            Text(message).font(.callout).foregroundStyle(.secondary)
            Text("已遍历 \(engine.scannedCount) 个目录")
                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            Button("停止") { engine.cancel() }
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 扫描结果

    private var resultView: some View {
        VStack(spacing: 0) {
            if engine.groups.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    PlanetView(planet: .purge, size: 90)
                    Text("没有发现可清理的构建产物 🎉")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("重新扫描") { engine.scan(root: URL(fileURLWithPath: engine.scanRoot)) }
                    Spacer(); Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach($engine.groups) { $group in
                        Section {
                            ForEach($group.items) { $item in
                                PurgeItemRow(item: $item) { engine.addToWhitelist(item) }
                            }
                        } header: {
                            PurgeGroupHeader(group: group) { selectAll in
                                engine.setAll(in: group.id, selected: selectAll)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已选 \(engine.totalSelectedCount) 项").font(.callout.weight(.medium))
                    Text("预计释放 \(engine.totalSelectedSize.humanSize)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新扫描") { engine.scan(root: URL(fileURLWithPath: engine.scanRoot)) }
                    .disabled(engine.phase == .cleaning)
                Button {
                    showConfirm = true
                } label: {
                    if engine.phase == .cleaning {
                        ProgressView().controlSize(.small).padding(.horizontal, 24)
                    } else {
                        Label("清理", systemImage: "trash").padding(.horizontal, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Module.purge.accent)
                .controlSize(.large)
                .disabled(engine.totalSelectedCount == 0 || engine.phase == .cleaning)
            }
            .padding(14)
            .background(.bar)
        }
    }
}

// MARK: - 行与组头

private struct PurgeGroupHeader: View {
    let group: PurgeGroup
    let onToggleAll: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill").foregroundStyle(Module.purge.accent)
            Text(group.ecosystem).font(.headline)
            Text("\(group.items.count) 项 · \(group.totalSize.humanSize)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Button(group.selectedCount == group.items.count ? "全不选" : "全选") {
                onToggleAll(group.selectedCount != group.items.count)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Module.purge.accent)
        }
    }
}

private struct PurgeItemRow: View {
    @Binding var item: PurgeItem
    let onWhitelist: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.isSelected).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.projectName).font(.callout.weight(.medium))
                    Text(item.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Module.purge.accent)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Module.purge.accent.opacity(0.14)))
                }
                Text(item.url.path)
                    .font(.caption).foregroundStyle(.tertiary)
                    .truncationMode(.middle).lineLimit(1)
            }
            Spacer()
            Text(item.size.humanSize)
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("在 Finder 中显示") { DiskUtils.revealInFinder(item.url) }
            Button("加入白名单(不再扫描)") { onWhitelist() }
        }
    }
}
