#include <errno.h>
#include <stdio.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>
#import <Foundation/Foundation.h>

// RebootRootHelper 有两个职责：
//   1) install-daemon：以 root 身份把 RebootDaemon + launchd plist 装进系统并拉起
//      （这一步只能用 root 写 /Library/LaunchDaemons 与 /usr/libexec）。
//   2) 直接 reboot(0)：保留给 daemon 装不上时的兜底路径，同时用 whoami 自检身份。
//
// 真机排查时，"helper 到底有没有以 root 身份跑起来"比 reboot 的返回值更关键：
// reboot(2) 在内核里走 suser()，uid 不是 0 必然 EPERM。
//
// 注意：iOS 上没有 NSTask，所有外部命令都走 system()，输出直接追加到 install.log。

static NSString *const kBaseDir = @"/var/mobile/Library/Caches/com.wan.reboottools";
static NSString *const kInstallLog = @"/var/mobile/Library/Caches/com.wan.reboottools/install.log";

static void installLogAppend(NSString *line)
{
	fprintf(stderr, "%s\n", [line UTF8String]);
	NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kInstallLog];
	if (fh == nil) {
		[[NSFileManager defaultManager] createFileAtPath:kInstallLog contents:nil attributes:nil];
		fh = [NSFileHandle fileHandleForWritingAtPath:kInstallLog];
	}
	if (fh == nil) {
		return;
	}
	@try {
		[fh seekToEndOfFile];
		[fh writeData:[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
		[fh closeFile];
	} @catch (__unused NSException *e) {
	}
}

static int runCommand(NSString *command)
{
	// 退出码也写进日志，事后能分辨「命令没跑」和「命令跑了但失败」。
	// iOS SDK 里 NSTask 和 system() 都不可用（分别是不存在和显式标记 unavailable），
	// 所以直接用 posix_spawn 起 /bin/sh。
	NSString *full = [NSString stringWithFormat:@"%@ >> %@ 2>&1; echo \"[exit=$?] %@\" >> %@",
					  command, kInstallLog, command, kInstallLog];

	char *argv[4];
	argv[0] = "/bin/sh";
	argv[1] = "-c";
	argv[2] = (char *)[full UTF8String];
	argv[3] = NULL;

	for (int attempt = 0; attempt < 3; attempt++) {
		pid_t pid = 0;
		int rc = posix_spawn(&pid, "/bin/sh", NULL, NULL, argv, NULL);
		if (rc != 0) {
			continue;
		}
		int status = 0;
		if (waitpid(pid, &status, 0) < 0) {
			continue;
		}
		return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
	}
	return -1;
}

static int installDaemon(NSString *daemonSrc, NSString *plistSrc, BOOL shouldLoad)
{
	NSFileManager *fm = [NSFileManager defaultManager];

	[fm createDirectoryAtPath:kBaseDir withIntermediateDirectories:YES
				   attributes:@{NSFilePosixPermissions : @0777} error:NULL];
	[fm createFileAtPath:kInstallLog contents:nil attributes:nil];

	installLogAppend([NSString stringWithFormat:@"=== install-daemon 开始 uid=%u euid=%u ===",
					  (unsigned)getuid(), (unsigned)geteuid()]);

	if (getuid() != 0) {
		installLogAppend(@"NOT ROOT：无法写 /Library/LaunchDaemons，daemon 不可能装上");
		return 2;
	}

	if (![fm fileExistsAtPath:daemonSrc] || ![fm fileExistsAtPath:plistSrc]) {
		installLogAppend([NSString stringWithFormat:@"缺少源文件 daemon=%@ plist=%@", daemonSrc, plistSrc]);
		return 3;
	}

	NSString *daemonDst = @"/usr/libexec/RebootDaemon";
	NSString *plistDst = @"/Library/LaunchDaemons/com.wan.reboottools.daemon.plist";

	[fm removeItemAtPath:daemonDst error:NULL];
	[fm removeItemAtPath:plistDst error:NULL];

	NSError *err = nil;
	if (![fm copyItemAtPath:daemonSrc toPath:daemonDst error:&err]) {
		installLogAppend([NSString stringWithFormat:@"复制 daemon 失败: %@", err.localizedDescription]);
		return 4;
	}
	if (![fm copyItemAtPath:plistSrc toPath:plistDst error:&err]) {
		installLogAppend([NSString stringWithFormat:@"复制 plist 失败: %@", err.localizedDescription]);
		return 5;
	}

	chmod([daemonDst UTF8String], 0755);
	chmod([plistDst UTF8String], 0644);
	chown([daemonDst UTF8String], 0, 0);
	chown([plistDst UTF8String], 0, 0);

	// 命令/日志目录必须让 mobile 可读写，否则 App 无法投递命令。
	chmod([kBaseDir UTF8String], 0777);
	chown([kBaseDir UTF8String], 501, 501);

	installLogAppend(@"文件已就位：/usr/libexec/RebootDaemon + /Library/LaunchDaemons/com.wan.reboottools.daemon.plist");

	// v8：默认不碰 launchctl。曾怀疑「App 启动时 spawn 出以 root 跑的 launchctl」
	// 会连带把前台 App 一起干掉（表现为点开闪退），所以安装只做落盘，激活交给下一次
	// 开机/用户空间重启时 launchd 自己加载（plist 里有 RunAtLoad）。
	if (!shouldLoad) {
		installLogAppend(@"跳过 launchctl（落盘完成，重启一次后 launchd 会自动加载）");
		return 0;
	}

	// iOS 13+ 用 bootstrap system；老版本回退到 load -w。
	int rc = runCommand(@"launchctl bootstrap system /Library/LaunchDaemons/com.wan.reboottools.daemon.plist");
	BOOL ok = (rc == 0);
	if (!ok) {
		rc = runCommand(@"launchctl load -w /Library/LaunchDaemons/com.wan.reboottools.daemon.plist");
		ok = (rc == 0);
	}
	runCommand(@"launchctl list | grep -i reboottools || true");

	installLogAppend(ok ? @"launchctl 已加载 daemon" : @"launchctl 加载失败");
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

		// install-daemon <daemonPath> <plistPath> [--load]
		// 默认只落盘不加载：加载（spawn launchctl）是最可疑的闪退来源，改成可选。
		if (argc > 3 && strcmp(argv[1], "install-daemon") == 0) {
			BOOL shouldLoad = (argc > 4 && strcmp(argv[4], "--load") == 0);
			return installDaemon([NSString stringWithUTF8String:argv[2]],
								 [NSString stringWithUTF8String:argv[3]],
								 shouldLoad);
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
