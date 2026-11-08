#import "DeviceController.h"
#include <spawn.h>
#include <signal.h>
#include <unistd.h>
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

@synthesize lastExitCode = _lastExitCode;
@synthesize lastLog = _lastLog;
@synthesize lastKilledCount = _lastKilledCount;

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
	_lastLog = [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@",
				gPersonaLog,
				result,
				stdOut.length ? stdOut : @"(empty)",
				stdErr.length ? stdErr : @"(empty)"];

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
	_lastLog = [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@",
				gPersonaLog,
				result,
				stdOut.length ? stdOut : @"(empty)",
				stdErr.length ? stdErr : @"(empty)"];
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
	_lastLog = [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@",
				gPersonaLog,
				result,
				stdOut.length ? stdOut : @"(empty)",
				stdErr.length ? stdErr : @"(empty)"];
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
    _lastLog = [NSString stringWithFormat:@"%@ | exit=%d stdout=%@ stderr=%@",
                gPersonaLog,
                result,
                stdOut.length ? stdOut : @"(empty)",
                stdErr.length ? stdErr : @"(empty)"];

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
	_lastLog = [NSString stringWithFormat:@"respring killed=%d errno=%d uid=%u euid=%u",
				killed, lastErr, getuid(), geteuid()];

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

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    // 这三个调用决定 helper 能不能拿到 root：persona 覆盖需要
    // com.apple.private.persona-mgmt，且必须被内核真正接受。
    // 原来直接忽略返回值，失败时 helper 会以 mobile 身份静默运行，
    // reboot(0) 必然 EPERM —— 这正是「点了没反应」最难查的一层。
    errno = 0;
    int personaErr = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int personaErrno = errno;
    errno = 0;
    int personaUidErr = posix_spawnattr_set_persona_uid_np(&attr, 0);
    int personaUidErrno = errno;
    errno = 0;
    int personaGidErr = posix_spawnattr_set_persona_gid_np(&attr, 0);
    int personaGidErrno = errno;

    gPersonaLog = [NSString stringWithFormat:@"app uid=%d euid=%d | persona set=%d(errno=%d) uid=%d(errno=%d) gid=%d(errno=%d)",
                   getuid(), geteuid(),
                   personaErr, personaErrno,
                   personaUidErr, personaUidErrno,
                   personaGidErr, personaGidErrno];

    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);

    int outErr[2];
    if(stdErr)
    {
        pipe(outErr);
        posix_spawn_file_actions_adddup2(&action, outErr[1], STDERR_FILENO);
        posix_spawn_file_actions_addclose(&action, outErr[0]);
    }

    int out[2];
    if(stdOut)
    {
        pipe(out);
        posix_spawn_file_actions_adddup2(&action, out[1], STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&action, out[0]);
    }

    pid_t task_pid;
    int status = -200;
    int spawnError = posix_spawn(&task_pid, [path UTF8String], &action, &attr, (char* const*)argsC, NULL);
    posix_spawnattr_destroy(&attr);
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
        if (waitpid(task_pid, &status, 0) != -1) {
            NSLog(@"Child status %d", WEXITSTATUS(status));
        } else
        {
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
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

        if(stdOut)
        {
            *stdOut = outString.copy;
        }
        if(stdErr)
        {
            *stdErr = errString.copy;
        }
    }

    return WEXITSTATUS(status);
}

NSString* getNSStringFromFile(int fd)
{
    NSMutableString* ms = [NSMutableString new];
    ssize_t num_read;
    char c;
    if(!fd_is_valid(fd)) return @"";
    while((num_read = read(fd, &c, sizeof(c))))
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

@end
