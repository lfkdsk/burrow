import SwiftUI

struct CleanView: View {
    @StateObject private var engine = CleanEngine()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .clean)
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
            Button("清理 \(engine.totalSelectedCount) 项(释放 \(engine.totalSelectedSize.humanSize))", role: .destructive) {
                engine.clean()
            }
            Button("取消", role: .cancel) {}
        } message: {
            let hasTrash = engine.groups.contains {
                $0.category.isDestructive && $0.selectedCount > 0
            }
            Text(hasTrash
                 ? "大部分项目将移至废纸篓(可恢复);已勾选的「废纸篓」内容将被永久删除。"
                 : "所选项目将移至废纸篓,可随时恢复。")
        }
    }

    // MARK: 初始态

    private var idleView: some View {
        VStack(spacing: 18) {
            Spacer()
            PlanetView(planet: .clean, size: 120)
            if let report = engine.report {
                VStack(spacing: 4) {
                    Text("已释放 \(report.freedBytes.humanSize)")
                        .font(.title3.bold())
                    Text("共处理 \(report.itemCount) 项" + (report.errors.isEmpty ? "" : ",\(report.errors.count) 项失败"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !report.errors.isEmpty {
                        Text(report.errors.prefix(3).joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Text("扫描缓存、日志与开发者残留\n所有项目在清理前均可逐项确认")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                engine.scan()
            } label: {
                Label("开始扫描", systemImage: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Module.clean.accent)
            .controlSize(.large)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func scanningView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            PlanetView(planet: .clean, size: 90)
            ProgressView()
            Text(message).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 扫描结果

    private var resultView: some View {
        VStack(spacing: 0) {
            List {
                ForEach($engine.groups) { $group in
                    Section {
                        ForEach($group.items) { $item in
                            CleanItemRow(item: $item) {
                                engine.addToWhitelist(item)
                            }
                        }
                    } header: {
                        CleanGroupHeader(group: group) { selectAll in
                            engine.setAll(in: group.id, selected: selectAll)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已选 \(engine.totalSelectedCount) 项")
                        .font(.callout.weight(.medium))
                    Text("预计释放 \(engine.totalSelectedSize.humanSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新扫描") { engine.scan() }
                    .disabled(engine.phase == .cleaning)
                Button {
                    showConfirm = true
                } label: {
                    if engine.phase == .cleaning {
                        ProgressView().controlSize(.small).padding(.horizontal, 24)
                    } else {
                        Label("清理", systemImage: "sparkles")
                            .padding(.horizontal, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Module.clean.accent)
                .controlSize(.large)
                .disabled(engine.totalSelectedCount == 0 || engine.phase == .cleaning)
            }
            .padding(14)
            .background(.bar)
        }
    }
}

// MARK: - 行与组头

private struct CleanGroupHeader: View {
    let group: CleanGroup
    let onToggleAll: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.category.icon)
                .foregroundStyle(group.category.isDestructive ? Color.red : Module.clean.accent)
            Text(group.category.rawValue).font(.headline)
            Text(group.totalSize.humanSize)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if group.category.isDestructive {
                Text("永久删除")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
            }
            Spacer()
            Button(group.selectedCount == group.items.count ? "全不选" : "全选") {
                onToggleAll(group.selectedCount != group.items.count)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Module.clean.accent)
        }
        .help(group.category.blurb)
    }
}

private struct CleanItemRow: View {
    @Binding var item: CleanItem
    let onWhitelist: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.callout)
                Text(item.url.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.size.humanSize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("在 Finder 中显示") { DiskUtils.revealInFinder(item.url) }
            Button("加入白名单(不再扫描)") { onWhitelist() }
        }
    }
}
