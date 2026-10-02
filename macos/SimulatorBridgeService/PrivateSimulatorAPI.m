#import "PrivateSimulatorAPI.h"
#import <dlfcn.h>

// SimulatorGate と同じ ObjC の経路に限定し、非公開部品はこのファイルに閉じ込める。
@interface NSObject (SimulatorPrivateAPI)
+ (id)sharedServiceContextForDeveloperDir:(NSString *)path error:(NSError **)error;
- (id)defaultDeviceSetWithError:(NSError **)error;
- (NSArray *)devices;
- (NSUUID *)UDID;
- (NSInteger)state;
- (id)io;
- (void)updateIOPorts;
- (NSArray *)ioPorts;
- (id)descriptor;
- (IOSurface *)framebufferSurface;
- (void)registerScreenCallbacksWithUUID:(NSUUID *)uuid callbackQueue:(dispatch_queue_t)queue frameCallback:(void (^)(void))frame surfacesChangedCallback:(void (^)(IOSurface *, IOSurface *))surfaces propertiesChangedCallback:(void (^)(id))properties;
- (void)unregisterScreenCallbacksWithUUID:(NSUUID *)uuid;
@end

@interface PrivateSimulatorAPI ()
@property BOOL coreSimulatorLoaded;
@property BOOL simulatorKitLoaded;
@property NSString *xcodeBuild;
@property NSString *reason;
@property NSString *developer;
@property id io;
@property NSMutableArray *descriptors;
@property NSMutableDictionary<NSString *, IOSurface *> *surfaces;
@property NSUUID *token;
@property uint32_t surfaceID;
@property(copy) void (^changed)(IOSurface *);
@end

