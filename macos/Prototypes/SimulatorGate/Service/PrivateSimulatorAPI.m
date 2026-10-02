#import "../Shared/Bridge.h"
#import <AppKit/AppKit.h>
#import <dlfcn.h>

// 非公開 API はこのプロセスのこのファイルだけで呼ぶ。
@interface NSObject (GatePrivateAPI)
+ (id)sharedServiceContextForDeveloperDir:(NSString *)path error:(NSError **)error;
- (id)defaultDeviceSetWithError:(NSError **)error;
- (NSArray *)devices;
- (NSUUID *)UDID;
- (NSString *)name;
- (id)io;
- (void)updateIOPorts;
- (NSArray *)ioPorts;
- (id)descriptor;
- (IOSurface *)framebufferSurface;
- (void)registerScreenCallbacksWithUUID:(NSUUID *)uuid callbackQueue:(dispatch_queue_t)queue frameCallback:(void (^)(void))frame surfacesChangedCallback:(void (^)(IOSurface *, IOSurface *))surfaces propertiesChangedCallback:(void (^)(id))properties;
- (void)unregisterScreenCallbacksWithUUID:(NSUUID *)uuid;
- (id)initWithDevice:(id)device error:(NSError **)error;
- (void)sendWithMessage:(void *)message freeWhenDone:(BOOL)free completionQueue:(dispatch_queue_t)queue completion:(void (^)(NSError *))completion;
@end

@interface Service : NSObject <NSXPCListenerDelegate, GateService>
@property NSXPCConnection *connection;
@property id device;
@property id io;
@property NSArray *descriptors;
@property NSMutableDictionary<NSString *, IOSurface *> *surfaces;
@property id hid;
@property NSUUID *token;
@property dispatch_queue_t queue;
@property dispatch_source_t timer;
@property NSFileHandle *log;
@property IOSurface *firstSurface;
@property uint32_t currentID;
@property NSUInteger transfers;
@property NSUInteger frames;
@property void *kit;
@property void *mouseFunction;
@property void *keyFunction;
@property void *buttonFunction;
@end

