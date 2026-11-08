#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

- (BOOL) RebootDevice;
- (BOOL) RebootUserspace;
- (void) Respring;

@end
