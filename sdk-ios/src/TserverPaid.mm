#define APICLIENT_NO_AUTO_SETUP 1
#import "TserverPaid.h"
#import "APIClient.h"

@implementation TserverPaid

+ (void)paid:(dispatch_block_t)onPaid {
    APIClientOpenPaid(onPaid);
}

@end
