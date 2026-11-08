#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

/// 最近一次 RebootDevice / RebootUserspace 中 helper 的退出码；
/// helper 根本没启动起来时是 posix_spawn 的错误码（负数）。
@property (nonatomic, readonly) int lastExitCode;
/// 最近一次调用的 helper stdout + stderr，用于把失败原因带到界面/日志里。
@property (nonatomic, copy, readonly) NSString *lastLog;

- (BOOL) RebootDevice;
- (BOOL) RebootUserspace;
- (void) Respring;

@end
