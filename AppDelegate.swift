import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?
    var mainViewController: RootViewController?
    // 加载配置文件
    let settingsUtils = SettingsUtils.instance
    // 用于存储启动时的快捷方式
    var pendingQuickAction: UIApplicationShortcutItem?

    // URL Scheme: reboottools://reboot | reboottools://userspace | reboottools://respring
    private var pendingRebootURL: URL?
    private var rebootURLHandled = false
    // RootViewController 用此标记跳过原有的“打开 App 自动执行动作”，避免重复重启。
    var launchedByRebootURL = false

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 必须在创建 RootViewController 之前设置标记，避免冷启动时先触发普通启动动作。
        if let url = launchOptions?[.url] as? URL, isRebootURL(url) {
            pendingRebootURL = url
            launchedByRebootURL = true
        }

		window = UIWindow(frame: UIScreen.main.bounds)
        mainViewController = RootViewController()
        guard let mainVC = mainViewController else {
            fatalError("Failed to initialize RootViewController")
        }
        window!.rootViewController = UINavigationController(rootViewController: mainVC)
		window!.makeKeyAndVisible()
        settingsUtils.configQuickActions(application: application)
        
        // 检查是否通过快捷方式启动
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            pendingQuickAction = shortcutItem // 保存快捷方式
        }

		return true
	}
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // 处理启动时的快捷方式
        if let shortcutItem = pendingQuickAction {
            handleQuickActionFromLaunch(shortcutItem)
            pendingQuickAction = nil // 清除状态
        }

        // 处理通过 URL Scheme 冷启动的请求。
        if let url = pendingRebootURL {
            pendingRebootURL = nil
            executeRebootURL(url)
        }
    }

    // App 已经运行时收到 URL Scheme。
    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard isRebootURL(url) else { return false }

        // 无论冷启动还是从后台被唤起，都要打标记，避免 RootViewController 的
        // “打开 App 自动操作” 与 URL 请求重复触发（例如自动操作设成注销时会被误触发）。
        launchedByRebootURL = true

        if application.applicationState == .active {
            executeRebootURL(url)
        } else {
            pendingRebootURL = url
        }
        return true
    }

    /// URL Scheme 支持的三级动作，与 App 内三个按钮一一对应。
    private enum RebootURLAction: String {
        /// 整机断电重启（RebootRootHelper → reboot(0)）
        case reboot
        /// 用户空间重启（RebootUserSpaceHelper → launchd userspace-reboot）
        case userspace
        /// 注销回桌面（killall SpringBoard）
        case respring

        var displayName: String {
            switch self {
            case .reboot: return "重启设备"
            case .userspace: return "用户空间重启"
            case .respring: return "注销"
            }
        }
    }

    private func rebootURLAction(from url: URL) -> RebootURLAction? {
        guard url.scheme?.lowercased() == "reboottools" else { return nil }
        guard let host = url.host?.lowercased(), let action = RebootURLAction(rawValue: host) else { return nil }
        guard url.path.isEmpty || url.path == "/" else { return nil }
        return action
    }

    private func isRebootURL(_ url: URL) -> Bool {
        return rebootURLAction(from: url) != nil
    }

    private func executeRebootURL(_ url: URL) {
        guard let action = rebootURLAction(from: url), !rebootURLHandled else { return }
        rebootURLHandled = true
        logDiagnostic("URL received: \(url.absoluteString) → \(action.rawValue)")

        // 留出时间让 App 完成前台切换，再调用对应的 Helper。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let deviceController = DeviceController()

            switch action {
            case .respring:
                // 注销不经过 Helper，直接杀 SpringBoard；此调用内部会 exit(0)。
                self.logDiagnostic("respring: sending SIGTERM to SpringBoard")
                deviceController.respring()
            case .reboot, .userspace:
                let success = action == .reboot
                    ? deviceController.rebootDevice()
                    : deviceController.rebootUserspace()
                self.logDiagnostic("\(action.rawValue): helper \(success ? "spawn ok" : "spawn FAILED")")

                // 如果 Helper 启动失败，弹出提示（原实现是静默失败），并允许再次调用 URL 重试。
                if !success {
                    self.rebootURLHandled = false
                    self.showFailureAlert(action: action)
                }
            }
        }
    }

    /// 失败时给出可见反馈：helper 起不来时（常见于缺少 platform-application 或 reboot 权限）
    /// 原来只在 NSLog 里留一行，侧载环境看不到，表现为“点了什么都没发生”。
    private func showFailureAlert(action: RebootURLAction) {
        let message = "「\(action.displayName)」未能执行：无法启动 Helper（可能缺少相应权限）。"
        let alert = UIAlertController(title: "RebootTools", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        DispatchQueue.main.async {
            let presenter = self.window?.rootViewController?.presentedViewController
                ?? self.window?.rootViewController
            presenter?.present(alert, animated: true)
        }
    }

    /// 把 URL 触发过程写进 Documents/reboottools-url.log，便于在侧载环境里离线排查。
    private func logDiagnostic(_ line: String) {
        NSLog("[RebootTools Shortcuts] %@", line)
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let file = dir.appendingPathComponent("reboottools-url.log")
        let formatter = ISO8601DateFormatter()
        let text = "\(formatter.string(from: Date())) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file, options: .atomic)
        }
    }
    
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let navController = window?.rootViewController as? UINavigationController else {
            completionHandler(false)
            return
        }

        // 检查是否有模态视图被显示 主要用来处理设置界面打开的时候返回桌面再按快捷方式无效的问题
        if let presentedVC = navController.presentedViewController {
            print("Modal view detected. Dismissing before executing quick action.")
            presentedVC.dismiss(animated: true) { [weak self] in
                self?.handleQuickAction(shortcutItem.type, navController: navController, completionHandler: completionHandler)
            }
        } else {
            // 没有模态视图，直接执行快捷方式逻辑 在主界面 直接执行快捷操作
            handleQuickAction(shortcutItem.type, navController: navController, completionHandler: completionHandler)
        }
    }
    
    private func handleQuickActionFromLaunch(_ shortcutItem: UIApplicationShortcutItem) {
        guard let navController = window?.rootViewController as? UINavigationController else {
            print("Failed to handle quick action: NavigationController not found.")
            return
        }

        handleQuickAction(shortcutItem.type, navController: navController) { success in
            print("Quick action from launch handled: \(success)")
        }
    }

    private func handleQuickAction(_ actionType: String, navController: UINavigationController, completionHandler: @escaping (Bool) -> Void) {
        guard let quickAction = SettingsUtils.QuickActionType(rawValue: actionType) else {
            completionHandler(false)
            return
        }
        
        // 优先处理 CancelTimer 快捷方式 不然就没办法从桌面快捷方式取消计时器了
        if quickAction == .CancelTimer {
            SettingsUtils.instance.setEnableAction(value: false)
            SettingsUtils.instance.configQuickActions(application: UIApplication.shared)
        }

        // 找到 RootViewController 并执行快捷方式
        if let rootVC = navController.topViewController as? RootViewController {
            rootVC.onClickQuickAction?(actionType)
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }



}
