#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>

NS_ASSUME_NONNULL_BEGIN
// 呼び出しと変更通知はサービスの直列キューで扱う。
@interface PrivateSimulatorAPI : NSObject
@property(nonatomic, readonly) BOOL coreSimulatorLoaded;
@property(nonatomic, readonly) BOOL simulatorKitLoaded;
@property(nonatomic, readonly) NSString *xcodeBuild;
@property(nonatomic, readonly, nullable) NSString *reason;
- (BOOL)load;
- (BOOL)attach:(NSString *)udid queue:(dispatch_queue_t)queue
       changed:(void (^)(IOSurface *))changed error:(NSError **)error;
- (void)detach;
- (void)sendTouch:(NSInteger)phase x:(double)x y:(double)y;
- (void)sendScroll:(double)dx dy:(double)dy x:(double)x y:(double)y phase:(NSInteger)phase;
- (void)sendKey:(uint16_t)keyCode modifiers:(NSUInteger)modifiers down:(BOOL)down;
- (void)sendButton:(NSInteger)button;
- (void)releaseAll;
@end
NS_ASSUME_NONNULL_END
