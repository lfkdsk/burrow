import SwiftUI

struct InstallerView: View {
    @StateObject private var engine = InstallerEngine()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .installer)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            switch engine.phase {
            case .idle:
                idleView
            case .scanning:
                scanningView
            case .ready, .cleaning:
                resultView
            }
        }
        .confirmationDialog("确认清理", isPresented: $showConfirm) {
            Button("清理 \(engine.selectedCount) 个(释放 \(engine.selectedSize.humanSize))",
                   role: .destructive) {
                engine.clean()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选安装包将移至废纸篓,可随时恢复。")
        }
    }

    // MARK: 初始态

    private var idleView: some View {
        VStack(spacing: 18) {
            Spacer()
            PlanetView(planet: .installer, size: 120)
            if let report = engine.report {
                VStack(spacing: 4) {
                    Text("已释放 \(report.freedBytes.humanSize)").font(.title3.bold())
                    Text("共清理 \(report.itemCount) 个安装包"
                         + (report.errors.isEmpty ? "" : ",\(report.errors.count) 项失败"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Text("扫描下载、桌面与缓存中遗留的 dmg / pkg / iso 安装包\n默认勾选超过 30 天未改动的旧安装包")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                engine.scan()
            } label: {
                Label("开始扫描", systemImage: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 22).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Module.installer.accent)
            .controlSize(.large)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            PlanetView(planet: .installer, size: 90)
            ProgressView()
            Text("正在扫描安装包…").font(.callout).foregroundStyle(.secondary)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 结果

    private var resultView: some View {
        VStack(spacing: 0) {
            if engine.items.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    PlanetView(planet: .installer, size: 90)
                    Text("没有发现遗留的安装包 🎉")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("重新扫描") { engine.scan() }
                    Spacer(); Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    Section {
                        ForEach($engine.items) { $item in
                            InstallerRow(item: $item) { engine.addToWhitelist(item) }
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill").foregroundStyle(Module.installer.accent)
                            Text("安装包").font(.headline)
                            Text("\(engine.items.count) 个 · \(engine.totalSize.humanSize)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            Button(engine.selectedCount == engine.items.count ? "全不选" : "全选") {
                                engine.setAll(engine.selectedCount != engine.items.count)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(Module.installer.accent)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已选 \(engine.selectedCount) 个").font(.callout.weight(.medium))
                    Text("预计释放 \(engine.selectedSize.humanSize)")
                        .font(.caption).foregroundStyle(.secondary)
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
                        Label("清理", systemImage: "trash").padding(.horizontal, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Module.installer.accent)
                .controlSize(.large)
                .disabled(engine.selectedCount == 0 || engine.phase == .cleaning)
            }
            .padding(14)
            .background(.bar)
        }
    }
}

private struct InstallerRow: View {
    @Binding var item: InstallerItem
    let onWhitelist: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.isSelected).toggleStyle(.checkbox).labelsHidden()
            Image(systemName: "shippingbox")
                .foregroundStyle(Module.installer.accent).font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).font(.callout).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.source)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Module.installer.accent)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Module.installer.accent.opacity(0.14)))
                    Text(item.daysOld == 0 ? "今天" : "\(item.daysOld) 天前")
                        .font(.caption).foregroundStyle(.tertiary)
                }
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
