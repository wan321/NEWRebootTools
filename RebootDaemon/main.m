#import <Foundation/Foundation.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

// RebootDaemon：由 launchd 以 root 身份常驻（/Library/LaunchDaemons）。
//
// 为什么需要它：reboot(2) 在内核里走 suser()，uid 必须为 0；而 TrollStore 安装的 App
// 永远以 mobile(501) 启动，靠 posix_spawn 的 persona 覆盖去抬权限属于"每次都要赌一次"。
// 把 root 能力固化成一个开机就起来的守护进程之后，App 只需要往一个 mobile 可写的
// 文件里写命令，重启链路不再依赖 App 自身的权限。

static NSString *const kBaseDir = @"/var/mobile/Library/Caches/com.wan.reboottools";
static NSString *const kCmdPath = @"/var/mobile/Library/Caches/com.wan.reboottools/cmd";
static NSString *const kHeartbeatPath = @"/var/mobile/Library/Caches/com.wan.reboottools/heartbeat";
static NSString *const kLogPath = @"/var/mobile/Library/Caches/com.wan.reboottools/daemon.log";

static void appendLog(NSString *line)
{
	NSString *stamped = [NSString stringWithFormat:@"%@ %@\n",
						 [[NSDate date] descriptionWithLocale:nil], line];
	NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
	if (fh == nil) {
		[[NSFileManager defaultManager] createFileAtPath:kLogPath contents:nil attributes:nil];
		fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
	}
	if (fh == nil) {
		return;
	}
	@try {
		[fh seekToEndOfFile];
		[fh writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
		[fh closeFile];
	} @catch (__unused NSException *e) {
	}
}

static void writeString(NSString *text, NSString *path)
{
	NSString *tmp = [path stringByAppendingString:@".tmp"];
	[text writeToFile:tmp atomically:NO encoding:NSUTF8StringEncoding error:NULL];
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	[[NSFileManager defaultManager] moveItemAtPath:tmp toPath:path error:NULL];
}

static void writeHeartbeat(void)
{
	NSString *body = [NSString stringWithFormat:@"uid=%u euid=%u pid=%d ts=%.0f\n",
					  (unsigned)getuid(), (unsigned)geteuid(), (int)getpid(), [[NSDate date] timeIntervalSince1970]];
	writeString(body, kHeartbeatPath);
}

// 遍历进程表杀掉 SpringBoard。root 下这一步才会真的成功；mobile 下必 EPERM，
// 旧实现 kill 失败也照样 exit(0)，表现就是"App 退出、回到桌面"的假注销。
static int killSpringBoard(void)
{
	int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
	size_t size = 0;
	if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0) {
		return -1;
	}
	struct kinfo_proc *procs = malloc(size);
	if (procs == NULL) {
		return -1;
	}
	if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) {
		free(procs);
		return -1;
	}
	int count = (int)(size / sizeof(struct kinfo_proc));
	int killed = 0;
	for (int i = 0; i < count; i++) {
		if (strcmp(procs[i].kp_proc.p_comm, "SpringBoard") == 0) {
			if (kill(procs[i].kp_proc.p_pid, SIGTERM) == 0) {
				killed++;
			}
		}
	}
	free(procs);
	return killed;
}

static void handleCommand(NSString *raw)
{
	NSString *cmd = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (cmd.length == 0) {
		return;
	}
	appendLog([NSString stringWithFormat:@"收到命令: %@ (uid=%u)", cmd, (unsigned)getuid()]);

	if ([cmd isEqualToString:@"ping"]) {
		appendLog(@"pong");
		return;
	}

	if ([cmd isEqualToString:@"respring"]) {
		int killed = killSpringBoard();
		appendLog([NSString stringWithFormat:@"respring 杀掉 SpringBoard=%d errno=%d", killed, errno]);
		if (killed > 0) {
			exit(0);
		}
		return;
	}

	if ([cmd isEqualToString:@"reboot"]) {
		appendLog(@"调用 reboot(0)…");
		if (reboot(0) == 0) {
			return;
		}
		appendLog([NSString stringWithFormat:@"reboot(0) 失败 errno=%d (%s)", errno, strerror(errno)]);
		return;
	}

	appendLog([NSString stringWithFormat:@"未知命令: %@", cmd]);
}

int main(int argc, char *argv[])
{
	@autoreleasepool {
		[[NSFileManager defaultManager] createDirectoryAtPath:kBaseDir
								  withIntermediateDirectories:YES
												   attributes:@{NSFilePosixPermissions : @0777}
														error:NULL];

		appendLog([NSString stringWithFormat:@"daemon 启动 uid=%u euid=%u pid=%d argc=%d",
				   (unsigned)getuid(), (unsigned)geteuid(), (int)getpid(), argc]);

		// 自检模式：不进入循环，只回报身份，供 App 在不重启的前提下验证 daemon 是否可用。
		if (argc > 1 && strcmp(argv[1], "--selftest") == 0) {
			writeHeartbeat();
			appendLog(@"selftest 完成");
			return getuid() == 0 ? 0 : 3;
		}

		writeHeartbeat();

		for (;;) {
			@autoreleasepool {
				writeHeartbeat();

				NSString *cmd = [NSString stringWithContentsOfFile:kCmdPath
														  encoding:NSUTF8StringEncoding
															 error:NULL];
				if (cmd != nil) {
					[[NSFileManager defaultManager] removeItemAtPath:kCmdPath error:NULL];
					handleCommand(cmd);
				}

				// 日志超过 64KB 就清空，避免 root 进程把用户空间写爆。
				NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:kLogPath error:NULL];
				if (attrs != nil && [attrs fileSize] > 64 * 1024) {
					[[NSFileManager defaultManager] removeItemAtPath:kLogPath error:NULL];
					appendLog(@"日志超过 64KB，已重置");
				}

				sleep(1);
			}
		}
	}
}
