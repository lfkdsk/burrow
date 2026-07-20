import SwiftUI

// MARK: - 模块定义(行星主题)

enum Module: String, CaseIterable, Identifiable {
    case clean
    case software
    case optimize
    case analyze
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "清理"
        case .software: return "软件"
        case .optimize: return "优化"
        case .analyze: return "分析"
        case .status: return "状态"
        }
    }

    var planetName: String {
        switch self {
        case .clean: return "Earth"
        case .software: return "Mars"
        case .optimize: return "Mercury"
        case .analyze: return "Jupiter"
        case .status: return "Sun"
        }
    }

    var subtitle: String {
        switch self {
        case .clean: return "深度清理缓存、日志与残留"
        case .software: return "卸载应用与管理启动项"
        case .optimize: return "刷新缓存、重建系统索引"
        case .analyze: return "磁盘空间可视化探索"
        case .status: return "实时系统健康仪表盘"
        }
    }

    /// 行星渐变色
    var planetColors: [Color] {
        switch self {
        case .clean: // 地球:蓝绿
            return [Color(red: 0.23, green: 0.51, blue: 0.96), Color(red: 0.13, green: 0.77, blue: 0.58)]
        case .software: // 火星:红橙
            return [Color(red: 0.95, green: 0.45, blue: 0.29), Color(red: 0.76, green: 0.22, blue: 0.18)]
        case .optimize: // 水星:银灰
            return [Color(red: 0.75, green: 0.78, blue: 0.83), Color(red: 0.45, green: 0.48, blue: 0.55)]
        case .analyze: // 木星:橙棕条纹
            return [Color(red: 0.95, green: 0.72, blue: 0.42), Color(red: 0.78, green: 0.45, blue: 0.25)]
        case .status: // 太阳:金黄
            return [Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 0.98, green: 0.55, blue: 0.15)]
        }
    }

    var accent: Color { planetColors[0] }

    var icon: String {
        switch self {
        case .clean: return "sparkles"
        case .software: return "app.badge"
        case .optimize: return "bolt.fill"
        case .analyze: return "chart.pie.fill"
        case .status: return "waveform.path.ecg"
        }
    }
}

// MARK: - 尺寸格式化

extension Int64 {
    var humanSize: String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt.string(fromByteCount: self)
    }
}

extension Double {
    var percentText: String { String(format: "%.0f%%", self * 100) }
}

// MARK: - 通用卡片样式

struct BentoCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

extension View {
    func bentoCard() -> some View { modifier(BentoCard()) }
}

// MARK: - 模块页头

struct ModuleHeader: View {
    let module: Module
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 14) {
            PlanetView(planet: module, size: 44, glowing: module == .status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(module.title).font(.title2.bold())
                    Text(module.planetName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(module.accent.opacity(0.15)))
                }
                Text(module.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}
