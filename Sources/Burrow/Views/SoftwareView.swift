import SwiftUI
import AppKit

struct SoftwareView: View {
    @StateObject private var engine = UninstallEngine()
    @State private var tab: Tab = .uninstall
    @State private var search = ""
    @State private var showConfirm = false

    enum Tab: String, CaseIterable {
        case uninstall = "应用卸载"
        case launchItems = "启动项"
    }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .software,
                         trailing: AnyView(
                            Picker("", selection: $tab) {
                                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                         ))
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            switch tab {
            case .uninstall: uninstallPane
            case .launchItems: launchPane
            }
        }
        .onAppear {
            engine.loadApps()
            engine.loadLaunchItems()
        }
        .confirmationDialog("确认卸载", isPresented: $showConfirm) {
            Button("移至废纸篓(\(engine.totalSelectedSize.humanSize))", role: .destructive) {
                engine.uninstall()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("应用与所选残留将移至废纸篓,可随时恢复。")
        }
    }

    // MARK: 卸载

    private var filteredApps: [AppInfo] {
        guard !search.isEmpty else { return engine.apps }
        return engine.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var uninstallPane: some View {
        HSplitView {
            // 左:应用列表
            VStack(spacing: 0) {
                TextField("搜索应用…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                if engine.isLoadingApps && engine.apps.isEmpty {
                    Spacer(); ProgressView("正在载入应用…"); Spacer()
                } else {
                    List(filteredApps, selection: Binding(
                        get: { engine.selectedApp?.id },
                        set: { id in
                            if let id, let app = engine.apps.first(where: { $0.id == id }) {
                                engine.scanResidues(for: app)
                            }
                        }
                    )) { app in
                        AppRow(app: app).tag(app.id)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 300, idealWidth: 340)

            // 右:残留详情
            residuePane
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let message = engine.resultMessage {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation { engine.resultMessage = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var residuePane: some View {
        if let app = engine.selectedApp {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.headline)
                        Text([app.bundleID, app.version.map { "v" + $0 }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)

                Divider()

                if engine.isScanningResidues {
                    Spacer(); HStack { Spacer(); ProgressView("正在扫描残留…"); Spacer() }; Spacer()
                } else {
                    List {
                        Section {
                            HStack {
                                Toggle("", isOn: $engine.includeAppBundle)
                                    .toggleStyle(.checkbox).labelsHidden()
                                Text("应用本体").font(.callout)
                                Spacer()
                                Text(app.size >= 0 ? app.size.humanSize : "…")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !engine.residues.isEmpty {
                            Section("残留文件(\(engine.residues.count))") {
                                ForEach($engine.residues) { $item in
                                    HStack(spacing: 10) {
                                        Toggle("", isOn: $item.isSelected)
                                            .toggleStyle(.checkbox).labelsHidden()
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 6) {
                                                Text(item.url.lastPathComponent).font(.callout)
                                                Text(item.kind)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Capsule().fill(Module.software.accent.opacity(0.14)))
                                                    .foregroundStyle(Module.software.accent)
                                            }
                                            Text(item.url.path)
                                                .font(.caption).foregroundStyle(.tertiary)
                                                .truncationMode(.middle).lineLimit(1)
                                        }
                                        Spacer()
                                        Text(item.size.humanSize)
                                            .font(.callout.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .contextMenu {
                                        Button("在 Finder 中显示") { DiskUtils.revealInFinder(item.url) }
                                    }
                                }
                            }
                        } else {
                            Text("未发现残留文件 🎉")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)

                    Divider()
                    HStack {
                        Text("共 \(engine.totalSelectedSize.humanSize)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showConfirm = true
                        } label: {
                            Label("卸载", systemImage: "trash")
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Module.software.accent)
                        .disabled(!engine.includeAppBundle && engine.residues.allSatisfy { !$0.isSelected })
                    }
                    .padding(12)
                    .background(.bar)
                }
            }
        } else {
            VStack(spacing: 14) {
                Spacer()
                PlanetView(planet: .software, size: 90)
                Text("选择左侧应用,扫描其在 15+ 个目录中的残留")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 启动项

    private var launchPane: some View {
        List {
            ForEach([LaunchItem.Kind.userAgent, .globalAgent, .daemon], id: \.rawValue) { kind in
                let items = engine.launchItems.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section("\(kind.rawValue)(\(items.count))") {
                        ForEach(items) { item in
                            HStack {
                                Image(systemName: item.kind == .userAgent
                                      ? "person.crop.circle" : "lock.shield")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.label).font(.callout)
                                    Text(item.url.path)
                                        .font(.caption).foregroundStyle(.tertiary)
                                        .truncationMode(.middle).lineLimit(1)
                                }
                                Spacer()
                                if item.editable {
                                    Button("移除") { engine.removeLaunchItem(item) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                } else {
                                    Text("只读")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contextMenu {
                                Button("在 Finder 中显示") { DiskUtils.revealInFinder(item.url) }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

private struct AppRow: View {
    let app: AppInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.callout)
                if let version = app.version {
                    Text("v" + version).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(app.size >= 0 ? app.size.humanSize : "…")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
