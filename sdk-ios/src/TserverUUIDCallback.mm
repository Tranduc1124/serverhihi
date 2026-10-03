#import "TserverUUIDCallback.h"
#import "TserverAuth.h"

NSString * const TserverUUIDCallbackDidReceiveNotification = @"com.tserver.auth.refresh";

@implementation TserverUUIDCallback

+ (BOOL)handleIncomingURL:(NSURL *)url {
    if (!url) return NO;
    BOOL accepted = [TserverAuth handleCallbackURL:url completion:^(NSDictionary *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:TserverUUIDCallbackDidReceiveNotification
                                                                object:nil
                                                              userInfo:@{ @"result": result ?: @{} }];
        });
    }];
    return accepted;
}

@end
