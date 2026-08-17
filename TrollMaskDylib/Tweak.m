//
//  Tweak.m
//  TrollMaskDylib — 注入到目标 App 进程后生效
//
//  作用范围：仅对“加载了本 dylib 的那个 App 进程”生效，不改动整机/其它 App。
//  配置来源：环境变量 TROLLMASK_CONFIG 指向的 plist（默认 /var/tmp/trollmask_config.plist）。
//
//  说明：
//  - 真实硬件序列号（serial number）需要 bootloader 级修改（checkm8/kernboot），
//    普通 App 进程内无法改写。这里 hook 的是“App 能读取到的设备标识 API”，
//    可覆盖绝大多数基于 IDFV / sysctl / UIDevice 做机器码/设备指纹的逻辑。
//  - 依赖 substrate（theos 提供 MSHookMessageEx / MSHookFunction）。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <sys/sysctl.h>
#import <substrate.h>

#pragma mark - Config

static NSDictionary *gConfig = nil;
static BOOL gSpoofDevice = NO;
static BOOL gSpoofLocation = NO;
static CLLocation *gFakeLocation = nil;
static NSString *gFakeIDFV = nil;
static NSString *gFakeName = nil;
static NSString *gFakeModel = nil;     // e.g. @"iPhone"
static NSString *gFakeHWMachine = nil; // e.g. @"iPhone14,2"
static NSString *gFakeHWModel = nil;   // e.g. @"D16AP"

static NSString *ConfigPath(void) {
    char *env = getenv("TROLLMASK_CONFIG");
    if (env && strlen(env) > 0) return [NSString stringWithUTF8String:env];
    return @"/var/tmp/trollmask_config.plist";
}

static void LoadConfig(void) {
    @autoreleasepool {
        gConfig = [NSDictionary dictionaryWithContentsOfFile:ConfigPath()];
        if (!gConfig) gConfig = @{};

        gSpoofDevice   = [gConfig[@"spoofDevice"] boolValue];
        gSpoofLocation = [gConfig[@"spoofLocation"] boolValue];

        gFakeIDFV      = gConfig[@"fakeIDFV"];      // NSString UUID，例如 @"A1B2C3D4-..."
        gFakeName      = gConfig[@"fakeName"];       // NSString，例如 @"iPhone of TrollMask"
        gFakeModel     = gConfig[@"fakeModel"];      // NSString
        gFakeHWMachine = gConfig[@"hwMachine"];      // NSString
        gFakeHWModel   = gConfig[@"hwModel"];        // NSString

        if (gSpoofLocation) {
            double lat = [gConfig[@"latitude"] doubleValue];
            double lon = [gConfig[@"longitude"] doubleValue];
            gFakeLocation = [[CLLocation alloc] initWithLatitude:lat longitude:lon];
        }
    }
}

#pragma mark - UIDevice hooks

static NSString *(*orig_identifierForVendor)(UIDevice *, SEL) = NULL;
static NSString *hook_identifierForVendor(UIDevice *self, SEL _cmd) {
    if (gSpoofDevice && gFakeIDFV.length) return gFakeIDFV;
    return orig_identifierForVendor(self, _cmd);
}

static NSString *(*orig_deviceName)(UIDevice *, SEL) = NULL;
static NSString *hook_deviceName(UIDevice *self, SEL _cmd) {
    if (gSpoofDevice && gFakeName.length) return gFakeName;
    return orig_deviceName(self, _cmd);
}

static NSString *(*orig_deviceModel)(UIDevice *, SEL) = NULL;
static NSString *hook_deviceModel(UIDevice *self, SEL _cmd) {
    if (gSpoofDevice && gFakeModel.length) return gFakeModel;
    return orig_deviceModel(self, _cmd);
}

#pragma mark - sysctl hooks (hw.machine / hw.model)

static int (*orig_sysctlbyname)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) = NULL;
static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (gSpoofDevice && name) {
        NSString *fake = nil;
        if (strcmp(name, "hw.machine") == 0 && gFakeHWMachine.length) {
            fake = gFakeHWMachine;
        } else if (strcmp(name, "hw.model") == 0 && gFakeHWModel.length) {
            fake = gFakeHWModel;
        }
        if (fake) {
            const char *c = [fake UTF8String];
            size_t need = strlen(c) + 1;
            if (oldp == NULL) {
                *oldlenp = need;
                return 0;
            }
            if (*oldlenp >= need) {
                strlcpy((char *)oldp, c, *oldlenp);
                *oldlenp = need;
                return 0;
            }
            // 缓冲区太小：按约定返回 -1 并把所需长度写入 oldlenp
            *oldlenp = need;
            errno = ENOMEM;
            return -1;
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

#pragma mark - CLLocationManager hooks

static CLLocation *(*orig_location)(CLLocationManager *, SEL) = NULL;
static CLLocation *hook_location(CLLocationManager *self, SEL _cmd) {
    if (gSpoofLocation && gFakeLocation) return gFakeLocation;
    return orig_location(self, _cmd);
}

static void (*orig_startUpdatingLocation)(CLLocationManager *, SEL) = NULL;
static void hook_startUpdatingLocation(CLLocationManager *self, SEL _cmd) {
    if (gSpoofLocation && gFakeLocation && self.delegate) {
        // 主动向 delegate 投递伪造定位，不让系统真实定位参与
        [self.delegate locationManager:self didUpdateLocations:@[gFakeLocation]];
        return;
    }
    orig_startUpdatingLocation(self, _cmd);
}

static void (*orig_requestLocation)(CLLocationManager *, SEL) = NULL;
static void hook_requestLocation(CLLocationManager *self, SEL _cmd) {
    if (gSpoofLocation && gFakeLocation && self.delegate) {
        [self.delegate locationManager:self didUpdateLocations:@[gFakeLocation]];
        return;
    }
    orig_requestLocation(self, _cmd);
}

#pragma mark - Constructor

__attribute__((constructor)) static void TrollMaskInit(void) {
    LoadConfig();

    if (gSpoofDevice) {
        MSHookMessageEx([UIDevice class],
                        @selector(identifierForVendor),
                        (IMP)hook_identifierForVendor,
                        (IMP *)&orig_identifierForVendor);
        MSHookMessageEx([UIDevice class],
                        @selector(name),
                        (IMP)hook_deviceName,
                        (IMP *)&orig_deviceName);
        MSHookMessageEx([UIDevice class],
                        @selector(model),
                        (IMP)hook_deviceModel,
                        (IMP *)&orig_deviceModel);
        MSHookFunction((void *)sysctlbyname,
                       (void *)hook_sysctlbyname,
                       (void **)&orig_sysctlbyname);
    }

    if (gSpoofLocation) {
        MSHookMessageEx([CLLocationManager class],
                        @selector(location),
                        (IMP)hook_location,
                        (IMP *)&orig_location);
        MSHookMessageEx([CLLocationManager class],
                        @selector(startUpdatingLocation),
                        (IMP)hook_startUpdatingLocation,
                        (IMP *)&orig_startUpdatingLocation);
        MSHookMessageEx([CLLocationManager class],
                        @selector(requestLocation),
                        (IMP)hook_requestLocation,
                        (IMP *)&orig_requestLocation);
    }
}
