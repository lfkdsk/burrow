import SwiftUI
import Sparkle

/// Sparkle 自动更新的 SwiftUI 封装。
///
/// App 启动即拉起 `SPUStandardUpdaterController`,由 Sparkle 依据 Info.plist 中的
/// `SUFeedURL` / `SUPublicEDKey` 后台定期检查 appcast(默认每天,见 `SUScheduledCheckInterval`)。
/// 更新包的 EdDSA 签名由 `SUPublicEDKey` 校验,确保即使 feed 被劫持也无法推送恶意更新。
///
/// 注意:以裸可执行文件方式 `swift run` 调试时没有完整 App 包 Info.plist,
/// Sparkle 仅会记录「缺少 feed」之类日志、不影响运行;打包后的 .app 才具备完整配置。
@MainActor
final class UpdaterViewModel: ObservableObject {
    /// 当前是否允许发起检查(正在检查/下载时为 false),用于置灰菜单项与按钮。
    @Published var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    var updater: SPUUpdater { controller.updater }

    /// 手动检查更新(菜单「检查更新…」与设置页按钮共用)。
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// 是否在后台自动检查更新,供设置页开关双向绑定。
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

/// 主菜单「检查更新…」项:检查进行中时自动置灰。
struct CheckForUpdatesMenuItem: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("检查更新…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
