#import "PrivateSimulatorAPI.h"
#import <dlfcn.h>
#import <AppKit/AppKit.h>

// SimulatorGate と同じ ObjC の経路に限定し、非公開部品はこのファイルに閉じ込める。
@interface NSObject (SimulatorPrivateAPI)
+ (id)sharedServiceContextForDeveloperDir:(NSString *)path error:(NSError **)error;
- (id)defaultDeviceSetWithError:(NSError **)error;
- (NSArray *)devices;
- (NSUUID *)UDID;
- (NSInteger)state;
- (id)io;
- (id)deviceType;
- (float)mainScreenScale;
- (void)updateIOPorts;
- (NSArray *)ioPorts;
- (id)descriptor;
- (IOSurface *)framebufferSurface;
- (void)registerScreenCallbacksWithUUID:(NSUUID *)uuid callbackQueue:(dispatch_queue_t)queue frameCallback:(void (^)(void))frame surfacesChangedCallback:(void (^)(IOSurface *, IOSurface *))surfaces propertiesChangedCallback:(void (^)(id))properties;
- (void)unregisterScreenCallbacksWithUUID:(NSUUID *)uuid;
- (id)initWithDevice:(id)device error:(NSError **)error;
- (void)sendWithMessage:(void *)message freeWhenDone:(BOOL)free completionQueue:(dispatch_queue_t)queue completion:(void (^)(NSError *))completion;
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
@property id hid;
@property dispatch_queue_t queue;
@property void *mouseFunction;
@property void *keyFunction;
@property void *buttonFunction;
@property void *usageFunction;
@property NSMutableSet<NSNumber *> *heldKeys;
@property NSMutableSet<NSNumber *> *syntheticModifiers;
@property BOOL touching;
@property CGPoint touchPoint;
@property NSUInteger inputGeneration;
@property BOOL homeDown;
@property NSUInteger homeGeneration;
@property double screenScale;
@property BOOL scrolling;
@property BOOL sendingScrollTouch;
@property BOOL scrollAnimating;
@property BOOL phasedScroll;
@property CGPoint scrollTarget;
@property double pendingScrollX;
@property double pendingScrollY;
@property CGPoint pendingScrollPoint;
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
        void *handle = dlopen(kit.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        self.simulatorKitLoaded = handle != NULL;
        if (!self.simulatorKitLoaded) { self.reason = [NSString stringWithUTF8String:dlerror()]; return NO; }
        if (![NSClassFromString(@"SimServiceContext") respondsToSelector:@selector(sharedServiceContextForDeveloperDir:error:)] ||
            !NSProtocolFromString(@"SimDisplayIOSurfaceRenderable")) {
            self.reason = @"画面取得に必要なクラス・プロトコルがありません";
            return NO;
        }
        self.mouseFunction = dlsym(handle, "IndigoHIDMessageForMouseNSEvent");
        self.keyFunction = dlsym(handle, "IndigoHIDMessageForKeyboardArbitrary");
        self.buttonFunction = dlsym(handle, "IndigoHIDMessageForButton");
        self.usageFunction = dlsym(handle, "hidUsageForCGKeyCode");
        Class hidClass = NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient");
        if (![hidClass instancesRespondToSelector:@selector(initWithDevice:error:)] ||
            ![hidClass instancesRespondToSelector:@selector(sendWithMessage:freeWhenDone:completionQueue:completion:)] ||
            !self.mouseFunction || !self.keyFunction || !self.buttonFunction || !self.usageFunction) {
            self.reason = @"入力に必要な HID クラス・関数がありません";
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
        id type = [selected respondsToSelector:@selector(deviceType)] ? [selected deviceType] : nil;
        if (![type respondsToSelector:@selector(mainScreenScale)]) return [self fail:@"端末の画面倍率 API がありません" error:error];
        self.screenScale = [type mainScreenScale];
        if (!isfinite(self.screenScale) || self.screenScale <= 0) return [self fail:@"端末の画面倍率が不正です" error:error];
        self.queue = queue;
        self.hid = [[NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient") alloc] initWithDevice:selected error:error];
        if (!self.hid) return [self fail:@"HID クライアントを作成できません" error:error];
        self.heldKeys = [NSMutableSet set];
        self.syntheticModifiers = [NSMutableSet set];
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
- (void)send:(void *)message {
    if (!message || !self.hid) {
        if (message) free(message);
        NSLog(@"HID メッセージまたは接続がありません");
        return;
    }
    @try {
        // detach が参照を離しても、配送完了までは送信元を保持する。
        id client = self.hid;
        [client sendWithMessage:message freeWhenDone:YES completionQueue:self.queue completion:^(NSError *error) {
            (void)client;
            if (error) NSLog(@"HID 入力の配送に失敗しました: %@", error.localizedDescription);
        }];
    } @catch (NSException *exception) { NSLog(@"HID 入力の配送で例外が発生しました: %@", exception); }
}
- (BOOL)validPoint:(CGPoint)point {
    return isfinite(point.x) && isfinite(point.y) && point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1;
}
- (void)sendTouch:(NSInteger)phase x:(double)x y:(double)y {
    CGPoint point = CGPointMake(x, y);
    if (self.hid && phase == 0 && [self validPoint:point] && self.scrolling && !self.sendingScrollTouch) [self cancelScroll];
    if (self.hid && phase == 0 && [self validPoint:point] && self.touching) [self sendTouch:2 x:self.touchPoint.x y:self.touchPoint.y];
    if (!self.hid || (self.scrolling && !self.sendingScrollTouch) || phase < 0 || phase > 2 || ![self validPoint:point] ||
        (phase != 0 && !self.touching)) {
        NSLog(@"不正な接触入力または接触状態です");
        return;
    }
    self.touchPoint = point;
    self.touching = phase != 2;
    if (phase == 2) self.inputGeneration++;
    // Indigo はここで正規化するため、単位矩形を渡して倍率の二重適用を避ける。
    // 移動も Down を使う。Dragged は接触を維持しない。
    void *(*function)(CGPoint *, CGPoint *, uint32_t, NSUInteger, CGSize, uint32_t) = self.mouseFunction;
    [self send:function(&point, NULL, 0x32, phase == 2 ? NSEventTypeLeftMouseUp : NSEventTypeLeftMouseDown, CGSizeMake(1, 1), 0)];
}
- (void)scrollTouch:(NSInteger)phase x:(double)x y:(double)y {
    self.sendingScrollTouch = YES;
    [self sendTouch:phase x:x y:y];
    self.sendingScrollTouch = NO;
}
- (void)cancelScroll {
    self.inputGeneration++;
    BOOL wasScrolling = self.scrolling;
    self.scrolling = NO;
    self.scrollAnimating = NO;
    self.phasedScroll = NO;
    self.pendingScrollX = 0;
    self.pendingScrollY = 0;
    if (wasScrolling && self.touching) [self sendTouch:2 x:self.touchPoint.x y:self.touchPoint.y];
}
- (void)finishScroll {
    NSUInteger generation = ++self.inputGeneration;
    CGPoint start = self.touchPoint, end = self.scrollTarget;
    // 同じ座標の再送は iOS に移動として届かない。残り1ptを120msで減速して終点へ置き、さらに120ms止める。
    for (NSUInteger step = 1; step <= 6; step++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, step * 40 * NSEC_PER_MSEC), self.queue, ^{
            if (self.inputGeneration != generation || !self.hid || !self.touching) return;
            double progress = fmin(1, step / 3.0);
            [self scrollTouch:step == 6 ? 2 : 1 x:start.x + (end.x - start.x) * progress y:start.y + (end.y - start.y) * progress];
            if (step == 6) self.scrolling = NO;
        });
    }
}
- (void)sendScroll:(double)dx dy:(double)dy x:(double)x y:(double)y phase:(NSInteger)phase {
    CGPoint start = CGPointMake(x, y);
    if (!self.hid || !isfinite(dx) || !isfinite(dy) || ![self validPoint:start] || phase < 0 || phase > 4 || (self.touching && !self.scrolling)) {
        NSLog(@"不正なスクロール入力または接触中です");
        return;
    }
    if (phase == 4) { [self cancelScroll]; return; }
    if (phase == 1 || (self.scrolling && self.phasedScroll != (phase != 0))) [self cancelScroll];
    if ((phase == 2 || phase == 3) && !self.scrolling) return;
    IOSurface *surface = nil;
    for (IOSurface *candidate in self.surfaces.allValues) {
        if (!surface || candidate.width * candidate.height > surface.width * surface.height) surface = candidate;
    }
    if (!surface || !surface.width || !surface.height) { NSLog(@"スクロールに必要な画面寸法がありません"); return; }
    double width = surface.width / self.screenScale, height = surface.height / self.screenScale;
    double nextX = self.pendingScrollX + dx, nextY = self.pendingScrollY + dy;
    if (!isfinite(nextX) || !isfinite(nextY)) { NSLog(@"スクロールの累積値が不正です"); return; }
    self.pendingScrollX = nextX;
    self.pendingScrollY = nextY;
    self.pendingScrollPoint = start;
    if (!self.scrolling) { self.scrolling = YES; self.phasedScroll = phase != 0; }
    if (self.scrollAnimating) return;
    if (!self.touching) {
        // 小量は合算して10ptに達するまで接触しない。ボタン上でタップに化けるのを防ぐ。
        if (hypot(nextX, nextY) < 10) {
            if (phase == 3) [self cancelScroll];
            return;
        }
        // 端のシステムジェスチャーを避ける44ptの内側。小画面では寸法の1/4までにする。
        double insetX = fmin(44, width / 4) / width, insetY = fmin(44, height / 4) / height;
        start = CGPointMake(fmin(1 - insetX, fmax(insetX, x)), fmin(1 - insetY, fmax(insetY, y)));
        [self scrollTouch:0 x:start.x y:start.y];
        self.scrollTarget = start;
    } else start = self.scrollTarget;
    self.pendingScrollX = 0;
    self.pendingScrollY = 0;
    CGPoint end = CGPointMake(fmin(1, fmax(0, start.x + nextX / width)), fmin(1, fmax(0, start.y + nextY / height)));
    self.scrollTarget = end;
    double distance = hypot((end.x - self.touchPoint.x) * width, (end.y - self.touchPoint.y) * height);
    // 最後の1ptは終了時の減速に残す。差分の合算は目標点を基準にして欠落させない。
    if (distance > 0) {
        double progress = fmax(0, distance - 1) / distance;
        end = CGPointMake(self.touchPoint.x + (end.x - self.touchPoint.x) * progress, self.touchPoint.y + (end.y - self.touchPoint.y) * progress);
    }
    start = self.touchPoint;
    NSUInteger generation = ++self.inputGeneration;
    if (phase != 0) {
        [self scrollTouch:1 x:end.x y:end.y];
        if (phase == 3) [self finishScroll];
        return;
    }
    self.scrollAnimating = YES;
    // ホイールも移動と停止を分け、接触したまま差分を合算する。
    NSUInteger steps = MAX(4, (NSUInteger)ceil(distance / 5));
    for (NSUInteger step = 1; step <= steps; step++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, step * 20 * NSEC_PER_MSEC), self.queue, ^{
            if (self.inputGeneration != generation || !self.hid || !self.touching) return;
            double progress = (double)step / steps;
            [self scrollTouch:1 x:start.x + (end.x - start.x) * progress y:start.y + (end.y - start.y) * progress];
            if (step == steps) {
                self.scrollAnimating = NO;
                CGPoint nextPoint = self.pendingScrollPoint;
                if (self.pendingScrollX != 0 || self.pendingScrollY != 0) [self sendScroll:0 dy:0 x:nextPoint.x y:nextPoint.y phase:0];
                else [self finishScroll];
            }
        });
    }
}
- (void)keyUsage:(uint32_t)usage down:(BOOL)down {
    if (down) [self.heldKeys addObject:@(usage)];
    else [self.heldKeys removeObject:@(usage)];
    void *(*function)(int32_t, int32_t) = self.keyFunction;
    [self send:function(usage, down ? 1 : 2)];
}
- (void)sendKey:(uint16_t)keyCode modifiers:(NSUInteger)modifiers down:(BOOL)down {
    NSUInteger allowed = NSEventModifierFlagDeviceIndependentFlagsMask | 0xffff;
    if (!self.hid || keyCode > 127 || (modifiers & ~allowed)) { NSLog(@"不正なキー入力です"); return; }
    uint32_t (*map)(uint32_t) = self.usageFunction;
    uint32_t usage = map(keyCode);
    if (!usage || usage > 255) { NSLog(@"対応する HID キーがありません: %u", keyCode); return; }
    if (!down && ![self.heldKeys containsObject:@(usage)]) return;
    // 修飾キーを押した後から画面が first responder になっても、通常キーのフラグを反映する。
    // 左右の物理修飾キーは個別の flagsChanged で扱う。
    if (down && usage < 0xe0 && ![self.heldKeys containsObject:@(usage)]) {
        const NSUInteger flags[] = {NSEventModifierFlagControl, NSEventModifierFlagShift, NSEventModifierFlagOption, NSEventModifierFlagCommand};
        for (NSUInteger index = 0; index < 4; index++) {
            NSNumber *left = @(0xe0 + index), *right = @(0xe4 + index);
            BOOL wanted = (modifiers & flags[index]) != 0;
            if (!wanted && [self.syntheticModifiers containsObject:left]) {
                [self keyUsage:left.unsignedIntValue down:NO];
                [self.syntheticModifiers removeObject:left];
            } else if (wanted && ![self.heldKeys containsObject:left] && ![self.heldKeys containsObject:right]) {
                [self.syntheticModifiers addObject:left];
                [self keyUsage:left.unsignedIntValue down:YES];
            }
        }
    }
    // 合成済みの左修飾キーを実際の押下として引き継ぐ。
    if (usage >= 0xe0) [self.syntheticModifiers removeObject:@(usage)];
    [self keyUsage:usage down:down];
    BOOL ordinaryHeld = NO;
    for (NSNumber *held in self.heldKeys) if (held.unsignedIntValue < 0xe0) ordinaryHeld = YES;
    if (!ordinaryHeld) {
        for (NSNumber *held in self.syntheticModifiers.copy) [self keyUsage:held.unsignedIntValue down:NO];
        [self.syntheticModifiers removeAllObjects];
    }
}
- (void)sendButton:(NSInteger)button {
    if (!self.hid || button != 0 || self.homeDown) { NSLog(@"不正なホーム入力または押下中です"); return; }
    self.homeDown = YES;
    void *(*function)(int32_t, int32_t, int32_t) = self.buttonFunction;
    [self send:function(0, 1, 0x33)];
    NSUInteger generation = ++self.homeGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), self.queue, ^{
        if (!self.hid || !self.homeDown || self.homeGeneration != generation) return;
        self.homeDown = NO;
        [self send:function(0, 2, 0x33)];
    });
}
- (void)releaseAll {
    [self cancelScroll];
    self.homeGeneration++;
    if (self.touching) [self sendTouch:2 x:self.touchPoint.x y:self.touchPoint.y];
    for (NSNumber *usage in self.heldKeys.copy) [self keyUsage:usage.unsignedIntValue down:NO];
    [self.syntheticModifiers removeAllObjects];
    if (self.homeDown) {
        self.homeDown = NO;
        void *(*function)(int32_t, int32_t, int32_t) = self.buttonFunction;
        [self send:function(0, 2, 0x33)];
    }
}
- (void)detach {
    [self releaseAll];
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
    self.hid = nil;
    self.queue = nil;
}
@end
