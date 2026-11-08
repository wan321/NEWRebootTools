#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

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
/// 以 root 身份执行 `RebootRootHelper install-daemon <daemon> <plist>`，
/// 把 RebootDaemon 装进 /usr/libexec 并注册为开机自启的 launchd 守护进程。
- (BOOL) installRootDaemon:(NSString *)daemonPath plistPath:(NSString *)plistPath;
- (void) Respring;
/// 与 Respring 相同，但会统计真正杀掉了几个 SpringBoard：一个都没杀掉时不 exit，
/// 让上层能把「注销其实没成功」显示出来（旧实现无论 kill 成功与否都 exit(0)，
/// 表现就是 App 一退出、用户看到“回到桌面”，误以为注销生效了）。
- (BOOL) RespringAndReport;

@end
