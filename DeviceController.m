#import "DeviceController.h"
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#import <sys/sysctl.h>
#import <Foundation/Foundation.h>
#import <FrontBoardServices/FBSSystemService.h>

@implementation DeviceController
{
	int _lastExitCode;
	NSString *_lastLog;
	int _lastKilledCount;
}

// 最近一次 spawnRoot 里 persona（提权）设置的结果，拼进 lastLog 供界面显示。
static NSString *gPersonaLog = @"";

// 本文件是 MRC 编译（Makefile 没有 -fobjc-arc）。直接把 autoreleased 字符串赋给
// 静态变量/实例变量，自动释放池一排空就变悬垂指针，下一次 %@ 格式化或 Swift 侧
// 桥接时会在 objc_release 里崩 —— 这正是 v6 起「点开就闪退」的根因
// （探测跑在后台队列 com.apple.root.user-initiated-qos，池一排空就炸）。
// 统一走这个函数：持有 +1 副本，替换前先释放旧值。
static void SetOwnedString(NSString **slot, NSString *value)
{
	if (*slot != value) {
		[*slot release];
		*slot = [value copy];
	}
}

@synthesize lastExitCode = _lastExitCode;
@synthesize lastLog = _lastLog;
@synthesize lastKilledCount = _lastKilledCount;

- (void)dealloc
{
	[_lastLog release];
	[super dealloc];
}

// ---------------- v13 C 级崩溃追踪 ----------------
// 前面的 v12 探针把日志写在 Documents/probe.log（要靠 ObjC 拼路径、要 open 新 fd），
// 结果真机上 probe.log 一行都没有 —— 说明崩溃发生在「连第一行日志都没写下去」的位置。
// 所以这一层再往下：启动时就预打开一个 fd，之后每行只做 write + fsync，
// 不碰 ObjC、不碰路径拼接、不受自动释放池影响。崩溃现场一定留在这份文件里。
static int gTraceFd = -1;
static char gTracePathBuf[512];

static void TraceRaw(const char *line, int n)
{
	if (n <= 0) return;
	if (gTraceFd < 0) return;
	ssize_t ignored = write(gTraceFd, line, (size_t)n);
	(void)ignored;
	fsync(gTraceFd);
}

const char *RTTracePath(void)
{
	return gTracePathBuf;
}

