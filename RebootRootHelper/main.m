#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#import <Foundation/Foundation.h>

// RebootRootHelper 有两个职责：
//   1) install-daemon：以 root 身份把 RebootDaemon + launchd plist 装进系统并拉起
//      （这一步只能用 root 写 /Library/LaunchDaemons 与 /usr/libexec）。
//   2) 直接 reboot(0)：保留给 daemon 装不上时的兜底路径，同时用 whoami 自检身份。
//
// 真机排查时，"helper 到底有没有以 root 身份跑起来"比 reboot 的返回值更关键：
// reboot(2) 在内核里走 suser()，uid 不是 0 必然 EPERM。

static NSString *const kBaseDir = @"/var/mobile/Library/Caches/com.wan.reboottools";
static NSString *const kInstallLog = @"/var/mobile/Library/Caches/com.wan.reboottools/install.log";

static void installLogAppend(NSString *line, NSMutableString *accum)
{
	fprintf(stderr, "%s\n", [line UTF8String]);
	[accum appendFormat:@"%@\n", line];
}

static BOOL runCommand(NSString *command, NSMutableString *out)
{
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/bin/sh";
	task.arguments = @[@"-c", command];
	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = pipe;
	@try {
		[task launch];
		[task waitUntilExit];
	} @catch (__unused NSException *e) {
		return NO;
	}
	NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (text.length) {
		[out appendFormat:@"$ %@\n%@", command, text];
		fprintf(stderr, "[cmd] %s\n%s\n", [command UTF8String], [text UTF8String]);
	}
	return task.terminationStatus == 0;
}

static int installDaemon(NSString *daemonSrc, NSString *plistSrc)
{
	NSMutableString *log = [NSMutableString string];
	NSFileManager *fm = [NSFileManager defaultManager];

	[fm createDirectoryAtPath:kBaseDir withIntermediateDirectories:YES
				   attributes:@{NSFilePosixPermissions : @0777} error:NULL];

	installLogAppend([NSString stringWithFormat:@"uid=%u euid=%u", (unsigned)getuid(), (unsigned)geteuid()], log);

	if (getuid() != 0) {
		installLogAppend(@"NOT ROOT，无法写 /Library/LaunchDaemons", log);
		[[log copy] writeToFile:kInstallLog atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		return 2;
	}

	if (![fm fileExistsAtPath:daemonSrc] || ![fm fileExistsAtPath:plistSrc]) {
		installLogAppend([NSString stringWithFormat:@"缺少源文件 daemon=%@ plist=%@", daemonSrc, plistSrc], log);
		[[log copy] writeToFile:kInstallLog atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		return 3;
	}

	NSString *daemonDst = @"/usr/libexec/RebootDaemon";
	NSString *plistDst = @"/Library/LaunchDaemons/com.wan.reboottools.daemon.plist";

	[fm removeItemAtPath:daemonDst error:NULL];
	[fm removeItemAtPath:plistDst error:NULL];

	NSError *err = nil;
	if (![fm copyItemAtPath:daemonSrc toPath:daemonDst error:&err]) {
		installLogAppend([NSString stringWithFormat:@"复制 daemon 失败: %@", err.localizedDescription], log);
		[[log copy] writeToFile:kInstallLog atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		return 4;
	}
	if (![fm copyItemAtPath:plistSrc toPath:plistDst error:&err]) {
		installLogAppend([NSString stringWithFormat:@"复制 plist 失败: %@", err.localizedDescription], log);
		[[log copy] writeToFile:kInstallLog atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		return 5;
	}

	chmod([daemonDst UTF8String], 0755);
	chmod([plistDst UTF8String], 0644);
	chown([daemonDst UTF8String], 0, 0);
	chown([plistDst UTF8String], 0, 0);

	// 日志/命令目录要被 mobile 读写，否则 App 无法投递命令。
	chmod([kBaseDir UTF8String], 0777);
	chown([kBaseDir UTF8String], 501, 501);

	installLogAppend(@"文件已就位：/usr/libexec/RebootDaemon + /Library/LaunchDaemons/com.wan.reboottools.daemon.plist", log);

	// iOS 13+ 用 bootstrap system；老版本回退到 load -w。
	BOOL ok = runCommand(@"launchctl bootstrap system /Library/LaunchDaemons/com.wan.reboottools.daemon.plist", log);
	if (!ok) {
		ok = runCommand(@"launchctl load -w /Library/LaunchDaemons/com.wan.reboottools.daemon.plist", log);
	}
	runCommand(@"launchctl list | grep -i reboottools", log);

	installLogAppend(ok ? @"launchctl 已加载 daemon" : @"launchctl 加载失败", log);
	[[log copy] writeToFile:kInstallLog atomically:YES encoding:NSUTF8StringEncoding error:NULL];

	return ok ? 0 : 6;
}

int main(int argc, char *argv[], char *envp[])
{
	@autoreleasepool {
		uid_t uid = getuid();
		gid_t gid = getgid();
		fprintf(stderr, "helper uid=%u euid=%u gid=%u argc=%d\n",
				(unsigned)uid, (unsigned)geteuid(), (unsigned)gid, argc);

		// whoami 模式：只报告身份，不动设备。用来在不重启的前提下验证
		// persona 提权是否真的生效。
		if (argc > 1 && strcmp(argv[1], "whoami") == 0) {
			return uid == 0 ? 0 : 2;
		}

		// install-daemon <daemonPath> <plistPath>
		if (argc > 3 && strcmp(argv[1], "install-daemon") == 0) {
			return installDaemon([NSString stringWithUTF8String:argv[2]],
								 [NSString stringWithUTF8String:argv[3]]);
		}

		if (uid != 0) {
			fprintf(stderr, "NOT ROOT: uid=%u, reboot(0) will fail with EPERM\n", (unsigned)uid);
			return 2;
		}

		if (reboot(0) == 0) {
			return 0;
		}
		int err = errno;
		fprintf(stderr, "reboot(0) failed: errno=%d (%s)\n", err, strerror(err));
		return err == 0 ? 1 : err;
	}
}
