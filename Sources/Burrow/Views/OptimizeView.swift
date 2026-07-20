import SwiftUI

struct OptimizeView: View {
    @StateObject private var engine = OptimizeEngine()

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .optimize)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            HSplitView {
                // 任务列表
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(engine.tasks) { task in
                            TaskCard(task: task,
                                     isOn: engine.enabled.contains(task.id)) {
                                engine.toggle(task)
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 380)

                // 执行日志
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label("执行日志", systemImage: "terminal")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(12)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                if engine.log.isEmpty {
                                    Text(engine.hasAdminTask
                                         ? "点击「立即优化」开始执行\n包含需要管理员权限的任务,系统会弹出授权提示"
                                         : "点击「立即优化」开始执行")
                                        .foregroundStyle(.tertiary)
                                        .font(.callout)
                                }
                                ForEach(engine.log) { line in
                                    Text(line.text)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(line.isError ? Color.orange : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.id)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: engine.log.count) { _, _ in
                            if let last = engine.log.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Text("已选 \(engine.enabled.count) 项任务")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    engine.run()
                } label: {
                    if engine.isRunning {
                        ProgressView().controlSize(.small).padding(.horizontal, 26)
                    } else {
                        Label("立即优化", systemImage: "bolt.fill")
                            .padding(.horizontal, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Module.optimize.planetColors[1])
                .controlSize(.large)
                .disabled(engine.isRunning || engine.enabled.isEmpty)
            }
            .padding(14)
            .background(.bar)
        }
    }
}

private struct TaskCard: View {
    let task: MaintenanceTask
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Module.optimize.planetColors[1] : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(task.name).font(.callout.weight(.medium))
                        if task.needsAdmin {
                            Label("管理员", systemImage: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bentoCard()
        .opacity(isOn ? 1 : 0.65)
    }
}
