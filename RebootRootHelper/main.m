#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#import <Foundation/Foundation.h>
#include <unistd.h>

// 这个 helper 只有两个职责：说清自己是谁（uid/euid），然后尝试 reboot(0)。
// 真机排查时，"helper 到底有没有以 root 身份跑起来" 比 reboot 的返回值更关键：
// reboot(2) 在内核里走 suser()，uid 不是 0 必然 EPERM。
int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool {
		uid_t uid = getuid();
		uid_t euid = geteuid();
		gid_t gid = getgid();
		fprintf(stderr, "helper uid=%u euid=%u gid=%u argc=%d\n", (unsigned)uid, (unsigned)euid, (unsigned)gid, argc);

		// whoami 模式：只报告身份，不动设备。用来在不重启的前提下验证
		// persona 提权是否真的生效。
		if (argc > 1 && strcmp(argv[1], "whoami") == 0) {
			return 0;
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
