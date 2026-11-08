import UIKit

class RootViewController: UIViewController {

    // 定义一个闭包（接口）当桌面快捷方式被点击的时候调用
    var onClickQuickAction: ((String) -> Void)?
    
	private let settingsUtils = SettingsUtils.instance
    private let checkPermissionLabel = UILabel()
    private let respringButton = UIButton(type: .system)
    // 常驻诊断面板：启动即自动探测 root 能力，结果直接显示在屏幕上，
    // 不依赖 URL Scheme 是否送达、也不依赖弹窗是否被看见。
    private let diagTextView = UITextView()
    // v8：安装 root 守护进程从「启动自动跑」改成「按钮显式触发」。
    private let installDaemonButton = UIButton(type: .system)
    private var installingDaemon = false
    // v11：身份探测从「启动自动跑」改成按钮触发（启动阶段不再 spawn 任何子进程）。
    private let probeButton = UIButton(type: .system)
    private var probing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        DaemonManager.bootLog("viewDidLoad")
        
        self.title = NSLocalizedString("CFBundleDisplayName", comment: "")

        // 设置ViewController的背景颜色
        self.view.backgroundColor = UIColor.systemBackground

        // icon
        let iconImageView = UIImageView()

        if #available(iOS 15.0, *) {
            iconImageView.image = UIImage(systemName: "power.circle.fill")
            iconImageView.tintColor = UIColor(hex: "#32A5E7")
        } else {
            let appIcon = UIImage(named: "AppIcon")
            iconImageView.image = appIcon
        }
        // 无障碍标签
        iconImageView.isAccessibilityElement = true // 声明这是一个可访问性元素
        iconImageView.accessibilityLabel = NSLocalizedString("CFBundleDisplayName", comment: "")

        // 禁用自动调整大小
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        // 设置图片适应方式
        iconImageView.contentMode = .scaleAspectFit

        // 检查权限
        checkPermissionLabel.translatesAutoresizingMaskIntoConstraints = false
        checkPermissionLabel.textAlignment = .center  // 设置文本居中

        let enable = settingsUtils.checkInstallPermission()

        if(enable) {
            checkPermissionLabel.text = NSLocalizedString("Install_With_TrollStore_text", comment: "")
            checkPermissionLabel.textColor = UIColor.green
            checkPermissionLabel.isHidden = !settingsUtils.getShowRootText()
        } else {
            checkPermissionLabel.text = NSLocalizedString("Need_Install_With_TrollStore_text", comment: "")
            checkPermissionLabel.textColor = UIColor.red
        }

        // 重启按钮
        let rebootButton = UIButton(type: .system)
        if #available(iOS 15.0, *) {
			rebootButton.configuration = .filled()
			rebootButton.setTitle(NSLocalizedString("Reboot_Device_text", comment: ""), for: .normal)
		} else {
			// iOS 14 及以下版本 没这效果只能硬凑了
			rebootButton.backgroundColor = UIColor.systemBlue
            rebootButton.layer.cornerRadius = 8
            rebootButton.clipsToBounds = true
            rebootButton.setTitle(NSLocalizedString("Reboot_Device_text", comment: ""), for: .normal)
            rebootButton.setTitleColor(.white, for: .normal)
            if !enable {
                // 禁用状态按钮的样子 照顾一下iOS14 用户 但是又没权限的情况，貌似基本不存在
                rebootButton.backgroundColor = UIColor.lightGray
                rebootButton.setTitleColor(.darkGray, for: .normal)
            }
		}

        rebootButton.translatesAutoresizingMaskIntoConstraints = false
        // 添加点击事件
        rebootButton.addTarget(self, action: #selector(onClickRebootButton), for: .touchUpInside)
        rebootButton.isEnabled = enable // 无权限的时候不允许点击

        // 重启用户空间
        let rebootUserSpaceButton = UIButton(type: .system)
        if #available(iOS 15.0, *) {
            rebootUserSpaceButton.configuration = .filled()
            rebootUserSpaceButton.setTitle(NSLocalizedString("Reboot_UserSpace_Device_text", comment: ""), for: .normal)
        } else {
            // iOS 14 及以下版本 没这效果只能硬凑了
            rebootUserSpaceButton.backgroundColor = UIColor.systemBlue
            rebootUserSpaceButton.layer.cornerRadius = 8
            rebootUserSpaceButton.clipsToBounds = true
            rebootUserSpaceButton.setTitle(NSLocalizedString("Reboot_UserSpace_Device_text", comment: ""), for: .normal)
            rebootUserSpaceButton.setTitleColor(.white, for: .normal)
            if !enable {
                // 禁用状态按钮的样子 照顾一下iOS14 用户 但是又没权限的情况，貌似基本不存在
                rebootUserSpaceButton.backgroundColor = UIColor.lightGray
                rebootUserSpaceButton.setTitleColor(.darkGray, for: .normal)
            }
        }
        rebootUserSpaceButton.translatesAutoresizingMaskIntoConstraints = false
        // 添加点击事件
        rebootUserSpaceButton.addTarget(self, action: #selector(onClickRebootUserSpaceButton), for: .touchUpInside)
        rebootUserSpaceButton.isEnabled = enable // 无权限的时候不允许点击
        
        // Respring
        respringButton.setTitle(NSLocalizedString("Respring_text", comment: ""), for: .normal)
        respringButton.translatesAutoresizingMaskIntoConstraints = false
        respringButton.addTarget(self, action: #selector(onClickRespringButton), for: .touchUpInside)
        respringButton.isEnabled = enable // 无权限的时候不允许点击
        respringButton.isHidden = !settingsUtils.getEnableRespringFunction()
        
        // 添加设置项
        let settingsButton = UIButton(type: .system)
        settingsButton.setTitle(NSLocalizedString("Settings_text", comment: ""), for: .normal)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addTarget(self, action: #selector(onClickSettingsButton), for: .touchUpInside)
        // 设置图标
        let settingsButtonIcon = UIImage(systemName: "gearshape")
        settingsButton.setImage(settingsButtonIcon, for: .normal)
        // 调整图标和文本之间的间距
        settingsButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 0)

		// 向View中添加控件
        self.view.addSubview(iconImageView)
        self.view.addSubview(checkPermissionLabel)
        self.view.addSubview(rebootButton)
        self.view.addSubview(rebootUserSpaceButton)
        self.view.addSubview(respringButton)
        self.view.addSubview(settingsButton)

        // 诊断面板（可选中复制）
        diagTextView.translatesAutoresizingMaskIntoConstraints = false
        diagTextView.isEditable = false
        diagTextView.isSelectable = true
        diagTextView.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        diagTextView.textColor = .secondaryLabel
        diagTextView.backgroundColor = .secondarySystemBackground
        diagTextView.layer.cornerRadius = 6
        diagTextView.text = "诊断信息加载中…"
        diagTextView.textContainerInset = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        self.view.addSubview(diagTextView)

        // 手动安装/更新 root 守护进程（v8 起不再在启动时自动执行）
        installDaemonButton.translatesAutoresizingMaskIntoConstraints = false
        installDaemonButton.setTitle("安装 root 守护进程", for: .normal)
        installDaemonButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        installDaemonButton.backgroundColor = .secondarySystemBackground
        installDaemonButton.layer.cornerRadius = 6
        installDaemonButton.addTarget(self, action: #selector(installDaemonTapped), for: .touchUpInside)
        self.view.addSubview(installDaemonButton)

        // v11：身份探测按钮（启动时不再自动 spawn）
        probeButton.translatesAutoresizingMaskIntoConstraints = false
        probeButton.setTitle("运行 root 探测", for: .normal)
        probeButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        probeButton.backgroundColor = .secondarySystemBackground
        probeButton.layer.cornerRadius = 6
        probeButton.addTarget(self, action: #selector(probeTapped), for: .touchUpInside)
        self.view.addSubview(probeButton)

        // AutoLayout
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 100),  // 设置宽度
            iconImageView.heightAnchor.constraint(equalToConstant: 100), // 设置高度
            iconImageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), // 水平居中
            iconImageView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 100),

            checkPermissionLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), // 水平居中
            checkPermissionLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 30), // 在 iconImageView 底部，间隔 20 点
            checkPermissionLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20), // 左侧边距
            checkPermissionLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20), // 右侧边距

            rebootButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), // 水平居中
            rebootButton.heightAnchor.constraint(equalToConstant: 50),
            rebootButton.topAnchor.constraint(equalTo: checkPermissionLabel.bottomAnchor, constant: 30),
            rebootButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 50), // 左侧边距
            rebootButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -50), // 右侧边距
            
            rebootUserSpaceButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), // 水平居中
            rebootUserSpaceButton.heightAnchor.constraint(equalToConstant: 50),
            rebootUserSpaceButton.topAnchor.constraint(equalTo: rebootButton.bottomAnchor, constant: 30),
            rebootUserSpaceButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 50), // 左侧边距
            rebootUserSpaceButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -50), // 右侧边距

            respringButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), // 水平居中
            respringButton.heightAnchor.constraint(equalToConstant: 50),
            respringButton.topAnchor.constraint(equalTo: rebootUserSpaceButton.bottomAnchor, constant: 20),
            respringButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 50), // 左侧边距
            respringButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -50), // 右侧边距

			settingsButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), // 水平居中
            settingsButton.heightAnchor.constraint(equalToConstant: 50),
            settingsButton.topAnchor.constraint(equalTo: respringButton.bottomAnchor, constant: 30),
            settingsButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 50), // 左侧边距
            settingsButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -50), // 右侧边距

            diagTextView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 12),
            diagTextView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12),
            diagTextView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            diagTextView.heightAnchor.constraint(equalToConstant: 168),

            installDaemonButton.leadingAnchor.constraint(equalTo: diagTextView.leadingAnchor),
            installDaemonButton.trailingAnchor.constraint(equalTo: diagTextView.trailingAnchor),
            installDaemonButton.heightAnchor.constraint(equalToConstant: 30),
            installDaemonButton.bottomAnchor.constraint(equalTo: diagTextView.topAnchor, constant: -6),

            probeButton.leadingAnchor.constraint(equalTo: diagTextView.leadingAnchor),
            probeButton.trailingAnchor.constraint(equalTo: diagTextView.trailingAnchor),
            probeButton.heightAnchor.constraint(equalToConstant: 30),
            probeButton.bottomAnchor.constraint(equalTo: installDaemonButton.topAnchor, constant: -6)
        ])

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 标题带上构建标记：真机上一眼能确认装的是哪一版，避免"改了没生效"的误判。
        self.title = "\(NSLocalizedString("CFBundleDisplayName", comment: "")) · \(AppDelegate.buildTag)"
        
        // 桌面快捷方式的回调
        onClickQuickAction = { [weak self] actionType in

            guard let quickAction = SettingsUtils.QuickActionType(rawValue: actionType) else {
                NSLog("Invalid quick action type: \(actionType)")
                return
            }
            
            switch quickAction {
            case .Reboot:
                self?.onClickRebootButton()
            case .Respring:
                self?.onClickRespringButton()
            case .CancelTimer:
                self?.onClickCloseTimerQuickAction()
            }
        }
        
        // 打开 app 时的自动操作。若本次是由 reboottools://reboot 启动，
        // 跳过用户原有的自动操作设置，避免和 URL 请求重复触发。
        let launchedByRebootURL = (UIApplication.shared.delegate as? AppDelegate)?.launchedByRebootURL ?? false
        if !launchedByRebootURL && settingsUtils.getEnableAction() && settingsUtils.getOpenApplicationAction() {
            let action = settingsUtils.getAction()
            switch action {
            case .Reboot:
                self.onClickRebootButton()
            case .Respring:
                self.onClickRespringButton()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        RTTraceLine("viewDidAppear")
        DaemonManager.bootLog("viewDidAppear")
        // v11：启动阶段**不做任何 spawn / 不做后台探测**。
        // v6..v10 的「点开就闪退」就发生在启动自动探测的后台任务里
        // （crash 线程 com.apple.root.user-initiated-qos，回溯在 libobjc 释放对象时）。
        // 所以启动只渲染纯 Swift 的静态信息，身份探测改成按钮显式触发。
        renderDiagnostics(probeResult: nil)
    }

    /// 纯静态渲染：只读心跳/日志文件，不 spawn 任何子进程。
    private func renderDiagnostics(probeResult: String?) {
        let build = AppDelegate.buildTag
        let appUid = getuid()
        let appEuid = geteuid()
        let permission = settingsUtils.checkInstallPermission()
        let status = DaemonManager.status()
        let hasB64 = Bundle.main.path(forResource: "RebootDaemon", ofType: "b64") != nil
        let hint = status.alive ? "" : "提示：daemon 离线 → 点「安装 root 守护进程」\n"

        var text = """
        构建 \(build)
        App uid=\(appUid) euid=\(appEuid)
        权限检查(可写 /var/mobile/Library/Preferences)=\(permission)
        daemon \(status.alive ? "在线" : "离线") \(status.detail)  资源 RebootDaemon.b64=\(hasB64 ? "在" : "缺失")
        \(hint)
        """
        if let p = probeResult {
            text += "身份探测 \(p)\n"
        } else {
            text += "身份探测 未运行（点上面「运行 root 探测」）\n"
        }
        // 自检记录放在最前面：面板放不下时用户不用滚动就能看到崩溃现场。
        text += """
        --- rt-trace 尾部 ---
        \(RootViewController.rtTraceTail())
        --- probe.log 尾部 ---
        \(RootViewController.probeTail())
        --- install.log ---
        \(DaemonManager.logTail(DaemonManager.installLogPath, lines: 2))
        --- daemon.log ---
        \(DaemonManager.logTail(DaemonManager.daemonLogPath, lines: 2))
        --- URL 日志尾部 ---
        \(RootViewController.logTail())
        --- 启动面包屑 ---
        \(RootViewController.bootTail())
        """
        diagTextView.text = text
    }

    /// 读 C 级追踪文件（/tmp/rt-trace.log）尾部：v12 的 probe.log 一行都没写下来，
    /// 说明崩溃发生在「连第一条 ObjC 日志都来不及写」的位置，所以这一版看这里。
    private static func rtTraceTail() -> String {
        let path = String(cString: RTTracePath())
        guard !path.isEmpty else { return "(追踪器未初始化)" }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty else {
            return "(无追踪记录 path=\(path))"
        }
        return content.split(separator: "\n").suffix(14).joined(separator: "\n")
    }

    /// 读 Documents/probe.log 尾部：v12 自检阶梯的最后几行，
    /// 「运行 root 探测」闪退后重新打开 App，看这里就能知道死在哪一级。
    private static func probeTail() -> String {
        let file = NSHomeDirectory() + "/Documents/probe.log"
        guard let content = try? String(contentsOfFile: file, encoding: .utf8), !content.isEmpty else {
            return "(无自检记录)"
        }
        return content.split(separator: "\n").suffix(12).joined(separator: "\n")
    }

    /// 显式触发的身份探测（不改动设备）。崩溃排查用：进入前后都写启动面包屑，
    /// 若这一下闪退，下次打开 App 的面包屑里会留下 probe-start。
    @objc private func probeTapped() {
        // v13：这一行必须是函数体第一句。如果连它都没出现在 rt-trace.log 里，
        // 说明崩溃发生在按钮回调之前（不是我们的代码）。
        RTTraceLine("probeTapped enter")
        guard !probing else { return }
        probing = true
        probeButton.isEnabled = false
        probeButton.setTitle("探测中…", for: .normal)
        RTTraceLine("probeTapped ui updated")
        DaemonManager.bootLog("probe-start")
        RTTraceLine("probeTapped bootLog written")

        DispatchQueue.global(qos: .userInitiated).async {
            RTTraceLine("bg closure entered")
            // v14：Swift 侧不碰 ObjC 对象，只调一个纯 C 入口。
            // v13 证明崩溃卡在「创建 DeviceController / 调它的方法」这段，
            // 所以 alloc/init/selfTest 全部收进 C 函数里，界面上只拿回一个返回码。
            let rc = RTDoSelfTest()
            RTTraceLine("RTDoSelfTest returned rc=\(rc)")
            let result = "C 入口自检 rc=\(rc)（明细见 rt-trace 尾部）"
            DaemonManager.bootLog("probe-done")

            DispatchQueue.main.async {
                self.probing = false
                self.probeButton.isEnabled = true
                self.probeButton.setTitle("运行 root 探测", for: .normal)
                self.renderDiagnostics(probeResult: result)
            }
        }
    }

    /// 手动安装 root 守护进程：只落盘、不调用 launchctl（见 DaemonManager.install 注释）。
    @objc private func installDaemonTapped() {
        RTTraceLine("installDaemonTapped enter")
        guard !installingDaemon else { return }
        installingDaemon = true
        installDaemonButton.isEnabled = false
        installDaemonButton.setTitle("安装中…", for: .normal)
        DaemonManager.bootLog("install-daemon tapped")

        DispatchQueue.global(qos: .userInitiated).async {
            RTTraceLine("install bg closure entered")
            let (spawned, exit, log) = DaemonManager.install(force: true, load: false)
            RTTraceLine("install returned spawn=\(spawned) exit=\(exit)")
            let first = log.split(separator: "\n").first.map(String.init) ?? log
            let result = "安装 spawn=\(spawned ? "ok" : "FAILED") exit=\(exit) \(first)"
            DaemonManager.bootLog("install-daemon done: \(result)")

            DispatchQueue.main.async {
                self.installingDaemon = false
                self.installDaemonButton.isEnabled = true
                self.installDaemonButton.setTitle("安装 root 守护进程", for: .normal)
                self.diagTextView.text = "\(result)\n\n正在重新探测…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.renderDiagnostics(probeResult: nil)
                }
            }
        }
    }

    /// 读取 Documents/boot.log 的最后几行，看启动流程走到哪一步（闪退排查用）。
    private static func bootTail() -> String {
        let file = NSHomeDirectory() + "/Documents/boot.log"
        guard let content = try? String(contentsOfFile: file, encoding: .utf8), !content.isEmpty else {
            return "(无启动记录)"
        }
        return content.split(separator: "\n").suffix(5).map { line -> String in
            let parts = line.split(separator: " ", maxSplits: 1)
            return parts.count == 2 ? String(parts[1]) : String(line)
        }.joined(separator: " → ")
    }

    /// 读取 Documents/reboottools-url.log 的最后几行，判断 URL 到底有没有送达。
    private static func logTail() -> String {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "(无 Documents)"
        }
        let file = dir.appendingPathComponent("reboottools-url.log")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else {
            return "(无 URL 记录)"
        }
        return content.split(separator: "\n").suffix(3).joined(separator: "\n")
    }

    @objc func onClickRebootButton() {
        
        if settingsUtils.getShowAlertBeforeAction() {
            // 创建 UIAlertController
            let alertController = UIAlertController(title: nil, message: String.localizedStringWithFormat(NSLocalizedString("Action_Alert", comment: ""), NSLocalizedString("Reboot_Device_text", comment: "")), preferredStyle: .alert)
            
            // 创建 "确定" 按钮（红色）
            let confirmAction = UIAlertAction(title: NSLocalizedString("Confirm_text", comment: ""), style: .destructive) { _ in
                self.rebootDevice()
            }
            
            // 创建 "取消" 按钮
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel_text", comment: ""), style: .cancel) { _ in
                //
            }
            
            // 添加按钮到 UIAlertController
            alertController.addAction(confirmAction)
            alertController.addAction(cancelAction)
            
            // 显示弹窗
            self.present(alertController, animated: true, completion: nil)
        } else {
            self.rebootDevice()
        }
        
    }
    
    @objc func onClickRebootUserSpaceButton() {
        
        if settingsUtils.getShowAlertBeforeAction() {
            // 创建 UIAlertController
            let alertController = UIAlertController(title: nil, message: String.localizedStringWithFormat(NSLocalizedString("Action_Alert", comment: ""), NSLocalizedString("Reboot_UserSpace_Device_text", comment: "")), preferredStyle: .alert)
            
            // 创建 "确定" 按钮（红色）
            let confirmAction = UIAlertAction(title: NSLocalizedString("Confirm_text", comment: ""), style: .destructive) { _ in
                self.rebootUserSpaceDevice()
            }
            
            // 创建 "取消" 按钮
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel_text", comment: ""), style: .cancel) { _ in
                //
            }
            
            // 添加按钮到 UIAlertController
            alertController.addAction(confirmAction)
            alertController.addAction(cancelAction)
            
            // 显示弹窗
            self.present(alertController, animated: true, completion: nil)
        } else {
            self.rebootUserSpaceDevice()
        }
        
    }
    
    private func rebootDevice() {
        let time = settingsUtils.getTime()
        if settingsUtils.getEnableAction() && time > 0 {
            showCountdownAlert(actionName: NSLocalizedString("Reboot_Device_text", comment: ""), countdownSeconds: time) {
                //计时器结束的操作
                let deviceController = DeviceController()
                deviceController.rebootDevice()
            }
        } else {
            let deviceController = DeviceController()
            deviceController.rebootDevice()
        }
        
    }
    
    private func rebootUserSpaceDevice() {
        let time = settingsUtils.getTime()
        if settingsUtils.getEnableAction() && time > 0 {
            showCountdownAlert(actionName: NSLocalizedString("Reboot_UserSpace_Device_text", comment: ""), countdownSeconds: time) {
                //计时器结束的操作
                let deviceController = DeviceController()
                deviceController.rebootUserspace()
            }
        } else {
            let deviceController = DeviceController()
            deviceController.rebootUserspace()
        }
        
    }
    
    @objc func onClickRespringButton() {
        
        if settingsUtils.getShowAlertBeforeAction() {
            // 创建 UIAlertController
            let alertController = UIAlertController(title: nil, message: String.localizedStringWithFormat(NSLocalizedString("Action_Alert", comment: ""), NSLocalizedString("Respring_text", comment: "")), preferredStyle: .alert)
            
            // 创建 "确定" 按钮（红色）
            let confirmAction = UIAlertAction(title: NSLocalizedString("Confirm_text", comment: ""), style: .destructive) { _ in
                self.respring()
            }
            
            // 创建 "取消" 按钮
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel_text", comment: ""), style: .cancel) { _ in
                //
            }
            
            // 添加按钮到 UIAlertController
            alertController.addAction(confirmAction)
            alertController.addAction(cancelAction)
            
            // 显示弹窗
            self.present(alertController, animated: true, completion: nil)
        } else {
            self.respring()
        }
        
    }
    
    private func respring() {
        let time = settingsUtils.getTime()
        if settingsUtils.getEnableAction() && time > 0 {
            showCountdownAlert(actionName: NSLocalizedString("Respring_text", comment: ""), countdownSeconds: time) {
                //计时器结束的操作
                let deviceController = DeviceController()
                deviceController.respring()
            }
        } else {
            let deviceController = DeviceController()
            deviceController.respring()
        }
        
    }

    @objc func onClickSettingsButton() {
		let settingsViewController = SettingsViewController()
        // 注册监听器
        settingsViewController.onSettingsChanged = { [weak self] in
            self?.updateUI()
        }
        // 嵌入到导航控制器
        let navController = UINavigationController(rootViewController: settingsViewController)
        // 设置导航栏完成按钮
        let doneButton = UIBarButtonItem(title: NSLocalizedString("Done_text", comment: ""), style: .done, target: self, action: #selector(onClickDoneButton))
        settingsViewController.navigationItem.rightBarButtonItem = doneButton
        // 设置模态视图的显示样式
        navController.modalPresentationStyle = .pageSheet
        navController.modalTransitionStyle = .coverVertical

        // 显示带导航栏的 SettingsViewController
        present(navController, animated: true, completion: nil)

	}

	@objc func onClickDoneButton() {
        // 关闭模态视图
        dismiss(animated: true, completion: nil)
    }
    
    private func showCountdownAlert(actionName: String, countdownSeconds: Int, action: @escaping () -> Void) {
        guard countdownSeconds > 0 else {
            print("Invalid countdownSeconds: \(countdownSeconds). It should be greater than 0.")
            return
        }
        
        // 初始化倒计时变量
        var remainingSeconds = countdownSeconds
        var timer: Timer?

        // 创建 UIAlertController
        let alertController = UIAlertController(
            title: String.localizedStringWithFormat(NSLocalizedString("Countdown_Title_text", comment: ""), actionName),
            message: String.localizedStringWithFormat(NSLocalizedString("Countdown_Message_text", comment: ""), remainingSeconds),
            preferredStyle: .alert
        )
        
        // 添加取消按钮
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel_text", comment: ""), style: .destructive) { _ in
            timer?.invalidate() // 停止计时器
        }
        alertController.addAction(cancelAction)
        
        // 显示弹窗
        DispatchQueue.main.async {
            self.present(alertController, animated: true, completion: nil)
        }

        // 创建 Timer，倒计时
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard remainingSeconds > 0 else { // 确保倒计时不为负数
                timer?.invalidate()
                return
            }
            
            remainingSeconds -= 1
            DispatchQueue.main.async {
                alertController.message = String.localizedStringWithFormat(NSLocalizedString("Countdown_Message_text", comment: ""), remainingSeconds)
            }
            
            // 倒计时结束，执行操作
            if remainingSeconds <= 0 {
                timer?.invalidate() // 停止计时器
                DispatchQueue.main.async {
                    alertController.dismiss(animated: true, completion: nil) // 关闭弹窗
                    action() // 执行操作
                }
            }
        }
    }

    
    private func updateUI() { // 因为设置更改 更新界面
        checkPermissionLabel.isHidden = !settingsUtils.getShowRootText()
        respringButton.isHidden = !settingsUtils.getEnableRespringFunction()
    }
    
    private func onClickCloseTimerQuickAction() {
        settingsUtils.setEnableAction(value: false)
        // 显示一个弹窗 提示用户倒计时器已被禁用
        let alertController = UIAlertController(title: nil, message: NSLocalizedString("Timer_Closed_text", comment: ""), preferredStyle: .alert)
        let dismissAction = UIAlertAction(title: NSLocalizedString("Dismiss_text", comment: ""), style: .cancel) { _ in
            //
        }
        // 添加按钮到 UIAlertController
        alertController.addAction(dismissAction)
        // 显示弹窗
        self.present(alertController, animated: true, completion: nil)
        settingsUtils.configQuickActions(application: UIApplication.shared)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