@implementation PrivateSimulatorAPI
- (instancetype)init {
    if ((self = [super init])) _xcodeBuild = @"不明";
    return self;
}
- (BOOL)load {
    if (self.coreSimulatorLoaded && self.simulatorKitLoaded && !self.reason) return YES;
    @try {
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xcode-select"];
        task.arguments = @[@"-p"];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        NSError *error = nil;
        if (![task launchAndReturnError:&error]) { self.reason = error.localizedDescription; return NO; }
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        [task waitUntilExit];
        self.developer = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (task.terminationStatus != 0 || !self.developer.length) { self.reason = @"Xcode の選択パスを取得できません"; return NO; }
        NSDictionary *version = [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:[self.developer stringByAppendingPathComponent:@"../version.plist"]] error:&error];
        self.xcodeBuild = version[@"ProductBuildVersion"] ?: @"不明";
        self.coreSimulatorLoaded = dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW | RTLD_GLOBAL) != NULL;
        if (!self.coreSimulatorLoaded) { self.reason = [NSString stringWithUTF8String:dlerror()]; return NO; }
        NSString *kit = [self.developer stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"];
        self.simulatorKitLoaded = dlopen(kit.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL) != NULL;
        if (!self.simulatorKitLoaded) { self.reason = [NSString stringWithUTF8String:dlerror()]; return NO; }
        if (![NSClassFromString(@"SimServiceContext") respondsToSelector:@selector(sharedServiceContextForDeveloperDir:error:)] ||
            !NSProtocolFromString(@"SimDisplayIOSurfaceRenderable")) {
            self.reason = @"画面取得に必要なクラス・プロトコルがありません";
            return NO;
        }
        self.reason = nil;
        return YES;
    } @catch (NSException *exception) { self.reason = exception.reason; return NO; }
}
- (BOOL)attach:(NSString *)udid queue:(dispatch_queue_t)queue changed:(void (^)(IOSurface *))changed error:(NSError **)error {
    [self detach];
    @try {
        if (![[NSUUID alloc] initWithUUIDString:udid]) return [self fail:@"端末 ID が不正です" error:error];
        if (![self load]) return [self fail:self.reason error:error];
        id context = [NSClassFromString(@"SimServiceContext") sharedServiceContextForDeveloperDir:self.developer error:error];
        if (![context respondsToSelector:@selector(defaultDeviceSetWithError:)]) return [self fail:@"端末セットの API がありません" error:error];
        id set = [context defaultDeviceSetWithError:error];
        if (![set respondsToSelector:@selector(devices)]) return [self fail:@"端末一覧の API がありません" error:error];
        id selected = nil;
        for (id device in [set devices]) {
            if ([device respondsToSelector:@selector(UDID)] && [[[device UDID] UUIDString] isEqualToString:udid]) selected = device;
        }
        if (![selected respondsToSelector:@selector(state)] || [selected state] != 3) return [self fail:@"端末が起動していません" error:error];
        if (![selected respondsToSelector:@selector(io)]) return [self fail:@"端末の表示 API がありません" error:error];
        self.io = [selected io];
        if (![self.io respondsToSelector:@selector(updateIOPorts)] || ![self.io respondsToSelector:@selector(ioPorts)]) return [self fail:@"表示ポートの API がありません" error:error];
        [self.io updateIOPorts];
        self.token = NSUUID.UUID;
        self.descriptors = [NSMutableArray array];
        self.surfaces = [NSMutableDictionary dictionary];
        self.changed = changed;
        __weak PrivateSimulatorAPI *weakSelf = self;
        NSUUID *token = self.token;
        for (id port in [self.io ioPorts]) {
            if (![port respondsToSelector:@selector(descriptor)]) continue;
            id descriptor = [port descriptor];
            if (![descriptor respondsToSelector:@selector(framebufferSurface)] ||
                ![descriptor respondsToSelector:@selector(unregisterScreenCallbacksWithUUID:)] ||
                ![descriptor respondsToSelector:@selector(registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:)]) continue;
            [self.descriptors addObject:descriptor];
            NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)self.descriptors.count];
            [descriptor registerScreenCallbacksWithUUID:token callbackQueue:queue frameCallback:^{} surfacesChangedCallback:^(IOSurface *surface, IOSurface *masked) {
                PrivateSimulatorAPI *owner = weakSelf;
                if (![owner.token isEqual:token]) return;
                if (surface) owner.surfaces[key] = surface;
                else [owner.surfaces removeObjectForKey:key];
                [owner publish];
            } propertiesChangedCallback:^(id properties) {}];
            IOSurface *initial = [descriptor framebufferSurface];
            if (initial) self.surfaces[key] = initial;
        }
        if (!self.descriptors.count) return [self fail:@"対応する表示ポートがありません" error:error];
        [self publish];
        return YES;
    } @catch (NSException *exception) { return [self fail:exception.reason error:error]; }
}
- (void)publish {
    IOSurface *best = nil;
    for (IOSurface *surface in self.surfaces.allValues) {
        if (!best || IOSurfaceGetWidth((__bridge IOSurfaceRef)surface) * IOSurfaceGetHeight((__bridge IOSurfaceRef)surface) >
            IOSurfaceGetWidth((__bridge IOSurfaceRef)best) * IOSurfaceGetHeight((__bridge IOSurfaceRef)best)) best = surface;
    }
    if (!best) return;
    uint32_t identifier = IOSurfaceGetID((__bridge IOSurfaceRef)best);
    if (identifier == self.surfaceID) return;
    self.surfaceID = identifier;
    if (self.changed) self.changed(best);
}
- (BOOL)fail:(NSString *)message error:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:@"Phlox.SimulatorBridge" code:1 userInfo:@{NSLocalizedDescriptionKey: message ?: @"画面取得に失敗しました"}];
    [self detach];
    return NO;
}
- (void)detach {
    NSUUID *token = self.token;
    self.token = nil;
    self.changed = nil;
    for (id descriptor in self.descriptors) {
        @try { [descriptor unregisterScreenCallbacksWithUUID:token]; }
        @catch (NSException *exception) { NSLog(@"表示コールバックの解除に失敗しました: %@", exception); }
    }
    self.descriptors = nil;
    self.surfaces = nil;
    self.io = nil;
    self.surfaceID = 0;
}
@end
