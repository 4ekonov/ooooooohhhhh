#import "OPCCActions.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>

NSString *const OPCCDismissNotification = @"OPCCDismissNotification";
NSString *const OPCCReloadNotification  = @"OPCCReloadNotification";

// ---- приватные интерфейсы (только объявления, классы берём через objc_getClass) ----
@interface SBWiFiManager : NSObject
+ (id)sharedInstance; - (BOOL)wiFiEnabled; - (void)setWiFiEnabled:(BOOL)e; - (NSString *)currentNetworkName;
@end
@interface BluetoothManager : NSObject
+ (id)sharedInstance; - (BOOL)powered; - (BOOL)setPowered:(BOOL)p;
@end
@interface RadiosPreferences : NSObject
- (BOOL)airplaneMode; - (void)setAirplaneMode:(BOOL)m; - (void)synchronize;
@end
@interface SBOrientationLockManager : NSObject
+ (id)sharedInstance; - (BOOL)isUserLocked; - (void)lock; - (void)unlock;
@end
@interface CBBlueLightClient : NSObject
- (BOOL)getBlueLightStatus:(void *)s;
@end
@interface _CDBatterySaver : NSObject
+ (id)batterySaver; - (NSInteger)getPowerMode; - (BOOL)setPowerMode:(NSInteger)m error:(NSError **)e;
@end
@interface AVSystemController : NSObject
+ (id)sharedAVSystemController; - (BOOL)getVolume:(float *)v forCategory:(NSString *)c; - (BOOL)setVolumeTo:(float)v forCategory:(NSString *)c;
@end
@interface DNDModeAssertionDetails : NSObject
+ (id)userRequestedAssertionDetailsWithIdentifier:(NSString *)i modeIdentifier:(NSString *)m lifetime:(id)l;
@end
@interface DNDModeAssertionService : NSObject
+ (id)serviceForClientIdentifier:(NSString *)c;
- (id)takeModeAssertionWithDetails:(id)d error:(NSError **)e;
- (BOOL)invalidateAllActiveModeAssertionsWithError:(NSError **)e;
@end
@interface DNDStateService : NSObject
+ (id)serviceForClientIdentifier:(NSString *)c; - (id)queryCurrentStateWithError:(NSError **)e;
@end
@interface DNDState : NSObject - (BOOL)isActive; @end
@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace; - (BOOL)openSensitiveURL:(NSURL *)u withOptions:(id)o;
@end
@interface CLLocationManager (OPCC)
+ (void)setLocationServicesEnabled:(BOOL)e;
@end
@interface RPScreenRecorder : NSObject
+ (id)sharedRecorder; - (BOOL)isRecording;
- (void)startRecordingWithHandler:(void (^)(NSError *))h;
- (void)stopRecordingWithHandler:(void (^)(id, NSError *))h;
@end
@interface SBScreenshotManager : NSObject
+ (id)sharedInstance; - (void)saveScreenshotsWithCompletion:(id)c;
@end

static void Load(void) {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/CoreDuet.framework/CoreDuet", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/ReplayKit.framework/ReplayKit", RTLD_LAZY);
    });
}

static NSString *const kDNDMode = @"com.apple.donotdisturb.mode.default";
static NSString *const kDNDClient = @"com.opcc.coloroscc";

@implementation OPCCActions

#pragma mark - каталог
+ (NSArray *)allIDs {
    return @[@"torch",@"location",@"airplane",@"devicecontrols",@"ewallet",@"autorotate",@"dnd",
             @"quickshare",@"eyecomfort",@"powersaving",@"screenshot",@"screenrecord",
             @"camera",@"calculator",@"timer",@"mobiledata"];
}
+ (NSArray *)defaultIDs {
    return @[@"torch",@"location",@"airplane",@"devicecontrols",@"ewallet",@"autorotate",@"dnd",
             @"quickshare",@"eyecomfort",@"powersaving",@"screenshot",@"screenrecord",
             @"camera",@"calculator",@"timer",@"mobiledata"];
}
+ (NSArray *)activeIDs {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"OPCC_buttons"];
    return a ?: [self defaultIDs];
}
+ (void)saveActiveIDs:(NSArray *)ids {
    [[NSUserDefaults standardUserDefaults] setObject:ids forKey:@"OPCC_buttons"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:OPCCReloadNotification object:nil];
}
+ (NSDictionary *)meta {
    return @{
     @"torch":@[@"Torch ▾",@"flashlight.off.fill"], @"location":@[@"Location",@"location.fill"],
     @"airplane":@[@"Aeroplane mode",@"airplane"], @"devicecontrols":@[@"Device controls",@"house.fill"],
     @"ewallet":@[@"E-wallet",@"wallet.pass.fill"], @"autorotate":@[@"Auto-rotate",@"arrow.triangle.2.circlepath"],
     @"dnd":@[@"Do Not Disturb ▾",@"moon.fill"], @"quickshare":@[@"Quick Share",@"arrow.triangle.2.circlepath.circle"],
     @"eyecomfort":@[@"Eye Comfort",@"eye.fill"], @"powersaving":@[@"Power saving mode",@"battery.100"],
     @"screenshot":@[@"Screenshot ▾",@"scissors"], @"screenrecord":@[@"Screen recording ▾",@"video.fill"],
     @"camera":@[@"Camera",@"camera.fill"], @"calculator":@[@"Calculator",@"plus.forwardslash.minus"],
     @"timer":@[@"Timer",@"timer"], @"mobiledata":@[@"Mobile data",@"antenna.radiowaves.left.and.right"]};
}
+ (NSString *)titleFor:(NSString *)i  { return [self meta][i][0] ?: i; }
+ (NSString *)symbolFor:(NSString *)i { return [self meta][i][1] ?: @"circle"; }
+ (BOOL)isDimmed:(NSString *)i { return [@[@"devicecontrols",@"ewallet"] containsObject:i]; }

