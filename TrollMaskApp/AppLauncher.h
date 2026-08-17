//
//  AppLauncher.h
//  TrollMask — 注入启动逻辑（ObjC，桥接到 Swift）
//
//  通过 posix_spawn 直接启动目标 App 的可执行文件，并注入 TrollMaskDylib.dylib，
//  实现“仅对选定 App 生效”的伪装 + 虚拟定位。
//
//  依赖 TrollStore 的自定义 dyld 才能允许 DYLD_INSERT_LIBRARIES 注入任意 App。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppLauncher : NSObject

/// 终止正在运行的目标 App（按可执行文件名匹配进程），确保下一次启动会重新加载注入的 dylib
+ (void)killAppWithExecName:(NSString *)execName;

/// 用 DYLD_INSERT_LIBRARIES 注入方式启动目标 App
/// @param execPath   目标 App 的可执行文件绝对路径
/// @param dylibPath  注入用的 dylib 绝对路径（建议 /var/tmp/TrollMaskDylib.dylib）
/// @param configPath 配置文件绝对路径（建议 /var/tmp/trollmask_config.plist）
/// @return 是否成功发起启动
+ (BOOL)launchAppAtExecPath:(NSString *)execPath
                  dylibPath:(NSString *)dylibPath
                 configPath:(NSString *)configPath;

@end

NS_ASSUME_NONNULL_END
