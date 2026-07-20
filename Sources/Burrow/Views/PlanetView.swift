import SwiftUI
import AppKit

/// 3D 渲染的行星图标(scripts/render_planets.swift 离线渲染),
/// 叠加缓慢旋转的光泽层;资源缺失时回退到渐变球。
struct PlanetView: View {
    let planet: Module
    var size: CGFloat = 28
    var glowing: Bool = false

    @State private var spinning = false

    var body: some View {
        Group {
            if let image = Self.image(for: planet) {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                    // 自转的云影光泽,让静态渲染图「活」起来
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    .white.opacity(0.0), .white.opacity(0.14),
                                    .white.opacity(0.0), .white.opacity(0.08),
                                    .white.opacity(0.0),
                                ]),
                                center: .center
                            )
                        )
                        .frame(width: size * sphereFraction, height: size * sphereFraction)
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(.linear(duration: 22).repeatForever(autoreverses: false),
                                   value: spinning)
                        .blendMode(.plusLighter)
                }
                .frame(width: size, height: size)
                .shadow(color: glowing ? planet.accent.opacity(0.6) : .black.opacity(0.28),
                        radius: glowing ? size * 0.2 : size * 0.05,
                        y: glowing ? 0 : 1)
            } else {
                fallbackBall
            }
        }
        .onAppear { spinning = true }
        .accessibilityHidden(true)
    }

    /// 渲染图中球体占画幅的比例(太阳含日冕留白更多)
    private var sphereFraction: CGFloat { planet == .status ? 0.62 : 0.82 }

    // MARK: 资源加载(带缓存)

    private static var cache: [String: NSImage] = [:]

    private static func image(for planet: Module) -> NSImage? {
        let name = planet.textureName
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png",
                                          subdirectory: "Planets"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    // MARK: 回退:原渐变球

    private var fallbackBall: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: planet.planetColors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.5), .clear],
                                     center: UnitPoint(x: 0.32, y: 0.28),
                                     startRadius: 0, endRadius: size * 0.6))
            Circle()
                .fill(RadialGradient(colors: [.clear, .black.opacity(0.32)],
                                     center: UnitPoint(x: 0.35, y: 0.32),
                                     startRadius: size * 0.25, endRadius: size * 0.85))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: glowing ? planet.accent.opacity(0.7) : .black.opacity(0.25),
                radius: glowing ? size * 0.28 : 3, y: glowing ? 0 : 1)
    }
}

extension Module {
    var textureName: String {
        switch self {
        case .clean: return "earth"
        case .software: return "mars"
        case .optimize: return "mercury"
        case .analyze: return "jupiter"
        case .status: return "sun"
        }
    }
}
