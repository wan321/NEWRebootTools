import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?
    var mainViewController: RootViewController?
    // 加载配置文件
    let settingsUtils = SettingsUtils.instance
    // 用于存储启动时的快捷方式
    var pendingQuickAction: UIApplicationShortcutItem?

    // URL Scheme: reboottools://reboot
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

        if application.applicationState == .active {
            executeRebootURL(url)
        } else {
            pendingRebootURL = url
        }
        return true
    }

    private func isRebootURL(_ url: URL) -> Bool {
        return url.scheme?.lowercased() == "reboottools"
            && url.host?.lowercased() == "reboot"
            && (url.path.isEmpty || url.path == "/")
    }

    private func executeRebootURL(_ url: URL) {
        guard isRebootURL(url), !rebootURLHandled else { return }
        rebootURLHandled = true

        // 留出时间让 App 完成前台切换，再调用原项目的 Root Helper。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let deviceController = DeviceController()
            let success = deviceController.rebootDevice()
            NSLog("[RebootTools Shortcuts] reboot request: %@", success ? "accepted" : "failed")

            // 如果 Root Helper 启动失败，允许用户再次调用 URL 重试。
            if !success {
                self.rebootURLHandled = false
            }
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
