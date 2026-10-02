#import "GateHost.h"
#import "../Shared/Bridge.h"
#import <QuartzCore/QuartzCore.h>

@interface GateHost () <GateClient>
@property NSXPCConnection *connection;
@property id<GateService> service;
@property IOSurface *surface;
@property IOSurface *firstSurface;
@property CALayer *screen;
@property NSFileHandle *log;
@property NSTimer *timer;
@property NSDate *start;
@property uint32_t lastSeed;
@property NSUInteger tick;
@property NSUInteger received;
@property BOOL ready;
@property BOOL touching;
@property NSMutableSet<NSNumber *> *heldKeys;
@end

@implementation GateHost
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.wantsLayer = YES;
    self.screen = [CALayer layer];
    self.screen.contentsGravity = kCAGravityResizeAspect;
    [self.layer addSublayer:self.screen];
    NSButton *home = [NSButton buttonWithTitle:@"ホーム" target:self action:@selector(home:)];
    home.frame = NSMakeRect(8, 878, 90, 30);
    [self addSubview:home];
    self.heldKeys = [NSMutableSet set];
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    self.log = [NSFileHandle fileHandleForWritingAtPath:environment[@"GATE_HOST_LOG"]];
    self.connection = [[NSXPCConnection alloc] initWithServiceName:@"com.phlox.prototype.SimulatorGate.Service"];
    self.connection.remoteObjectInterface = GateServiceInterface();
    self.connection.exportedInterface = GateClientInterface();
    self.connection.exportedObject = self;
    __weak GateHost *weakSelf = self;
    self.connection.invalidationHandler = ^{ dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf record:@{@"切断":@YES}]; weakSelf.ready = NO; }); };
    [self.connection resume];
    self.service = [self.connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf record:@{@"XPC失敗":error.description}]; });
    }];
    [self.service attach:environment[@"GATE_UDID"] developer:environment[@"GATE_DEVELOPER"] log:environment[@"GATE_SERVICE_LOG"] reply:^(NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf record:@{@"接続結果":error.length ? error : @"成功"}];
            weakSelf.ready = !error.length;
            if (weakSelf.ready) [weakSelf begin];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!weakSelf.ready) { [weakSelf record:@{@"接続期限":@"5秒以内に接続成功を確認できません"}]; }
    });
    return self;
}
- (void)layout {
    [super layout];
    self.screen.frame = NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height - 40);
}
- (void)record:(NSDictionary *)values {
    NSMutableDictionary *row = [values mutableCopy];
    row[@"時刻"] = @([[NSDate date] timeIntervalSince1970]);
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:row options:0 error:&error];
    if (!data) { NSLog(@"ログの符号化失敗: %@", error); return; }
    [self.log writeData:data];
    [self.log writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
}
- (void)surface:(IOSurface *)surface {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.surface = surface;
        if (!self.firstSurface) self.firstSurface = surface;
        self.received++;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        self.screen.contents = surface;
        [CATransaction commit];
        [self record:@{@"surface受信":@(GateSurfaceID(surface)), @"seed":@(surface.seed), @"surface受信数":@(self.received)}];
    });
}
- (void)begin {
    self.start = [NSDate date];
    __weak GateHost *weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer) { [weakSelf sample]; }];
    [self record:@{@"ウィンドウ番号":@(self.window.windowNumber), @"PID":@(getpid())}];
    if ([NSProcessInfo.processInfo.environment[@"GATE_AUTOMATE"] isEqualToString:@"1"]) {
        [self after:12 action:^{ [weakSelf tapX:0.5 y:180.0/874]; }];
        [self after:14 action:^{ [weakSelf touch:0 x:0.25 y:280.0/874]; [weakSelf dragStep:1]; }];
        [self after:16 action:^{ [weakSelf tapX:0.5 y:380.0/874]; }];
        [self after:18 action:^{ [weakSelf keyUsage:4 down:YES]; }];
        [self after:18.1 action:^{ [weakSelf keyUsage:4 down:NO]; }];
        [self after:19 action:^{ [weakSelf keyUsage:0xe1 down:YES]; }];
        [self after:19.1 action:^{ [weakSelf keyUsage:5 down:YES]; }];
        [self after:19.2 action:^{ [weakSelf keyUsage:5 down:NO]; }];
        [self after:19.3 action:^{ [weakSelf keyUsage:0xe1 down:NO]; }];
        [self after:25 action:^{ [weakSelf home:nil]; }];
        [self after:29 action:^{ [weakSelf finish]; }];
    }
}
- (void)after:(double)seconds action:(dispatch_block_t)action {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds*NSEC_PER_SEC), dispatch_get_main_queue(), action);
}
- (void)sample {
    if (!self.surface) return;
    self.tick++;
    double elapsed = -self.start.timeIntervalSinceNow;
    NSString *mode = elapsed < 4 ? @"初回設定のみ" : elapsed < 8 ? @"同じsurface再設定" : @"nil後に再設定";
    uint32_t seed = self.surface.seed;
    if (seed != self.lastSeed && elapsed >= 4) {
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        if (elapsed >= 8) self.screen.contents = nil;
        self.screen.contents = self.surface;
        [CATransaction commit];
    }
    if (self.tick % 6 == 0) [self record:@{@"surfaceID":@(GateSurfaceID(self.surface)), @"seed":@(seed), @"初回ID":@(GateSurfaceID(self.firstSurface)), @"初回seed":@(self.firstSurface.seed), @"表示方式":mode, @"経過秒":@(elapsed), @"受信数":@(self.received)}];
    self.lastSeed = seed;
}
- (void)touch:(NSInteger)phase x:(double)x y:(double)y {
    if (!self.ready) return;
    self.touching = phase != 2;
    [self.service touch:phase x:x y:y reply:^(NSString *error) { dispatch_async(dispatch_get_main_queue(), ^{ [self record:@{@"タッチ配送":error.length ? error : @"成功", @"phase":@(phase), @"x":@(x), @"y":@(y)}]; }); }];
}
- (void)tapX:(double)x y:(double)y {
    [self touch:0 x:x y:y];
    [self after:0.1 action:^{ [self touch:2 x:x y:y]; }];
}
- (void)dragStep:(NSInteger)step {
    // 長い期限のタイマー群がまとめて配送されても、移動の間隔を保つ。
    [self after:0.05 action:^{
        [self touch:step <= 10 ? 1 : 2 x:step <= 10 ? 0.25+step*0.05 : 0.75 y:280.0/874];
        if (step <= 10) [self dragStep:step+1];
    }];
}
- (void)keyUsage:(uint32_t)usage down:(BOOL)down {
    if (!self.ready) return;
    if (down) [self.heldKeys addObject:@(usage)]; else [self.heldKeys removeObject:@(usage)];
    [self.service key:usage down:down reply:^(NSString *error) { dispatch_async(dispatch_get_main_queue(), ^{ [self record:@{@"キー配送":error.length ? error : @"成功", @"usage":@(usage), @"押下":@(down)}]; }); }];
}
- (void)home:(id)sender {
    if (!self.ready) return;
    [self.service home:^(NSString *error) { dispatch_async(dispatch_get_main_queue(), ^{ [self record:@{@"ホーム配送":error.length ? error : @"成功"}]; }); }];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent *)event { [self.window makeFirstResponder:self]; [self mouse:event phase:0]; }
