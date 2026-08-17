//
//  AppLauncher.m
//

#import "AppLauncher.h"
#import <spawn.h>
#import <sys/sysctl.h>
#import <sys/param.h>
#import <signal.h>
#import <dlfcn.h>
#import <sys/stat.h>

@implementation AppLauncher

+ (NSArray<NSNumber *> *)pidsForExecName:(NSString *)execName {
    // 遍历进程，按 comm（可执行文件名）匹配
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) < 0) return @[];

    struct kinfo_proc *procs = malloc(size);
    if (!procs) return @[];
    if (sysctl(mib, 3, procs, &size, NULL, 0) < 0) {
        free(procs);
        return @[];
    }

    int count = (int)(size / sizeof(struct kinfo_proc));
    NSMutableArray<NSNumber *> *pids = [NSMutableArray array];
    const char *target = [execName UTF8String];
    for (int i = 0; i < count; i++) {
        const char *comm = procs[i].kp_proc.p_comm;
        if (comm && strncmp(comm, target, MAXCOMLEN) == 0) {
            [pids addObject:@(procs[i].kp_proc.p_pid)];
        }
    }
    free(procs);
    return pids;
}

+ (void)killAppWithExecName:(NSString *)execName {
    // 先尝试 SIGTERM，给 App 正常退出的机会；失败再 SIGKILL
    NSArray<NSNumber *> *pids = [self pidsForExecName:execName];
    for (NSNumber *pid in pids) {
        kill(pid.intValue, SIGTERM);
    }
    // 给一点时间退出
    usleep(300 * 1000);
    pids = [self pidsForExecName:execName];
    for (NSNumber *pid in pids) {
        kill(pid.intValue, SIGKILL);
    }
}

+ (BOOL)launchAppAtExecPath:(NSString *)execPath
                  dylibPath:(NSString *)dylibPath
                 configPath:(NSString *)configPath {

    // 确保 dylib / config 可被目标进程读取（tmp 默认对所有进程可读）
    chmod([dylibPath UTF8String], 0755);

    pid_t pid = 0;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    NSString *ldEnv  = [NSString stringWithFormat:@"DYLD_INSERT_LIBRARIES=%@", dylibPath];
    NSString *cfgEnv = [NSString stringWithFormat:@"TROLLMASK_CONFIG=%@", configPath];

    char *env[] = {
        (char *)[ldEnv  UTF8String],
        (char *)[cfgEnv UTF8String],
        NULL
    };
    char *argv[] = {
        (char *)[execPath UTF8String],
        NULL
    };

    int rv = posix_spawn(&pid, [execPath UTF8String], NULL, &attr, argv, env);
    posix_spawnattr_destroy(&attr);

    return (rv == 0 && pid > 0);
}

@end