#pragma mark - состояния
+ (BOOL)stateFor:(NSString *)i {
    Load();
    @try {
        if ([i isEqualToString:@"torch"]) {
            AVCaptureDevice *d = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            return d.torchMode == AVCaptureTorchModeOn;
        }
        if ([i isEqualToString:@"location"]) return [CLLocationManager locationServicesEnabled];
        if ([i isEqualToString:@"airplane"]) { RadiosPreferences *p = [[objc_getClass("RadiosPreferences") alloc] init]; return [p airplaneMode]; }
        if ([i isEqualToString:@"autorotate"]) return ![[objc_getClass("SBOrientationLockManager") sharedInstance] isUserLocked];
        if ([i isEqualToString:@"dnd"]) {
            id svc = [objc_getClass("DNDStateService") serviceForClientIdentifier:kDNDClient];
            return [[svc queryCurrentStateWithError:nil] isActive];
        }
        if ([i isEqualToString:@"eyecomfort"]) {
            static CBBlueLightClient *c; if (!c) c = [[objc_getClass("CBBlueLightClient") alloc] init];
            char buf[128] = {0}; [c getBlueLightStatus:buf]; return buf[1] != 0;   // .enabled
        }
        if ([i isEqualToString:@"powersaving"]) return [[objc_getClass("_CDBatterySaver") batterySaver] getPowerMode] != 0;
    } @catch (__unused NSException *e) {}
    return NO;
}

+ (void)tap:(NSString *)i {
    Load();
    BOOL on = [self stateFor:i];
    @try {
        if ([i isEqualToString:@"torch"]) {
            AVCaptureDevice *d = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            if ([d hasTorch] && [d lockForConfiguration:nil]) { d.torchMode = on ? AVCaptureTorchModeOff : AVCaptureTorchModeOn; [d unlockForConfiguration]; }
        } else if ([i isEqualToString:@"location"]) {
            [CLLocationManager setLocationServicesEnabled:!on];
        } else if ([i isEqualToString:@"airplane"]) {
            RadiosPreferences *p = [[objc_getClass("RadiosPreferences") alloc] init]; [p setAirplaneMode:!on]; [p synchronize];
        } else if ([i isEqualToString:@"autorotate"]) {
            id m = [objc_getClass("SBOrientationLockManager") sharedInstance]; on ? [m lock] : [m unlock];
        } else if ([i isEqualToString:@"dnd"]) {
            id svc = [objc_getClass("DNDModeAssertionService") serviceForClientIdentifier:kDNDClient];
            if (on) [svc invalidateAllActiveModeAssertionsWithError:nil];
            else {
                id d = [objc_getClass("DNDModeAssertionDetails") userRequestedAssertionDetailsWithIdentifier:@"com.opcc.coloroscc.assertion" modeIdentifier:kDNDMode lifetime:nil];
                [svc takeModeAssertionWithDetails:d error:nil];
            }
        } else if ([i isEqualToString:@"eyecomfort"]) {
            static CBBlueLightClient *c; if (!c) c = [[objc_getClass("CBBlueLightClient") alloc] init];
            ((BOOL(*)(id, SEL, BOOL))objc_msgSend)(c, NSSelectorFromString(@"setEnabled:"), !on);
        } else if ([i isEqualToString:@"powersaving"]) {
            [[objc_getClass("_CDBatterySaver") batterySaver] setPowerMode:on ? 0 : 1 error:nil];
        } else if ([i isEqualToString:@"quickshare"]) {
            [self openSettingsURL:@"prefs:root=General&path=AIRDROP"]; [self dismissCC];
        } else if ([i isEqualToString:@"screenshot"]) {
            [self dismissCC];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                id sm = [objc_getClass("SBScreenshotManager") sharedInstance];
                if ([sm respondsToSelector:@selector(saveScreenshotsWithCompletion:)]) [sm saveScreenshotsWithCompletion:nil];
            });
        } else if ([i isEqualToString:@"screenrecord"]) {
            // ЭКСПЕРИМЕНТАЛЬНО: ReplayKit из SpringBoard может не стартовать на части версий iOS
            id rec = [objc_getClass("RPScreenRecorder") sharedRecorder];
            if ([rec isRecording]) [rec stopRecordingWithHandler:^(id p, NSError *e) {}];
            else [rec startRecordingWithHandler:^(NSError *e) {}];
            [self dismissCC];
        } else if ([i isEqualToString:@"devicecontrols"]) { [self openApp:@"com.apple.Home"]; [self dismissCC]; }
        else if ([i isEqualToString:@"ewallet"])    { [self openApp:@"com.apple.Passbook"]; [self dismissCC]; }
        else if ([i isEqualToString:@"camera"])     { [self openApp:@"com.apple.camera"]; [self dismissCC]; }
        else if ([i isEqualToString:@"calculator"]) { [self openApp:@"com.apple.calculator"]; [self dismissCC]; }
        else if ([i isEqualToString:@"timer"])      { [self openApp:@"com.apple.mobiletimer"]; [self dismissCC]; }
        else if ([i isEqualToString:@"mobiledata"]) { [self openSettingsURL:@"prefs:root=MOBILE_DATA_SETTINGS_ID"]; [self dismissCC]; }
    } @catch (__unused NSException *e) {}
}

