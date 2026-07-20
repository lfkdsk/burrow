import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            WhitelistSettings()
                .tabItem { Label("白名单", systemImage: "checkmark.shield") }
            AboutSettings()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 360)
    }
}

private struct WhitelistSettings: View {
    @EnvironmentObject var whitelist: WhitelistStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("白名单中的路径不会出现在清理扫描结果里。")
                .font(.callout)
                .foregroundStyle(.secondary)
            if whitelist.paths.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("暂无白名单条目\n在清理结果中右键任意条目即可加入")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                Spacer()
            } else {
                List {
                    ForEach(Array(whitelist.paths).sorted(), id: \.self) { path in
                        HStack {
                            Text(path)
                                .font(.callout)
                                .truncationMode(.middle)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                whitelist.remove(path)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            PlanetView(planet: .clean, size: 72)
            Text("Burrow").font(.title.bold())
            Text("v1.0.0").font(.caption).foregroundStyle(.secondary)
            Text("Mac 系统维护工具\n清理 · 软件 · 优化 · 分析 · 状态")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("灵感来自开源项目 Mole")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}
