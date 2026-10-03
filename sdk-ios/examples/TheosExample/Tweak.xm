#import <UIKit/UIKit.h>
#import "APIClient/APIClient.h"

static void StopPaidFeatures(void) {
    NSLog(@"[APIClient] revoked / denied — tear down paid UI");
}

static void OpenPaidMenu(void) {
    // Put remaining time into your menu title / HUD / ImGui text:
    NSString *banner = [APIClient renderTemplate:@"Hạn: %tserver_timekeyt% | Key: %tserver_key%"];
    NSLog(@"[APIClient] paid lease OK — %@", banner);
}

%ctor {
    // Package token is configured once in APIClient.h; auto-setup runs before this ctor.
    APIClientStartAuthorization(^{
        APIClientPerformAuthorized(@"paid", ^{
            OpenPaidMenu();
        }, ^{
            StopPaidFeatures();
        });
    }, ^{
        StopPaidFeatures();
    });
}
