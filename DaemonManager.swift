import Foundation

/// 与常驻 root 守护进程 RebootDaemon 通信的桥。
///
/// 设计要点：App 永远以 mobile(501) 运行，抬权限要靠 persona 覆盖、每次都赌一把。
/// 所以 root 能力被固化到一个 launchd 常驻进程里（`/usr/libexec/RebootDaemon`，
/// 由 `/Library/LaunchDaemons/com.wan.reboottools.daemon.plist` 以 root 拉起），
/// App 只跟它交换两个文件：
///   cmd       —— App 写入动作（reboot / respring / ping）
///   heartbeat —— daemon 每秒刷新（uid、pid、时间戳），App 据此判断它是否在线
@objcMembers
final class DaemonManager: NSObject {

    static let baseDir = "/var/mobile/Library/Caches/com.wan.reboottools"
    static let cmdPath = DaemonManager.baseDir + "/cmd"
    static let heartbeatPath = DaemonManager.baseDir + "/heartbeat"
    static let installLogPath = DaemonManager.baseDir + "/install.log"
    static let daemonLogPath = DaemonManager.baseDir + "/daemon.log"

    struct Status {
        let alive: Bool
        let detail: String
    }

    /// 本次启动内只尝试安装一次，避免每次切前台都 spawn 一个 root 进程。
    private static var installAttempted = false

    static func status() -> Status {
        guard let text = try? String(contentsOfFile: heartbeatPath, encoding: .utf8),
              !text.isEmpty else {
            return Status(alive: false, detail: "无心跳文件")
        }

        var uid = "?"
        var ts: Double = 0
        for field in text.split(separator: " ") {
            let kv = field.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            if kv[0] == "uid" { uid = String(kv[1]) }
            if kv[0] == "ts" { ts = Double(kv[1]) ?? 0 }
        }

        let age = Date().timeIntervalSince1970 - ts
        // daemon 每秒刷新一次，超过 12 秒没更新就认为它已经不在（或被系统杀掉）。
        let alive = age >= -5 && age < 12
        return Status(alive: alive, detail: "uid=\(uid) age=\(Int(age))s")
    }

    /// 把随包的 base64 资源还原成可执行文件，落到 mobile 可写的缓存目录。
    /// v9：App 包里不再出现裸的 daemon Mach-O——TrollStore 安装时要重签包内可执行文件，
    /// v7 多塞一个后点开就闪退，所以改为安装时解码。
    static func stageDaemonBinary() -> (path: String?, message: String) {
        let bundle = Bundle.main
        guard let b64 = bundle.path(forResource: "RebootDaemon", ofType: "b64"),
              let text = try? String(contentsOfFile: b64, encoding: .utf8) else {
            return (nil, "包内缺少 RebootDaemon.b64")
        }
        let cleaned = text.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: cleaned), !data.isEmpty else {
            return (nil, "base64 解码失败（数据为空或格式错）")
        }
        do {
            try FileManager.default.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
        } catch {
            return (nil, "建目录失败: \(error.localizedDescription)")
        }
        let stagePath = baseDir + "/RebootDaemon.staged"
        do {
            try data.write(to: URL(fileURLWithPath: stagePath), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagePath)
        } catch {
            return (nil, "写临时文件失败: \(error.localizedDescription)")
        }
        return (stagePath, "解码 \(data.count) 字节")
    }

    /// 尝试用 root helper 安装/更新 daemon。返回 (spawn 是否成功, exit, 日志)。
    /// v8：默认只落盘、不调用 launchctl（load = false），因为「App 启动即 spawn 一个
    /// 以 root 跑的 launchctl」是 v7 点开就闪退的头号嫌疑。activate 交给下次开机。
    static func install(force: Bool = false, load: Bool = false) -> (Bool, Int, String) {
        if installAttempted && !force {
            return (false, -1, "本次启动已尝试过安装")
        }
        installAttempted = true

        let bundle = Bundle.main
        let (staged, stageMsg) = stageDaemonBinary()
        guard let daemonPath = staged else {
            return (false, -1, stageMsg)
        }
        guard let plist = bundle.path(forResource: "com.wan.reboottools.daemon", ofType: "plist") else {
            return (false, -1, "包内缺少 launchd plist")
        }

        let controller = DeviceController()
        let ok = controller.installRootDaemon(daemonPath, plistPath: plist, load: load)
        let log = "\(stageMsg) | \(controller.lastLog ?? "")"
        return (ok, Int(controller.lastExitCode), log)
    }

    /// 启动阶段面包屑：v7 在真机上点开就闪退，而闪退前的最后一行只能靠这个留下痕迹。
    /// 每次冷启动重写，避免历史噪音。
    static func bootLog(_ stage: String, reset: Bool = false) {
        let path = NSHomeDirectory() + "/Documents/boot.log"
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, stage)
        if reset || !FileManager.default.fileExists(atPath: path) {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8) ?? Data())
            fh.closeFile()
        }
    }

    /// 给 daemon 投递命令；daemon 会立刻删掉命令文件，所以这是"一次性"的。
    @discardableResult
    static func send(_ command: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
            try command.write(toFile: cmdPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func logTail(_ path: String, lines: Int) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty else {
            return "(空)"
        }
        return content.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }
}
