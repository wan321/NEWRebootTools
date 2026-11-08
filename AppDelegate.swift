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

    /// URL Scheme 支持的动作，与 App 内按钮一一对应；whoami 只探测身份，不动设备。
    private enum RebootURLAction: String {
        /// 整机断电重启（RebootRootHelper → reboot(0)）
        case reboot
        /// 用户空间重启（RebootUserSpaceHelper → launchd userspace-reboot）
        case userspace
        /// 注销回桌面（killall SpringBoard）
        case respring
        /// 只把 root helper 跑起来读回 uid/euid，用于验证提权是否生效
        case whoami

        var displayName: String {
            switch self {
            case .reboot: return "重启设备"
            case .userspace: return "用户空间重启"
            case .respring: return "注销"
            case .whoami: return "身份探测"
            }
        }
    }

    /// 打进二进制的构建标记，方便一眼确认手机装的是哪一版。
    static let buildTag = "v7-daemon"

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
        logDiagnostic("URL received: \(url.absoluteString) → \(action.rawValue) uid=\(getuid())")

        // 先把「到底收到了哪个动作」摆在屏幕上，再执行。真机排查时这一层确认
        // 能立刻区分「快捷指令填错了」和「动作执行失败」。
        showReceiptAlert(action: action, url: url) { [weak self] in
            self?.perform(action: action)
        }
    }

    private func perform(action: RebootURLAction) {
        let deviceController = DeviceController()
        var detail: String

        if action == .whoami {
            // 身份探测只回报，不按「失败」措辞。
            _ = deviceController.probeHelperIdentity()
            let report = "exit=\(deviceController.lastExitCode)\n\(deviceController.lastLog ?? "")"
            logDiagnostic("whoami: \(report)")
            rebootURLHandled = false
            showReportAlert(title: "RebootTools \(AppDelegate.buildTag) · 身份探测", detail: report)
            return
        }

        switch action {
        case .respring:
            // 优先交给 root daemon：只有 uid 0 才能真的把 SpringBoard 杀掉。
            let daemon = DaemonManager.status()
            if daemon.alive, DaemonManager.send("respring") {
                detail = "respring: 已投递给 root daemon（\(daemon.detail)），若无效见 daemon 日志"
                break
            }
            // daemon 不在时退回 App 内 kill（mobile 下大概率 EPERM，但会如实报告）。
            _ = deviceController.respringAndReport()
            detail = "\(action.rawValue): \(String(describing: deviceController.lastLog ?? ""))"
        case .whoami:
            // 已在上面单独处理，这里只为穷尽 switch。
            detail = "whoami"
        case .reboot, .userspace:
            let daemon = DaemonManager.status()
            let command = (action == .reboot) ? "reboot" : "userspace"

            // 重启走 root daemon：这是唯一不依赖 App 自身权限的路径。
            if action == .reboot && daemon.alive {
                let sent = DaemonManager.send(command)
                detail = "daemon 在线(\(daemon.detail)) 命令投递=\(sent ? "ok" : "FAILED")"
                logDiagnostic(detail)
                // 命令生效的话设备马上就会重启，进程根本走不到这里；4 秒后还活着 = 没生效。
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    let tail = DaemonManager.logTail(DaemonManager.daemonLogPath, lines: 6)
                    self?.rebootURLHandled = false
                    self?.showFailureAlert(action: action, detail: "\(detail)\n--- daemon 日志 ---\n\(tail)")
                }
                return
            }

            let spawned = action == .reboot
                ? deviceController.rebootDevice()
                : deviceController.rebootUserspace()
            // 走到这里说明设备没有重启（重置成功的话进程早就被内核干掉了），
            // 所以不论 spawn 成功与否都要把 helper 的退出码和 stderr 显示出来。
            detail = "\(action.rawValue): spawn \(spawned ? "ok" : "FAILED") exit=\(deviceController.lastExitCode) \(String(describing: deviceController.lastLog ?? ""))"
            if action == .reboot {
                detail += "\ndaemon 状态: \(daemon.alive ? "在线" : "离线")（\(daemon.detail)）"
            }
        }

        logDiagnostic(detail)
        rebootURLHandled = false
        showFailureAlert(action: action, detail: detail)
    }

    /// 执行前的确认窗：显示收到的 URL、解析出的动作、App 的 uid。
    /// 故意不自动消失，必须点一下——之前 1 秒自动闪窗在有别的弹窗时会整个看不见，
    /// 于是"到底有没有收到 URL"永远查不清。
    private func showReceiptAlert(action: RebootURLAction, url: URL, completion: @escaping () -> Void) {
        let message = "\(url.absoluteString)\n动作：\(action.displayName)\nApp uid=\(getuid()) euid=\(geteuid())\n构建：\(AppDelegate.buildTag)"
        let alert = UIAlertController(title: "已收到 RebootTools 请求", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "执行", style: .destructive) { _ in
            completion()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.rebootURLHandled = false
        })
        guard let host = presenter() else {
            logDiagnostic("receipt alert: no presenter, executing directly")
            completion()
            return
        }
        host.present(alert, animated: true)
    }

    private func presenter() -> UIViewController? {
        return window?.rootViewController?.presentedViewController ?? window?.rootViewController
    }

    /// 失败/未生效时给出可见反馈。
    private func showFailureAlert(action: RebootURLAction, detail: String) {
        let message = "「\(action.displayName)」未能生效。\n\n\(detail)"
        let alert = UIAlertController(title: "RebootTools \(AppDelegate.buildTag)", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        alert.addAction(UIAlertAction(title: "复制详情", style: .default) { _ in
            UIPasteboard.general.string = detail
        })
        DispatchQueue.main.async {
            self.presenter()?.present(alert, animated: true)
        }
    }

    /// 只报告结果的弹窗（身份探测用），必须点「好」才能继续。
    private func showReportAlert(title: String, detail: String) {
        let alert = UIAlertController(title: title, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        alert.addAction(UIAlertAction(title: "复制详情", style: .default) { _ in
            UIPasteboard.general.string = detail
        })
        DispatchQueue.main.async {
            self.presenter()?.present(alert, animated: true)
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
