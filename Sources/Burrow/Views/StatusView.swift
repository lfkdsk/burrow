import SwiftUI
import Charts

struct StatusView: View {
    @EnvironmentObject var monitor: StatusMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ModuleHeader(module: .status)
                    .padding(.top, 20)

                // 第一排:CPU + 内存
                HStack(spacing: 14) {
                    cpuCard
                    memCard
                }
                // 第二排:网络 + 磁盘 + 电池/系统
                HStack(spacing: 14) {
                    netCard
                    diskCard
                    infoCard
                }
                processCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear { monitor.start() }
    }

    // MARK: CPU

    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("CPU", icon: "cpu.fill")
            HStack(alignment: .firstTextBaseline) {
                Text(monitor.cpuUsage.percentText)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                Spacer()
                Text(String(format: "负载 %.2f / %.2f / %.2f",
                            monitor.loadAvg[0], monitor.loadAvg[1], monitor.loadAvg[2]))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Sparkline(values: monitor.cpuHistory, maxValue: 1.0,
                      color: Module.status.planetColors[1])
                .frame(height: 56)
        }
        .bentoCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: 内存

    private var memCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("内存", icon: "memorychip.fill")
            HStack(alignment: .firstTextBaseline) {
                Text(monitor.memUsed.humanSize)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                Text("/ \(monitor.memTotal.humanSize)")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if monitor.swapTotal > 0 {
                    Text("交换 \(monitor.swapUsed.humanSize)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Sparkline(values: monitor.memHistory, maxValue: 1.0,
                      color: Module.clean.planetColors[0])
                .frame(height: 56)
        }
        .bentoCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: 网络

    private var netCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("网络", icon: "network")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.caption2).foregroundStyle(.green)
                    Text(StatusMonitor.rateText(monitor.netRxRate))
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up").font(.caption2).foregroundStyle(.orange)
                    Text(StatusMonitor.rateText(monitor.netTxRate))
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
            }
            Sparkline(values: monitor.netRxHistory,
                      maxValue: max(monitor.netRxHistory.max() ?? 1, 1),
                      color: .green)
                .frame(height: 40)
        }
        .bentoCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: 磁盘

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("磁盘", icon: "internaldrive.fill")
            HStack {
                Ring(progress: monitor.diskTotal > 0
                     ? Double(monitor.diskTotal - monitor.diskFree) / Double(monitor.diskTotal) : 0,
                     colors: Module.analyze.planetColors)
                    .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 3) {
                    Text("可用 \(monitor.diskFree.humanSize)")
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text("共 \(monitor.diskTotal.humanSize)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .bentoCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: 电池 / 系统信息

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let battery = monitor.battery {
                cardTitle("电池", icon: battery.isCharging ? "battery.100.bolt" : "battery.75")
                HStack(alignment: .firstTextBaseline) {
                    Text("\(battery.percent)%")
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    if battery.externalPower {
                        Image(systemName: "powerplug.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                Text("循环 \(battery.cycleCount) 次 · 健康度 \(String(format: "%.0f%%", battery.healthPercent))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Divider()
            } else {
                cardTitle("系统", icon: "desktopcomputer")
            }
            Text("已运行 \(monitor.uptimeText)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(ProcessInfo.processInfo.operatingSystemVersionString)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .bentoCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: 进程

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("活跃进程 Top \(max(monitor.processes.count, 1))", icon: "list.bullet.rectangle.fill")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("进程").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("PID").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("CPU").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("内存").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
                Divider()
                ForEach(monitor.processes) { proc in
                    GridRow {
                        Text(proc.name).font(.callout).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(proc.pid)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Text(String(format: "%.1f%%", proc.cpu))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(proc.cpu > 80 ? .orange : .primary)
                        Text(proc.rssBytes.humanSize).font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .bentoCard()
        .frame(maxWidth: .infinity)
    }

    private func cardTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - 迷你图

struct Sparkline: View {
    let values: [Double]
    let maxValue: Double
    let color: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("t", item.offset), y: .value("v", item.element))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [color.opacity(0.4), color.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
            LineMark(x: .value("t", item.offset), y: .value("v", item.element))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...59)
        .chartYScale(domain: 0...max(maxValue, 0.0001))
        .chartLegend(.hidden)
    }
}

// MARK: - 圆环

struct Ring: View {
    let progress: Double
    let colors: [Color]

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: colors, center: .center,
                                    startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption.weight(.bold).monospacedDigit())
        }
    }
}
