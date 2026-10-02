#import "Bridge.h"
NSXPCInterface *GateServiceInterface(void) {
    return [NSXPCInterface interfaceWithProtocol:@protocol(GateService)];
}
NSXPCInterface *GateClientInterface(void) {
    NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(GateClient)];
    [interface setClasses:[NSSet setWithObject:IOSurface.class] forSelector:@selector(surface:) argumentIndex:0 ofReply:NO];
    return interface;
}
