import SwiftUI

struct RootView: View {
    @State private var selection: Module? = .clean

    var body: some View {
        NavigationSplitView {
            List(Module.allCases, selection: $selection) { module in
                HStack(spacing: 12) {
                    PlanetView(planet: module, size: 26, glowing: module == .status)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(module.title).font(.body.weight(.medium))
                        Text(module.planetName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 5)
                .tag(module)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "circle.grid.cross.fill")
                        .foregroundStyle(
                            LinearGradient(colors: Module.clean.planetColors,
                                           startPoint: .top, endPoint: .bottom)
                        )
                    Text("Burrow").font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        } detail: {
            Group {
                switch selection ?? .clean {
                case .clean: CleanView()
                case .purge: PurgeView()
                case .installer: InstallerView()
                case .software: SoftwareView()
                case .optimize: OptimizeView()
                case .analyze: AnalyzeView()
                case .status: StatusView()
                }
            }
            .background(SpaceBackground())
        }
    }
}

/// 深空渐变背景
struct SpaceBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if scheme == .dark {
                LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.11),
                                        Color(red: 0.09, green: 0.09, blue: 0.15)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .ignoresSafeArea()
    }
}
