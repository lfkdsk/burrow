import SwiftUI
import AppKit

struct AnalyzeView: View {
    @StateObject private var engine = AnalyzeEngine()

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .analyze, trailing: AnyView(scanButtons))
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            if engine.isScanning {
                VStack(spacing: 14) {
                    Spacer()
                    PlanetView(planet: .analyze, size: 90)
                    ProgressView()
                    Text("正在扫描 \(engine.scanTarget)")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("已发现 \(engine.scannedCount) 个项目")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Button("停止") { engine.cancel() }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let current = engine.current {
                explorer(current)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    PlanetView(planet: .analyze, size: 110)
                    Text("选择一个位置,以树图形式探索磁盘占用\n单击方块进入目录,右键管理文件")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    scanButtons
                    Spacer(); Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var scanButtons: some View {
        HStack(spacing: 8) {
            Button("主目录") { engine.scan(url: DiskUtils.home) }
            Button("下载") { engine.scan(url: DiskUtils.home.appendingPathComponent("Downloads")) }
            Button("应用程序") { engine.scan(url: URL(fileURLWithPath: "/Applications")) }
            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "分析"
                if panel.runModal() == .OK, let url = panel.url {
                    engine.scan(url: url)
                }
            } label: {
                Label("选择文件夹…", systemImage: "folder")
            }
        }
        .disabled(engine.isScanning)
    }

    // MARK: 浏览器

    private func explorer(_ current: FileNode) -> some View {
        VStack(spacing: 0) {
            // 面包屑
            HStack(spacing: 4) {
                Button {
                    engine.goUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(current.parent == nil)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(current.pathChain) { node in
                            Button {
                                engine.drill(into: node)
                            } label: {
                                Text(node.name)
                                    .font(.callout.weight(node.id == current.id ? .semibold : .regular))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(node.id == current.id ? .primary : Color.secondary)
                            if node.id != current.id {
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                Spacer()
                Text(current.size.humanSize)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Module.analyze.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Divider()

            HSplitView {
                // 树图
                GeometryReader { geo in
                    let nodes = Treemap.displayNodes(for: current)
                    let cells = Treemap.layout(nodes: nodes,
                                               in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 2, dy: 2))
                    ZStack(alignment: .topLeading) {
                        ForEach(cells) { cell in
                            TreemapCellView(cell: cell, parentSize: current.size, engine: engine)
                        }
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .padding(6)

                // 侧栏列表
                List {
                    ForEach(current.children.prefix(200).map { $0 }) { child in
                        HStack(spacing: 8) {
                            Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                                .foregroundStyle(child.isDirectory ? Module.analyze.accent : .secondary)
                                .font(.caption)
                            Text(child.name).font(.callout).lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(child.size.humanSize)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                ProgressView(value: current.size > 0
                                             ? Double(child.size) / Double(current.size) : 0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 56)
                                    .tint(Module.analyze.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if child.isDirectory { engine.drill(into: child) }
                        }
                        .contextMenu {
                            Button("在 Finder 中显示") { DiskUtils.revealInFinder(child.url) }
                            Button("移到废纸篓", role: .destructive) { engine.trash(child) }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(minWidth: 240, idealWidth: 280)
            }
        }
    }
}

// MARK: - 树图方块

private struct TreemapCellView: View {
    let cell: TreemapCell
    let parentSize: Int64
    @ObservedObject var engine: AnalyzeEngine
    @State private var hovering = false

    private var fill: Color {
        let node = cell.node
        if node.isAggregate { return Color.gray.opacity(0.45) }
        if node.isDirectory {
            // 木星色系:按名称哈希微调色相
            let hash = abs(node.name.hashValue % 100)
            return Color(hue: 0.07 + Double(hash) / 100.0 * 0.06,
                         saturation: 0.55,
                         brightness: 0.62 + Double(hash % 30) / 100.0)
        }
        let hash = abs(cell.node.url.pathExtension.hashValue % 100)
        return Color(hue: 0.55 + Double(hash) / 100.0 * 0.25,
                     saturation: 0.35,
                     brightness: 0.55)
    }

    var body: some View {
        let rect = cell.rect
        RoundedRectangle(cornerRadius: 3)
            .fill(fill.opacity(hovering ? 1.0 : 0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.black.opacity(0.25), lineWidth: 0.5)
            )
            .overlay(
                Group {
                    if rect.width > 52 && rect.height > 30 {
                        VStack(spacing: 1) {
                            Text(cell.node.name)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                            Text(cell.node.size.humanSize)
                                .font(.system(size: 9).monospacedDigit())
                                .opacity(0.8)
                        }
                        .foregroundStyle(.white)
                        .padding(2)
                    }
                }
            )
            .frame(width: max(rect.width - 1.5, 1), height: max(rect.height - 1.5, 1))
            .offset(x: rect.minX, y: rect.minY)
            .onHover { hovering = $0 }
            .onTapGesture {
                if cell.node.isDirectory { engine.drill(into: cell.node) }
            }
            .contextMenu {
                if !cell.node.isAggregate {
                    Button("在 Finder 中显示") { DiskUtils.revealInFinder(cell.node.url) }
                    Button("移到废纸篓", role: .destructive) { engine.trash(cell.node) }
                }
            }
            .help("\(cell.node.name) — \(cell.node.size.humanSize)"
                  + (parentSize > 0
                     ? String(format:"(%.1f%%)", Double(cell.node.size) / Double(parentSize) * 100)
                     : ""))
    }
}
