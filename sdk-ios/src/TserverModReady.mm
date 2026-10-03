#import "TserverModReady.h"
#import "TserverAuthConfig.h"
#import "TserverGateUI.h"
#import <UIKit/UIKit.h>

static const NSInteger kTserverModReadyMaxAttempts =
    (NSInteger)kTserverModReadyMaxAttemptsConfig;
static const NSTimeInterval kTserverModReadyRetrySeconds =
    kTserverModReadyRetrySecondsConfig;
static const NSTimeInterval kTserverModReadySettleSeconds =
    kTserverModReadySettleSecondsConfig;

static UIViewController *TserverModTopViewController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current.presentedViewController && !current.presentedViewController.isBeingDismissed) {
        current = current.presentedViewController;
    }
    while ([current isKindOfClass:UINavigationController.class]) {
        UIViewController *visible = ((UINavigationController *)current).visibleViewController;
        if (!visible) break;
        current = visible;
    }
    while ([current isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)current).selectedViewController;
        if (!selected) break;
        current = selected;
    }
    return current;
}

static UIWindow *TserverModGameWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (application.applicationState == UIApplicationStateBackground) {
        return nil;
    }

    for (UIWindow *window in application.windows.reverseObjectEnumerator) {
        if (!window || window.hidden || window.alpha <= 0.01 || !window.rootViewController) {
            continue;
        }
        if (window.windowLevel <= UIWindowLevelNormal + 1) {
            return window;
        }
    }

    if ([application respondsToSelector:@selector(connectedScenes)]) {
        @try {
            NSSet *scenes = [application valueForKey:@"connectedScenes"];
            for (id scene in scenes) {
                if (![NSStringFromClass([scene class]) containsString:@"WindowScene"]) continue;
                NSArray *sceneWindows = [scene valueForKey:@"windows"];
                for (UIWindow *window in sceneWindows) {
                    if (window && !window.hidden && window.rootViewController &&
                        window.windowLevel <= UIWindowLevelNormal + 1) {
                        return window;
                    }
                }
            }
        } @catch (__unused NSException *exception) {
        }
    }

    for (UIWindow *candidate in application.windows.reverseObjectEnumerator) {
        if (candidate && !candidate.hidden && candidate.rootViewController) return candidate;
    }
    return nil;
}

static BOOL TserverModGateBlocksHost(void) {
    return [TserverGateUI isVisible];
}

static BOOL TserverModHostLooksReady(void) {
    UIWindow *window = TserverModGameWindow();
    if (!window || !window.rootViewController) {
        return NO;
    }

    UIViewController *controller = TserverModTopViewController(window.rootViewController);
    UIView *host = controller.view;
    return controller.isViewLoaded && host && host.window;
}

static void TserverModReadyDispatchInternal(BOOL requireGateDismissed,
                                            NSInteger attempt,
                                            dispatch_block_t block) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            if (requireGateDismissed && TserverModGateBlocksHost()) {
                if (attempt < kTserverModReadyMaxAttempts) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                 (int64_t)(kTserverModReadyRetrySeconds * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        TserverModReadyDispatchInternal(requireGateDismissed, attempt + 1, block);
                    });
                }
                return;
            }

            if (!TserverModHostLooksReady()) {
                if (attempt < kTserverModReadyMaxAttempts) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                                 (int64_t)(kTserverModReadyRetrySeconds * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        TserverModReadyDispatchInternal(requireGateDismissed, attempt + 1, block);
                    });
                }
                return;
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(kTserverModReadySettleSeconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (block) {
                    block();
                }
            });
        } @catch (__unused NSException *exception) {
            if (attempt < kTserverModReadyMaxAttempts) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(kTserverModReadyRetrySeconds * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    TserverModReadyDispatchInternal(requireGateDismissed, attempt + 1, block);
                });
            }
        }
    });
}

void TserverModReadyDispatch(dispatch_block_t block) {
    if (!block) return;
    TserverModReadyDispatchInternal(YES, 0, [block copy]);
}

void TserverModHostReadyDispatch(dispatch_block_t block) {
    if (!block) return;
    TserverModReadyDispatchInternal(NO, 0, [block copy]);
}