+ (void)longPress:(NSString *)i {
    NSDictionary *m = @{@"torch":@"", @"location":@"prefs:root=Privacy&path=LOCATION", @"airplane":@"prefs:root=AIRPLANE_MODE",
                        @"dnd":@"prefs:root=DO_NOT_DISTURB", @"powersaving":@"prefs:root=BATTERY_USAGE",
                        @"eyecomfort":@"prefs:root=DISPLAY", @"quickshare":@"prefs:root=General&path=AIRDROP",
                        @"mobiledata":@"prefs:root=MOBILE_DATA_SETTINGS_ID"};
    NSString *u = m[i];
    if (u.length) { [self openSettingsURL:u]; [self dismissCC]; }
}

+ (void)dismissCC { [[NSNotificationCenter defaultCenter] postNotificationName:OPCCDismissNotification object:nil]; }

#pragma mark - ползунки
+ (float)brightness { return [UIScreen mainScreen].brightness; }
+ (void)setBrightness:(float)v {
    Load();
    v = MAX(0.01f, MIN(1.f, v));
    void (*set)(float, int) = dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessSet");
    if (set) set(v, 1); else [UIScreen mainScreen].brightness = v;
}
+ (float)volume {
    float v = 0; [[objc_getClass("AVSystemController") sharedAVSystemController] getVolume:&v forCategory:@"Audio/Video"]; return v;
}
+ (void)setVolume:(float)v {
    [[objc_getClass("AVSystemController") sharedAVSystemController] setVolumeTo:MAX(0, MIN(1, v)) forCategory:@"Audio/Video"];
}

#pragma mark - плитки
+ (BOOL)wifiOn { Load(); return [[objc_getClass("SBWiFiManager") sharedInstance] wiFiEnabled]; }
+ (NSString *)wifiName { Load(); NSString *n = [[objc_getClass("SBWiFiManager") sharedInstance] currentNetworkName]; return n.length ? n : nil; }
+ (void)setWifi:(BOOL)on { Load(); [[objc_getClass("SBWiFiManager") sharedInstance] setWiFiEnabled:on]; }
+ (BOOL)btOn { Load(); return [[objc_getClass("BluetoothManager") sharedInstance] powered]; }
+ (void)setBT:(BOOL)on { Load(); id m = [objc_getClass("BluetoothManager") sharedInstance]; [m setPowered:on]; ((BOOL(*)(id, SEL, BOOL))objc_msgSend)(m, NSSelectorFromString(@"setEnabled:"), on); }

+ (id)ringer {
    @try { return [[UIApplication sharedApplication] valueForKey:@"ringerControl"]; } @catch (__unused NSException *e) { return nil; }
}
+ (NSInteger)ringerMode {
    id r = [self ringer];
    BOOL muted = r ? ((BOOL(*)(id, SEL))objc_msgSend)(r, NSSelectorFromString(@"isRingerMuted")) : NO;
    if (!muted) return 0;
    return (NSInteger)[[NSUserDefaults standardUserDefaults] integerForKey:@"OPCC_silentKind"] == 1 ? 1 : 2;
}
+ (void)setRingerMode:(NSInteger)m {
    [[NSUserDefaults standardUserDefaults] setInteger:m forKey:@"OPCC_silentKind"];
    id r = [self ringer];
    SEL s = NSSelectorFromString(@"setRingerMuted:");
    if (r && [r respondsToSelector:s]) ((void(*)(id, SEL, BOOL))objc_msgSend)(r, s, m != 0);
}

+ (void)openApp:(NSString *)b {
    UIApplication *app = [UIApplication sharedApplication];
    SEL sel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([app respondsToSelector:sel]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(app, sel, b, NO);
}
+ (void)openSettingsURL:(NSString *)u {
    [[objc_getClass("LSApplicationWorkspace") defaultWorkspace] openSensitiveURL:[NSURL URLWithString:u] withOptions:nil];
}
@end
