#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <sys/sysctl.h>
#import <Foundation/Foundation.h>
#include <unistd.h>

int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool {
		// reboot(0) 失败时（常见于缺少 reboot 权限）把 errno 作为退出码返回，
		// 主 App 才能感知失败并弹出提示，而不是静默当成成功。
		if (reboot(0) == 0) {
			return 0;
		}
		int err = errno;
		fprintf(stderr, "reboot(0) failed: errno=%d (%s)\n", err, strerror(err));
		return err == 0 ? 1 : err;
	}
}
