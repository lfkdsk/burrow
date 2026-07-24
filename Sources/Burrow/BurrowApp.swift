import SwiftUI

@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = StatusMonitor.shared
    @StateObject private var whitelist = WhitelistStore.shared
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup("Burrow", id: "main") {
            RootView()
                .environmentObject(monitor)
                .environmentObject(whitelist)
                .frame(minWidth: 1020, minHeight: 660)
                .onAppear { monitor.start() }
        }
        .defaultSize(width: 1180, height: 740)
        .commands {
            // 「检查更新…」置于应用菜单「关于 Burrow」下方
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem(updater: updater)
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel()
                .environmentObject(monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(whitelist)
                .environmentObject(updater)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        StatusMonitor.shared.start()
    }
}