void RTTraceInit(void)
{
	if (gTraceFd >= 0) return;
	const char *tmp = getenv("TMPDIR");
	if (tmp == NULL || tmp[0] == 0) tmp = "/tmp";
	snprintf(gTracePathBuf, sizeof(gTracePathBuf), "%s/rt-trace.log", tmp);
	gTraceFd = open(gTracePathBuf, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (gTraceFd < 0) {
		// TMPDIR 不可写时退到 Documents（同样是纯 C 拼接）
		const char *home = getenv("HOME");
		if (home != NULL && home[0] != 0) {
			snprintf(gTracePathBuf, sizeof(gTracePathBuf), "%s/Documents/rt-trace.log", home);
			gTraceFd = open(gTracePathBuf, O_WRONLY | O_CREAT | O_APPEND, 0644);
		}
	}
	if (gTraceFd < 0) return;

	char hdr[192];
	snprintf(hdr, sizeof(hdr), "\n===== rt-trace open pid=%d uid=%d euid=%d t=%ld =====\n",
	         (int)getpid(), (int)getuid(), (int)geteuid(), (long)time(NULL));
	TraceRaw(hdr, (int)strlen(hdr));
}

void RTTrace(const char *fmt, ...)
{
	if (gTraceFd < 0) RTTraceInit();
	if (gTraceFd < 0) return;

	char line[512];
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(line, sizeof(line) - 2, fmt, ap);
	va_end(ap);
	if (n < 0) return;
	if (n > (int)sizeof(line) - 2) n = (int)sizeof(line) - 2;
	line[n++] = '\n';
	line[n] = 0;
	TraceRaw(line, n);
}

// Swift 侧入口：Swift 导入 C 可变参数函数会被标记 unavailable，所以单独给一个
// 非可变参数版本，格式化在 Swift 里拼好，这里只补换行。
void RTTraceStr(const char *s)
{
	if (s == NULL) return;
	if (gTraceFd < 0) RTTraceInit();
	if (gTraceFd < 0) return;

	char line[512];
	int n = snprintf(line, sizeof(line) - 2, "%s", s);
	if (n < 0) return;
	if (n > (int)sizeof(line) - 2) n = (int)sizeof(line) - 2;
	line[n++] = '\n';
	line[n] = 0;
	TraceRaw(line, n);
}

// ---------------- v12 崩溃定位探针 ----------------
// 每次 open/append/write/fsync/close，绝不经过任何内存缓冲。
// v13 起同时镜像一份到 rt-trace.log，两条路都断掉才算没留下证据。
static void ProbeLog(const char *fmt, ...)
{
	char line[512];
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(line, sizeof(line) - 2, fmt, ap);
	va_end(ap);
	if (n < 0) return;
	if (n > (int)sizeof(line) - 2) n = (int)sizeof(line) - 2;
	line[n++] = '\n';
	line[n] = 0;

	if (gTraceFd < 0) RTTraceInit();
	TraceRaw(line, n);

	NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/probe.log"];
	int fd = open([path UTF8String], O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd < 0) return;
	ssize_t ignored = write(fd, line, (size_t)n);
	(void)ignored;
	fsync(fd);
	close(fd);
}

// 自检阶梯用：跳过 persona 属性设置，验证「不提权」时是否同样崩。
static BOOL gSpawnSkipPersona = NO;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

- (BOOL) RebootDevice
{
	NSString *path = [[NSBundle mainBundle] pathForResource:@"RebootRootHelper" ofType:@""];

	NSArray *args = @[]; // 不需要任何额外参数
    NSString *stdOut = nil;
    NSString *stdErr = nil;

	if (path == nil) {
		_lastExitCode = -1;
		_lastLog = @"RebootRootHelper not found in bundle";
		return NO;
	}

	int result = spawnRoot(path, args, &stdOut, &stdErr);
	// 必须把 helper 的退出码和 stderr 带出去：reboot(0) 被内核拒绝时
	// 只有这里才能看到真实原因（EPERM 等），否则表现为静默失败。
	_lastExitCode = result;
	SetOwnedString(&_lastLog, [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@", gPersonaLog, result, stdOut.length ? stdOut : @"(empty)", stdErr.length ? stdErr : @"(empty)"]);

	return result == 0;
}

- (BOOL) probeHelperIdentity
{
	NSString *path = [[NSBundle mainBundle] pathForResource:@"RebootRootHelper" ofType:@""];
	if (path == nil) {
		_lastExitCode = -1;
		_lastLog = @"RebootRootHelper not found in bundle";
		return NO;
	}

	NSString *stdOut = nil;
	NSString *stdErr = nil;
	int result = spawnRoot(path, @[@"whoami"], &stdOut, &stdErr);
	_lastExitCode = result;
	SetOwnedString(&_lastLog, [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@", gPersonaLog, result, stdOut.length ? stdOut : @"(empty)", stdErr.length ? stdErr : @"(empty)"]);
	return result == 0;
}

- (BOOL) installRootDaemon:(NSString *)daemonPath plistPath:(NSString *)plistPath
{
	return [self installRootDaemon:daemonPath plistPath:plistPath load:NO];
}

- (BOOL) installRootDaemon:(NSString *)daemonPath plistPath:(NSString *)plistPath load:(BOOL)load
{
	NSString *path = [[NSBundle mainBundle] pathForResource:@"RebootRootHelper" ofType:@""];
	if (path == nil) {
		_lastExitCode = -1;
		_lastLog = @"RebootRootHelper not found in bundle";
		return NO;
	}

	NSString *stdOut = nil;
	NSString *stdErr = nil;
	NSMutableArray *args = [@[@"install-daemon", daemonPath ?: @"", plistPath ?: @""] mutableCopy];
	if (load) {
		[args addObject:@"--load"];
	}
	int result = spawnRoot(path, args, &stdOut, &stdErr);

	_lastExitCode = result;
	SetOwnedString(&_lastLog, [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@", gPersonaLog, result, stdOut.length ? stdOut : @"(empty)", stdErr.length ? stdErr : @"(empty)"]);
	return result == 0;
}

- (BOOL) RebootUserspace
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"RebootUserSpaceHelper" ofType:@""];

    NSArray *args = @[]; // 不需要任何额外参数
    NSString *stdOut = nil;
    NSString *stdErr = nil;

    if (path == nil) {
        _lastExitCode = -1;
        _lastLog = @"RebootUserSpaceHelper not found in bundle";
        return NO;
    }

    int result = spawnRoot(path, args, &stdOut, &stdErr);
    _lastExitCode = result;
    SetOwnedString(&_lastLog, [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@", gPersonaLog, result, stdOut.length ? stdOut : @"(empty)", stdErr.length ? stdErr : @"(empty)"]);

    if (result == 0) {
        return YES;
    }

    return NO;
}

// @See https://github.com/opa334/TrollStore/blob/main/Shared/TSUtil.m#L297
- (void) Respring
{
	killall(@"SpringBoard", YES);
	exit(0);
}

// 统计式注销：kill 失败时不再 exit(0)，否则「App 退出回桌面」会被误认成注销成功。
- (BOOL) RespringAndReport
{
	__block int killed = 0;
	__block int lastErr = 0;
	enumerateProcessesUsingBlock(^(pid_t pid, NSString* executablePath, BOOL* stop)
	{
		if ([executablePath.lastPathComponent isEqualToString:@"SpringBoard"])
		{
			if (kill(pid, SIGTERM) == 0) {
				killed++;
			} else {
				lastErr = errno;
			}
		}
	});

	_lastKilledCount = killed;
	_lastExitCode = (killed > 0) ? 0 : (lastErr ? lastErr : -1);
	SetOwnedString(&_lastLog, [NSString stringWithFormat:@"respring killed=%d errno=%d uid=%u euid=%u", killed, lastErr, getuid(), geteuid()]);

	if (killed > 0) {
		exit(0);
	}
	return NO;
}

// @See https://github.com/opa334/TrollStore/blob/main/Shared/TSUtil.m#L79
int spawnRoot(NSString* path, NSArray* args, NSString** stdOut, NSString** stdErr)
{
    NSMutableArray* argsM = args.mutableCopy ?: [NSMutableArray new];
    [argsM insertObject:path atIndex:0];

    NSUInteger argCount = [argsM count];
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char*));

    for (NSUInteger i = 0; i < argCount; i++)
    {
        argsC[i] = strdup([[argsM objectAtIndex:i] UTF8String]);
    }
    argsC[argCount] = NULL;

    ProbeLog("[spawn] begin path=%s argc=%lu skipPersona=%d pipes=%d", [path UTF8String], (unsigned long)argCount, (int)gSpawnSkipPersona, (stdOut || stdErr) ? 1 : 0);

    posix_spawnattr_t attr;
    ProbeLog("[spawn] before attr_init");
    posix_spawnattr_init(&attr);
    ProbeLog("[spawn] after attr_init");

    // 这三个调用决定 helper 能不能拿到 root：persona 覆盖需要
    // com.apple.private.persona-mgmt，且必须被内核真正接受。
    // 原来直接忽略返回值，失败时 helper 会以 mobile 身份静默运行，
    // reboot(0) 必然 EPERM —— 这正是「点了没反应」最难查的一层。
    int personaErr = -999, personaErrno = 0;
    int personaUidErr = -999, personaUidErrno = 0;
    int personaGidErr = -999, personaGidErrno = 0;
    if (!gSpawnSkipPersona)
    {
        errno = 0;
        ProbeLog("[spawn] before persona_np");
        personaErr = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
        personaErrno = errno;
        ProbeLog("[spawn] after persona_np ret=%d errno=%d", personaErr, personaErrno);
        errno = 0;
        ProbeLog("[spawn] before persona_uid");
        personaUidErr = posix_spawnattr_set_persona_uid_np(&attr, 0);
        personaUidErrno = errno;
        ProbeLog("[spawn] after persona_uid ret=%d errno=%d", personaUidErr, personaUidErrno);
        errno = 0;
        ProbeLog("[spawn] before persona_gid");
        personaGidErr = posix_spawnattr_set_persona_gid_np(&attr, 0);
        personaGidErrno = errno;
        ProbeLog("[spawn] after persona_gid ret=%d errno=%d", personaGidErr, personaGidErrno);
    }
    else
    {
        ProbeLog("[spawn] persona skipped");
    }

    SetOwnedString(&gPersonaLog, [NSString stringWithFormat:@"app uid=%d euid=%d | persona set=%d(errno=%d) uid=%d(errno=%d) gid=%d(errno=%d)", getuid(), geteuid(), personaErr, personaErrno, personaUidErr, personaUidErrno, personaGidErr, personaGidErrno]);

    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);

    int outErr[2] = {-1, -1};
    int out[2] = {-1, -1};
    if(stdErr)
    {
        ProbeLog("[spawn] before pipe(stderr)");
        if (pipe(outErr) == 0) {
            posix_spawn_file_actions_adddup2(&action, outErr[1], STDERR_FILENO);
            posix_spawn_file_actions_addclose(&action, outErr[0]);
        } else {
            ProbeLog("[spawn] pipe(stderr) failed errno=%d", errno);
        }
        ProbeLog("[spawn] after pipe(stderr) fd=%d,%d", outErr[0], outErr[1]);
    }

    if(stdOut)
    {
        ProbeLog("[spawn] before pipe(stdout)");
        if (pipe(out) == 0) {
            posix_spawn_file_actions_adddup2(&action, out[1], STDOUT_FILENO);
            posix_spawn_file_actions_addclose(&action, out[0]);
        } else {
            ProbeLog("[spawn] pipe(stdout) failed errno=%d", errno);
        }
        ProbeLog("[spawn] after pipe(stdout) fd=%d,%d", out[0], out[1]);
    }

    pid_t task_pid;
    int status = -200;
    ProbeLog("[spawn] before posix_spawn");
    int spawnError = posix_spawn(&task_pid, [path UTF8String], &action, &attr, (char* const*)argsC, NULL);
    ProbeLog("[spawn] after posix_spawn ret=%d pid=%d", spawnError, (int)task_pid);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&action);
    for (NSUInteger i = 0; i < argCount; i++)
    {
        free(argsC[i]);
    }
    free(argsC);

    if(spawnError != 0)
    {
        NSLog(@"posix_spawn error %d\n", spawnError);
        return spawnError;
    }

    __block volatile BOOL _isRunning = YES;
    NSMutableString* outString = [NSMutableString new];
    NSMutableString* errString = [NSMutableString new];
    dispatch_semaphore_t sema = 0;
    dispatch_queue_t logQueue;
    if(stdOut || stdErr)
    {
        logQueue = dispatch_queue_create("com.opa334.TrollStore.LogCollector", NULL);
        sema = dispatch_semaphore_create(0);

        int outPipe = out[0];
        int outErrPipe = outErr[0];

        __block BOOL outEnabled = (BOOL)stdOut;
        __block BOOL errEnabled = (BOOL)stdErr;
        dispatch_async(logQueue, ^
        {
            while(_isRunning)
            {
                @autoreleasepool
                {
                    if(outEnabled)
                    {
                        [outString appendString:getNSStringFromFile(outPipe)];
                    }
                    if(errEnabled)
                    {
                        [errString appendString:getNSStringFromFile(outErrPipe)];
                    }
                }
            }
            dispatch_semaphore_signal(sema);
        });
    }

    do
    {
        ProbeLog("[spawn] before waitpid");
        if (waitpid(task_pid, &status, 0) != -1) {
            ProbeLog("[spawn] after waitpid exited=%d status=%d", WIFEXITED(status) ? WEXITSTATUS(status) : -1, status);
            NSLog(@"Child status %d", WEXITSTATUS(status));
        } else
        {
            ProbeLog("[spawn] waitpid failed errno=%d", errno);
            perror("waitpid");
            _isRunning = NO;
            return -222;
        }
    } while (!WIFEXITED(status) && !WIFSIGNALED(status));

    _isRunning = NO;
    if(stdOut || stdErr)
    {
        if(stdOut)
        {
            close(out[1]);
        }
        if(stdErr)
        {
            close(outErr[1]);
        }

        // wait for logging queue to finish
        ProbeLog("[spawn] before semaphore_wait");
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        ProbeLog("[spawn] after semaphore_wait");

        if(stdOut)
        {
            *stdOut = outString.copy;
        }
        if(stdErr)
        {
            *stdErr = errString.copy;
        }
    }

    ProbeLog("[spawn] end exit=%d", WEXITSTATUS(status));
    return WEXITSTATUS(status);
}

NSString* getNSStringFromFile(int fd)
{
    NSMutableString* ms = [NSMutableString new];
    ssize_t num_read;
    char c;
    if(!fd_is_valid(fd)) return @"";
    // 必须显式处理 num_read <= 0：read 出错返回 -1（真值），原写法会死循环往
    // 字符串里塞垃圾直到进程被杀。
    while((num_read = read(fd, &c, sizeof(c))) == 1)
    {
        [ms appendString:[NSString stringWithFormat:@"%c", c]];
        if(c == '\n') break;
    }
    return ms.copy;
}

int fd_is_valid(int fd)
{
    return fcntl(fd, F_GETFD) != -1 || errno != EBADF;
}

// @See https://github.com/opa334/TrollStore/blob/main/Shared/TSUtil.m#L279
void killall(NSString* processName, BOOL softly)
{
	enumerateProcessesUsingBlock(^(pid_t pid, NSString* executablePath, BOOL* stop)
	{
		if([executablePath.lastPathComponent isEqualToString:processName])
		{
			if(softly)
			{
				kill(pid, SIGTERM);
			}
			else
			{
				kill(pid, SIGKILL);
			}
		}
	});
}

void enumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString* executablePath, BOOL* stop))
{
	static int maxArgumentSize = 0;
	if (maxArgumentSize == 0) {
		size_t size = sizeof(maxArgumentSize);
		if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &maxArgumentSize, &size, NULL, 0) == -1) {
			perror("sysctl argument size");
			maxArgumentSize = 4096; // Default
		}
	}
	int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL};
	struct kinfo_proc *info;
	size_t length;
	int count;

	if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0)
		return;
	if (!(info = malloc(length)))
		return;
	if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
		free(info);
		return;
	}
	count = length / sizeof(struct kinfo_proc);
	for (int i = 0; i < count; i++) {
		@autoreleasepool {
		pid_t pid = info[i].kp_proc.p_pid;
		if (pid == 0) {
			continue;
		}
		size_t size = maxArgumentSize;
		char* buffer = (char *)malloc(length);
		if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3, buffer, &size, NULL, 0) == 0) {
			NSString* executablePath = [NSString stringWithCString:(buffer+sizeof(int)) encoding:NSUTF8StringEncoding];

			BOOL stop = NO;
			enumerator(pid, executablePath, &stop);
			if(stop)
			{
				free(buffer);
				break;
			}
		}
		free(buffer);
		}
	}
	free(info);
}

