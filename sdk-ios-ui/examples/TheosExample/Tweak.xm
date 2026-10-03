#import <UIKit/UIKit.h>
#import "TserverAuth.h"
#import "TserverGateUI.h"

%ctor {
    [TserverAuth configureWithEndpoint:@"https://your-domain.com"
                               storeId:@"Tserver"
                                 appId:@"tserver_app"
                          returnScheme:@"tserverapp"];

    [TserverGateUI setOnValid:^(NSDictionary *result) {
        NSLog(@"[Tserver] VALID - open main menu here");
    }];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [TserverGateUI showLoadingWithMessage:@"Dang kiem tra key..."];

        [TserverAuth bootstrapWithCompletion:^(NSDictionary *result) {
            [TserverGateUI showWithResult:result];
        }];
    });
}

static void TserverOpenProfileGateExample(void) {
    [TserverGateUI showNeedUUIDWithConfig:@{}];
}

static void TserverHandleDeepLinkExample(NSURL *url) {
    [TserverAuth handleCallbackURL:url completion:^(NSDictionary *result) {
        [TserverGateUI showWithResult:result];
    }];
}
