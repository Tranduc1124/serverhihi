#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const TserverUUIDCallbackDidReceiveNotification;

@interface TserverUUIDCallback : NSObject

// Handles only a validated Tserver callback URL and refreshes the auth gate.
+ (BOOL)handleIncomingURL:(NSURL *)url;

@end