// ---------------- v13 自检阶梯 ----------------
// 真机上「运行 root 探测」闪退且 probe.log 一行都没有，所以第一级必须是
// 完全纯 C 的 posix_spawn（不碰 ObjC、不碰 spawn attrs、不接管管道），
// 先确认「在这台机器上 spawn 到底能不能用」，再逐级往 ObjC / persona 上叠。
// L0 纯 C spawn → L1 最小 ObjC（NSBundle）→ L2 spawnRoot 无管道 →
// L3 spawnRoot 管道 → L4 helper 带 persona → L5 helper 不带 persona。
// 每一步之间都 RTTrace 到 rt-trace.log，崩溃现场一定能留下。
- (BOOL) selfTest
{
	RTTrace("== selfTest enter ==");

	// ---- L0：纯 C，不碰 ObjC ----
	RTTrace("[L0] pure-C posix_spawn begin");
	{
		char *argv[3];
		argv[0] = (char *)"/bin/echo";
		argv[1] = (char *)"rt-L0";
		argv[2] = NULL;
		pid_t pid = -1;
		int sp = posix_spawn(&pid, "/bin/echo", NULL, NULL, argv, NULL);
		RTTrace("[L0] posix_spawn ret=%d pid=%d errno=%d", sp, (int)pid, errno);
		if (sp == 0) {
			int st = 0;
			pid_t w = waitpid(pid, &st, 0);
			RTTrace("[L0] waitpid ret=%d status=%d exit=%d", (int)w, st,
			        WIFEXITED(st) ? WEXITSTATUS(st) : -1);
		}
	}
	RTTrace("[L0] done");

	// ---- L1：最小 ObjC 调用 ----
	RTTrace("[L1] NSBundle begin");
	NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
	RTTrace("[L1] bundlePath=%s", bundlePath ? [bundlePath UTF8String] : "(nil)");
	NSString *helper = [[NSBundle mainBundle] pathForResource:@"RebootRootHelper" ofType:@""];
	RTTrace("[L1] helperResolved=%d path=%s", helper != nil, helper ? [helper UTF8String] : "(nil)");
	RTTrace("[L1] done");

	ProbeLog("=== selftest begin ===");

	NSString *o = nil;
	NSString *e = nil;

	// ---- L2：不接管管道（不建 dispatch 队列/信号量），只看 posix_spawn 本身 ----
	RTTrace("[L2] echo nopipe begin");
	ProbeLog("[L2] echo nopipe start");
	int r2 = spawnRoot(@"/bin/echo", @[@"v13-L2"], NULL, NULL);
	RTTrace("[L2] nopipe done exit=%d", r2);

	// ---- L3：接管管道 → 建日志队列 + 信号量 ----
	RTTrace("[L3] echo pipe begin");
	int r3 = spawnRoot(@"/bin/echo", @[@"v13-L3"], &o, &e);
	RTTrace("[L3] pipe done exit=%d", r3);
	o = nil; e = nil;

	// ---- L4：真正的 helper（提权 + 管道）----
	if (helper == nil) {
		RTTrace("[L4] helper missing, skip");
	} else {
		RTTrace("[L4] helper persona begin");
		int r4 = spawnRoot(helper, @[@"whoami"], &o, &e);
		RTTrace("[L4] helper persona done exit=%d", r4);
		o = nil; e = nil;

		// ---- L5：同样的 helper，但完全不设 persona（不提权）----
		gSpawnSkipPersona = YES;
		RTTrace("[L5] helper nopersona begin");
		int r5 = spawnRoot(helper, @[@"whoami"], &o, &e);
		gSpawnSkipPersona = NO;
		RTTrace("[L5] helper nopersona done exit=%d", r5);
	}

	RTTrace("== selfTest end ==");
	ProbeLog("=== selftest end ===");
	return YES;
}

@end
