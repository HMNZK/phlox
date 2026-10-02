#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>
#import <IOSurface/IOSurfaceRef.h>
static inline uint32_t GateSurfaceID(IOSurface *surface) {
    return IOSurfaceGetID((__bridge IOSurfaceRef)surface);
}

@protocol GateService
- (void)attach:(NSString *)udid developer:(NSString *)developer log:(NSString *)log reply:(void (^)(NSString *))reply;
- (void)touch:(NSInteger)phase x:(double)x y:(double)y reply:(void (^)(NSString *))reply;
- (void)key:(uint32_t)usage down:(BOOL)down reply:(void (^)(NSString *))reply;
- (void)home:(void (^)(NSString *))reply;
- (void)detach:(void (^)(void))reply;
@end

@protocol GateClient
- (void)surface:(IOSurface *)surface;
@end

NSXPCInterface *GateServiceInterface(void);
NSXPCInterface *GateClientInterface(void);
#if __has_include("../Host/GateHost.h")
#import "../Host/GateHost.h"
#endif