@implementation Service
- (void)record:(NSDictionary *)values {
    NSMutableDictionary *row = [values mutableCopy];
    row[@"時刻"] = @([[NSDate date] timeIntervalSince1970]);
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:row options:0 error:&error];
    if (!data) { NSLog(@"ログの符号化失敗: %@", error); return; }
    [self.log writeData:data];
    [self.log writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
}
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    if (self.connection) return NO;
    self.queue = dispatch_queue_create("com.phlox.prototype.gate", DISPATCH_QUEUE_SERIAL);
    self.connection = connection;
    connection.exportedInterface = GateServiceInterface();
    connection.exportedObject = self;
    connection.remoteObjectInterface = GateClientInterface();
    __weak Service *weakSelf = self;
    connection.invalidationHandler = ^{ dispatch_async(weakSelf.queue, ^{ [weakSelf cleanup]; weakSelf.connection = nil; }); };
    [connection resume];
    return YES;
}
- (void)attach:(NSString *)udid developer:(NSString *)developer log:(NSString *)log reply:(void (^)(NSString *))reply {
    dispatch_async(self.queue, ^{
        @try {
            self.log = [NSFileHandle fileHandleForWritingAtPath:log];
            if (!self.log) { reply(@"サービスのログファイルを開けません"); return; }
            NSArray *paths = @[@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", [developer stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"]];
            for (NSString *path in paths) {
                void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
                if (!handle) {
                    NSString *message = [NSString stringWithUTF8String:dlerror()];
                    [self record:@{@"読み込み失敗":message, @"パス":path}]; reply(message); return;
                }
                if ([path containsString:@"SimulatorKit"]) self.kit = handle;
                [self record:@{@"読み込み成功":path, @"PID":@(getpid())}];
            }
            self.mouseFunction = dlsym(self.kit, "IndigoHIDMessageForMouseNSEvent");
            self.keyFunction = dlsym(self.kit, "IndigoHIDMessageForKeyboardArbitrary");
            self.buttonFunction = dlsym(self.kit, "IndigoHIDMessageForButton");
            Class contextClass = NSClassFromString(@"SimServiceContext");
            SEL contextSelector = @selector(sharedServiceContextForDeveloperDir:error:);
            if (![contextClass respondsToSelector:contextSelector]) { reply(@"SimServiceContext のセレクターがありません"); return; }
            NSError *error = nil;
            id context = [contextClass sharedServiceContextForDeveloperDir:developer error:&error];
            if (!context) { reply(error.description ?: @"SimServiceContext が nil"); return; }
            id set = [context defaultDeviceSetWithError:&error];
            if (!set) { reply(error.description ?: @"SimDeviceSet が nil"); return; }
            for (id device in [set devices]) {
                if ([[[device UDID] UUIDString] isEqualToString:udid]) self.device = device;
            }
            if (!self.device || ![[self.device name] hasPrefix:@"Phlox-SimulatorGate-"]) { reply(@"専用端末ではありません"); return; }
            self.io = [self.device io];
            [self.io updateIOPorts];
            NSMutableArray *descriptors = [NSMutableArray array];
            self.token = [NSUUID UUID];
            self.surfaces = [NSMutableDictionary dictionary];
            __weak Service *weakSelf = self;
            for (id port in [self.io ioPorts]) {
                id descriptor = [port descriptor];
                if (![descriptor respondsToSelector:@selector(registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:)]) continue;
                [descriptors addObject:descriptor];
                NSString *key = [NSString stringWithFormat:@"%lu", (unsigned long)descriptors.count];
                [descriptor registerScreenCallbacksWithUUID:self.token callbackQueue:self.queue frameCallback:^{ weakSelf.frames++; } surfacesChangedCallback:^(IOSurface *surface, IOSurface *masked) {
                    if (surface) weakSelf.surfaces[key] = surface;
                    else [weakSelf.surfaces removeObjectForKey:key];
                    [weakSelf sample];
                } propertiesChangedCallback:^(id properties) {}];
                IOSurface *initial = [descriptor framebufferSurface];
                if (initial) self.surfaces[key] = initial;
            }
            self.descriptors = descriptors;
            if (!descriptors.count) { reply(@"表示ポートのコールバックが見つかりません"); return; }
            Class hidClass = NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient");
            if (![hidClass instancesRespondToSelector:@selector(initWithDevice:error:)] || !self.mouseFunction || !self.keyFunction || !self.buttonFunction) { reply(@"HID のクラスまたは関数がありません"); return; }
            self.hid = [[hidClass alloc] initWithDevice:self.device error:&error];
            if (!self.hid) { reply(error.description ?: @"HID クライアントが nil"); return; }
            self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
            dispatch_source_set_timer(self.timer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 30, 0);
            dispatch_source_set_event_handler(self.timer, ^{ [weakSelf sample]; });
            dispatch_resume(self.timer);
            [self record:@{@"接続":udid, @"表示ポート数":@(descriptors.count)}];
            reply(@"");
        } @catch (NSException *exception) {
            [self record:@{@"例外":exception.description}]; reply(exception.description);
        }
    });
}
- (void)sample {
    @try {
        IOSurface *best = nil;
        // 遠隔プロキシの getter を毎フレーム呼ぶと HID の配送が滞る。
        for (IOSurface *surface in self.surfaces.allValues) {
            if (surface.width * surface.height > best.width * best.height) best = surface;
        }
        if (!best) return;
        if (!self.firstSurface) self.firstSurface = best;
        if (GateSurfaceID(best) != self.currentID) {
            self.currentID = GateSurfaceID(best);
            self.transfers++;
            NSError *error = nil;
            NSData *encoded = [NSKeyedArchiver archivedDataWithRootObject:best requiringSecureCoding:YES error:&error];
            [self record:@{@"surface符号化バイト":@(encoded.length), @"符号化結果":error.description ?: @"成功", @"画素バイト":@(best.allocationSize)}];
            id<GateClient> client = [self.connection remoteObjectProxyWithErrorHandler:^(NSError *error) { [self record:@{@"XPC失敗":error.description}]; }];
            [client surface:best];
        }
        [self record:@{@"surfaceID":@(GateSurfaceID(best)), @"seed":@(best.seed), @"初回ID":@(GateSurfaceID(self.firstSurface)), @"初回seed":@(self.firstSurface.seed), @"surface送信数":@(self.transfers), @"描画通知数":@(self.frames), @"幅":@(best.width), @"高さ":@(best.height), @"画素形式":@(best.pixelFormat)}];
    } @catch (NSException *exception) { [self record:@{@"取得例外":exception.description}]; }
}
- (void)send:(void *)message reply:(void (^)(NSString *))reply {
    if (!message || !self.hid) { if (message) free(message); reply(@"HID メッセージまたは接続がありません"); return; }
    @try {
        [self.hid sendWithMessage:message freeWhenDone:YES completionQueue:self.queue completion:^(NSError *error) {
            [self record:@{@"HID送信結果":error.description ?: @"配送完了（入力結果は別途確認）"}]; reply(error.description ?: @"");
        }];
    } @catch (NSException *exception) { [self record:@{@"入力例外":exception.description}]; reply(exception.description); }
}
- (void)touch:(NSInteger)phase x:(double)x y:(double)y reply:(void (^)(NSString *))reply {
    dispatch_async(self.queue, ^{
        if (phase < 0 || phase > 2 || !isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1 || !self.mouseFunction) { reply(@"不正なタッチ"); return; }
        CGPoint point = CGPointMake(x, y);
        // 移動中も接触を維持する。Dragged(6) はこの関数では押下として扱われない。
        NSUInteger type = phase == 2 ? NSEventTypeLeftMouseUp : NSEventTypeLeftMouseDown;
        void *(*function)(CGPoint *, CGPoint *, uint32_t, NSUInteger, CGSize, uint32_t) = self.mouseFunction;
        [self send:function(&point, NULL, 0x32, type, CGSizeMake(1, 1), 0) reply:reply];
    });
}
- (void)key:(uint32_t)usage down:(BOOL)down reply:(void (^)(NSString *))reply {
    dispatch_async(self.queue, ^{
        if (!self.keyFunction || usage > 255) { reply(@"不正なキー"); return; }
        void *(*function)(int32_t, int32_t) = self.keyFunction;
        [self send:function(usage, down ? 1 : 2) reply:reply];
    });
}
- (void)home:(void (^)(NSString *))reply {
    dispatch_async(self.queue, ^{
        if (!self.buttonFunction) { reply(@"ホーム関数がありません"); return; }
        void *(*function)(int32_t, int32_t, int32_t) = self.buttonFunction;
        [self send:function(0, 1, 0x33) reply:^(NSString *error) {
            if (error.length) { reply(error); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), self.queue, ^{ [self send:function(0, 2, 0x33) reply:reply]; });
        }];
    });
}
- (void)cleanup {
    if (self.timer) dispatch_source_cancel(self.timer);
    self.timer = nil;
    for (id descriptor in self.descriptors) [descriptor unregisterScreenCallbacksWithUUID:self.token];
    self.descriptors = nil; self.surfaces = nil; self.hid = nil; self.io = nil; self.device = nil; self.firstSurface = nil;
    [self.log closeFile]; self.log = nil;
}
- (void)detach:(void (^)(void))reply { dispatch_async(self.queue, ^{ [self cleanup]; reply(); }); }
@end

int main(void) {
    @autoreleasepool {
        Service *service = [Service new];
        NSXPCListener *listener = NSXPCListener.serviceListener;
        listener.delegate = service;
        [listener resume];
    }
    return 0;
}
