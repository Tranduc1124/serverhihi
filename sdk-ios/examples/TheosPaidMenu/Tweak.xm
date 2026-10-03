#import <UIKit/UIKit.h>
#import "APIClient/APIClient.h"

static UIButton *gMenuButton = nil;
static UILabel *gInfoLabel = nil;

static void CustomerTearDownMenu(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [gMenuButton removeFromSuperview];
        [gInfoLabel removeFromSuperview];
        gMenuButton = nil;
        gInfoLabel = nil;
    });
}

static void CustomerRefreshKeyInfo(void) {
    // Drop remaining-time text into your real menu (ImGui title, UILabel, etc.).
    NSString *text = [APIClient renderTemplate:@"Key: %tserver_key%\nHạn: %tserver_timekeyt%"];
    gInfoLabel.text = text;
}

static void CustomerInstallMenu(void) {
    // Replace with your project's menu bootstrap (ImGui, UIKit float button, etc.)
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;

        if (!gMenuButton.superview) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            button.frame = CGRectMake(24, 120, 48, 48);
            button.backgroundColor = [UIColor colorWithRed:0.08 green:0.45 blue:0.72 alpha:0.96];
            button.layer.cornerRadius = 24.0;
            [button setTitle:@"M" forState:UIControlStateNormal];
            [window addSubview:button];
            gMenuButton = button;
        }

        if (!gInfoLabel.superview) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, 180, 220, 48)];
            label.numberOfLines = 2;
            label.textColor = UIColor.whiteColor;
            label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
            label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [window addSubview:label];
            gInfoLabel = label;
        }

        CustomerRefreshKeyInfo();
    });
}

%ctor {
    // Package token is configured once in APIClient.h; auto-setup runs before this ctor.
    APIClientStartAuthorization(^{
        // onAuthorized means the UI may open — still gate the menu install on the live lease.
        APIClientPerformAuthorized(@"paid", ^{
            CustomerInstallMenu();
        }, ^{
            CustomerTearDownMenu();
        });
    }, ^{
        CustomerTearDownMenu();
    });
}
