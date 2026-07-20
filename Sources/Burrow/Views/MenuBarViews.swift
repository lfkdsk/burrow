import SwiftUI
import AppKit

/// 菜单栏图标 + 实时 CPU
struct MenuBarLabel: View {
    @EnvironmentObject var monitor: StatusMonitor

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.grid.cross.fill")
            Text(monitor.cpuUsage.percentText)
                .font(.caption.monospacedDigit())
        }
        .onAppear { monitor.start() }
    }
}

/// 菜单栏下拉面板:迷你 bento
struct MenuBarPanel: View {
    @EnvironmentObject var monitor: StatusMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                PlanetView(planet: .status, size: 20, glowing: true)
                Text("Burrow").font(.headline)
                Spacer()
                Text("已运行 " + monitor.uptimeText)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                MiniStat(title: "CPU", value: monitor.cpuUsage.percentText,
                         color: Module.status.planetColors[1])
                MiniStat(title: "内存",
                         value: monitor.memTotal > 0
                            ? (Double(monitor.memUsed) / Double(monitor.memTotal)).percentText : "-",
                         color: Module.clean.planetColors[0])
                MiniStat(title: "磁盘可用", value: monitor.diskFree.humanSize,
                         color: Module.analyze.accent)
            }

            HStack(spacing: 8) {
                MiniStat(title: "下载", value: StatusMonitor.rateText(monitor.netRxRate), color: .green)
                MiniStat(title: "上传", value: StatusMonitor.rateText(monitor.netTxRate), color: .orange)
                if let battery = monitor.battery {
                    MiniStat(title: battery.isCharging ? "电池 ⚡" : "电池",
                             value: "\(battery.percent)%",
                             color: .mint)
                }
            }

            Sparkline(values: monitor.cpuHistory, maxValue: 1,
                      color: Module.status.planetColors[1])
                .frame(height: 36)

            Divider()

            HStack {
                Button {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("打开 Burrow", systemImage: "macwindow")
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct MiniStat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