- (void)mouseDragged:(NSEvent *)event { if (self.touching) [self mouse:event phase:1]; }
- (void)mouseUp:(NSEvent *)event { if (self.touching) [self mouse:event phase:2]; }
- (void)mouse:(NSEvent *)event phase:(NSInteger)phase {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect rect = self.screen.frame;
    if (NSPointInRect(point, rect)) [self touch:phase x:point.x/rect.size.width y:1-point.y/rect.size.height];
    else if (phase == 2) [self touch:2 x:0.5 y:0.5];
}
- (void)keyDown:(NSEvent *)event {
    // 関門で使う物理キー A・B と Shift のみに絞る。
    if (event.keyCode == 0) [self keyUsage:4 down:YES];
    if (event.keyCode == 11) [self keyUsage:5 down:YES];
}
- (void)keyUp:(NSEvent *)event {
    if (event.keyCode == 0) [self keyUsage:4 down:NO];
    if (event.keyCode == 11) [self keyUsage:5 down:NO];
}
- (void)flagsChanged:(NSEvent *)event { if (event.keyCode == 56) [self keyUsage:0xe1 down:(event.modifierFlags & NSEventModifierFlagShift) != 0]; }
- (BOOL)resignFirstResponder {
    for (NSNumber *usage in self.heldKeys.copy) [self keyUsage:usage.unsignedIntValue down:NO];
    if (self.touching) [self touch:2 x:0.5 y:0.5];
    return [super resignFirstResponder];
}
- (void)finish {
    [self resignFirstResponder];
    [self.timer invalidate];
    [self.service detach:^{ dispatch_async(dispatch_get_main_queue(), ^{
        [self record:@{@"終了":@YES}];
        [self.connection invalidate];
        [NSApp terminate:nil];
    }); }];
}
@end
