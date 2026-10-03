#import <AppKit/AppKit.h>
#import <objc/message.h>
#import "../../SimulatorBridgeService/PrivateSimulatorAPI.h"

// HID メッセージの生成・配送だけを置き換え、本番の接触とキーの状態遷移を検査する。
static NSMutableArray<NSDictionary *> *messages;
static int failures;
static void check(BOOL value, NSString *message) {
    if (!value) { failures++; fprintf(stderr, "失敗: %s\n", message.UTF8String); }
}
static void *mouse(CGPoint *point, CGPoint *unused, uint32_t source, NSUInteger type, CGSize size, uint32_t flags) {
    [messages addObject:@{@"種別": @"接触", @"位相": @(type), @"X": @(point->x), @"Y": @(point->y), @"時刻": @(NSProcessInfo.processInfo.systemUptime)}];
    return malloc(1);
}
static void *key(int32_t usage, int32_t state) {
    [messages addObject:@{@"種別": @"キー", @"コード": @(usage), @"状態": @(state)}];
    return malloc(1);
}
static uint32_t usage(uint32_t code) { return code == 0 ? 4 : 0xe3; }
@interface RecordingAPI : PrivateSimulatorAPI
- (void)send:(void *)message;
@end
@interface PrivateSimulatorAPI (検査用関数)
- (void)setMouseFunction:(void *)function;
- (void)setKeyFunction:(void *)function;
- (void)setUsageFunction:(void *)function;
@end
@implementation RecordingAPI
- (void)send:(void *)message { free(message); }
@end

static void scroll(PrivateSimulatorAPI *api, double delta, NSInteger phase, double y) {
    SEL selector = NSSelectorFromString(@"sendScroll:dy:x:y:phase:");
    if ([api respondsToSelector:selector]) {
        ((void (*)(id, SEL, double, double, double, double, NSInteger))objc_msgSend)(api, selector, 0, delta, 0.5, y, phase);
    } else {
        check(phase == 0, @"スクロールの位相を受け取れない");
        SEL old = NSSelectorFromString(@"sendScroll:dy:x:y:");
        ((void (*)(id, SEL, double, double, double, double))objc_msgSend)(api, old, 0, delta, 0.5, y);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        dispatch_queue_t queue = dispatch_queue_create("入力検査", DISPATCH_QUEUE_SERIAL);
        RecordingAPI *api = [RecordingAPI new];
        messages = [NSMutableArray array];
        [api setValue:[NSObject new] forKey:@"hid"];
        [api setValue:queue forKey:@"queue"];
        [api setMouseFunction:mouse];
        [api setKeyFunction:key];
        [api setUsageFunction:usage];
        [api setValue:[NSMutableSet set] forKey:@"heldKeys"];
        [api setValue:[NSMutableSet set] forKey:@"syntheticModifiers"];
        [api setValue:@3 forKey:@"screenScale"];
        IOSurface *surface = [[IOSurface alloc] initWithProperties:@{(id)kIOSurfaceWidth: @1206, (id)kIOSurfaceHeight: @2622, (id)kIOSurfaceBytesPerElement: @4}];
        [api setValue:[@{@"画面": surface} mutableCopy] forKey:@"surfaces"];
        NSString *test = argc > 1 ? @(argv[1]) : @"";
        dispatch_sync(queue, ^{
            if ([test isEqual:@"重複押下"]) {
                [api sendTouch:0 x:0.2 y:0.3];
                [api sendTouch:1 x:0.4 y:0.5];
                [api sendTouch:0 x:0.7 y:0.8];
                check(messages.count == 4, @"新しい押下の前に古い接触を離す");
                if (messages.count >= 4) {
                    check([messages[2][@"位相"] unsignedIntegerValue] == NSEventTypeLeftMouseUp && [messages[2][@"X"] doubleValue] == 0.4 && [messages[2][@"Y"] doubleValue] == 0.5, @"古い位置で離す");
                    check([messages[3][@"X"] doubleValue] == 0.7, @"新しい位置で押す");
                }
            } else if ([test isEqual:@"キーリピート"]) {
                [api sendKey:0 modifiers:0 down:YES];
                [api sendKey:0 modifiers:NSEventModifierFlagCommand down:YES];
                check(messages.count == 2, @"リピートで Command を合成しない");
                for (NSDictionary *row in messages) check([row[@"コード"] intValue] == 4, @"A のみ配送する");
            } else if ([test isEqual:@"小量"]) {
                scroll(api, -1, 0, 0.2);
            } else {
                scroll(api, -100, [test isEqual:@"位相"] ? 1 : 0, [test isEqual:@"端"] ? 1 : 0.5);
            }
        });
        [NSThread sleepForTimeInterval:0.8];
        dispatch_sync(queue, ^{
            if ([test isEqual:@"小量"]) {
                check(messages.count == 0, @"小量スクロールをタップにしない");
            } else if ([test isEqual:@"位相"]) {
                check([[api valueForKey:@"touching"] boolValue], @"ended までは接触を保つ");
                scroll(api, -20, 2, 0.5);
                scroll(api, 0, 3, 0.5);
                check([[api valueForKey:@"touching"] boolValue], @"終了直後は終点で止まる");
            } else if ([test isEqual:@"ホイール"] || [test isEqual:@"端"]) {
                NSDictionary *last = messages.lastObject;
                check([last[@"位相"] unsignedIntegerValue] == NSEventTypeLeftMouseUp, @"ホイールを解放する");
                NSDictionary *stationary = nil;
                for (NSDictionary *row in messages) {
                    if ([row[@"位相"] unsignedIntegerValue] == NSEventTypeLeftMouseDown && [row[@"Y"] isEqual:last[@"Y"]] && !stationary) stationary = row;
                }
                check(stationary != nil && [last[@"時刻"] doubleValue] - [stationary[@"時刻"] doubleValue] >= 0.1, @"終点で100ms以上停止してから離す");
                if ([test isEqual:@"端"]) check([messages.firstObject[@"Y"] doubleValue] <= 1 - 44.0 / 874, @"端から44ポイント内側で開始する");
            }
        });
        [NSThread sleepForTimeInterval:0.35];
        dispatch_sync(queue, ^{
            if ([test isEqual:@"位相"]) check(![[api valueForKey:@"touching"] boolValue], @"ended 後は離す");
            [api releaseAll];
        });
        printf("%s: %s\n", test.UTF8String, failures ? "失敗" : "成功");
        return failures ? 1 : 0;
    }
}
