#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

/// v13：C 级崩溃追踪。启动时 RTTraceInit() 预打开 fd，之后 RTTrace() 每次
/// write+fsync 一行，不经过 ObjC、不经过任何内存缓冲。
/// 纯 C 实现，所以在「连 ObjC 调用都可能崩」的情况下仍然能留下现场。
void RTTraceInit(void);
void RTTrace(const char *fmt, ...);
/// 当前追踪文件的完整路径（C 字符串），未初始化时返回 ""。界面按这个路径读尾部。
const char *RTTracePath(void);

/// 最近一次 RebootDevice / RebootUserspace 中 helper 的退出码；
/// helper 根本没启动起来时是 posix_spawn 的错误码（负数）。
@property (nonatomic, readonly) int lastExitCode;
/// 最近一次调用的 helper stdout + stderr，用于把失败原因带到界面/日志里。
@property (nonatomic, copy, readonly) NSString *lastLog;
/// 最近一次 RespringAndReport 成功杀掉的目标进程数；0 表示 kill 全部被拒（多半是权限不足）。
@property (nonatomic, readonly) int lastKilledCount;

- (BOOL) RebootDevice;
- (BOOL) RebootUserspace;
/// 只把 RootHelper 以 root 身份跑起来并读回它的 uid/euid，不重启设备。
/// 用来验证 posix_spawn persona 提权是否真的生效（返回值仅代表 spawn 是否成功）。
- (BOOL) probeHelperIdentity;
/// v12：四级 spawn 自检阶梯（echo 无管道 → echo 有管道 → helper 带 persona →
/// helper 不带 persona），每一步开始前 fsync 一行到 Documents/probe.log。
/// 「运行 root 探测」闪退时，靠这个文件能定位死在哪一级、哪个 syscall。
- (BOOL) selfTest;
/// 以 root 身份执行 `RebootRootHelper install-daemon <daemon> <plist>`，
/// 把 RebootDaemon 装进 /usr/libexec 并注册为开机自启的 launchd 守护进程。
/// v8 起默认只落盘不调用 launchctl（spawn launchctl 是最可疑的闪退来源），
/// 激活交给下次开机时 launchd 自动加载；需要立即加载时用 load:YES。
- (BOOL) installRootDaemon:(NSString *)daemonPath plistPath:(NSString *)plistPath;
- (BOOL) installRootDaemon:(NSString *)daemonPath plistPath:(NSString *)plistPath load:(BOOL)load;
- (void) Respring;
/// 与 Respring 相同，但会统计真正杀掉了几个 SpringBoard：一个都没杀掉时不 exit，
/// 让上层能把「注销其实没成功」显示出来（旧实现无论 kill 成功与否都 exit(0)，
/// 表现就是 App 一退出、用户看到“回到桌面”，误以为注销生效了）。
- (BOOL) RespringAndReport;

@end
