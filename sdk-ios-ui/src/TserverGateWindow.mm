#import <UIKit/UIKit.h>
#import "TserverSecurityPolicy.h"
#import "APIClient.h"

@interface TserverGateWindow : NSObject
+ (instancetype)shared;
- (void)showGateView:(UIView *)view;
- (void)showGateView:(UIView *)view makeKey:(BOOL)makeKey;
- (void)refreshCaptureProtection;
/// Protect the host app's own content while authorized. Independent from the gate
/// cover: dismissing the gate must not silently drop capture protection.
- (void)setHostCaptureProtectionActive:(BOOL)active;
- (void)dismiss;
- (BOOL)isVisible;
- (UIViewController *)presentationViewController;
- (void)prepareForExternalPresentation;
@end

@interface TserverGateRootViewController : UIViewController
@end

@interface TserverGateTouchBlocker : UIControl
@end

@implementation TserverGateRootViewController
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)prefersStatusBarHidden { return NO; }
@end

@implementation TserverGateTouchBlocker
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return YES; }
@end

@interface TserverGateWindow ()
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) TserverGateRootViewController *rootViewController;
@property(nonatomic, weak) UIView *hostContainerView;
@property(nonatomic, strong) UIView *hostOverlayView;
@property(nonatomic, strong) UITextField *secureCaptureField;
@property(nonatomic, assign) BOOL captureObserverInstalled;
// Host content protection has its own lifecycle: the gate comes and goes, the
// authorized session does not.
@property(nonatomic, assign) BOOL hostCaptureObserverInstalled;
@property(nonatomic, assign) BOOL hostCaptureRequested;
@end

static const NSInteger kTserverGateOverlayTag = 59102731;
static NSUInteger gTserverGatePresentationGeneration = 0;

static BOOL TserverIsIOS13OrNewer(void) {
    return [UIApplication.sharedApplication respondsToSelector:@selector(connectedScenes)];
}

/// Either "ẩn khỏi quay màn hình" or "che nội dung khi quay/chụp" is on.
///
/// Both policies are served by the same mechanism: hosting the SDK's own views
/// inside a secure-text-entry canvas, which iOS omits from screen recordings,
/// screenshots and AirPlay while leaving them fully visible on the device. No
/// mask is drawn, so a recorder never blacks out the host app and the user can
/// keep touching the game underneath.
BOOL TserverGateCaptureHidingEnabled(void) {
    return TserverSecurityPolicyHideScreenCapture() || TserverSecurityPolicyProtectScreenContent();
}

static UIViewController *TserverGateTopViewController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current) {
        UIViewController *next = nil;
        if (current.presentedViewController && !current.presentedViewController.isBeingDismissed) {
            next = current.presentedViewController;
        } else if ([current isKindOfClass:UINavigationController.class]) {
            next = ((UINavigationController *)current).visibleViewController;
        } else if ([current isKindOfClass:UITabBarController.class]) {
            next = ((UITabBarController *)current).selectedViewController;
        }
        if (!next || next == current) break;
        current = next;
    }
    return current;
}

@implementation TserverGateWindow

+ (instancetype)shared {
    static TserverGateWindow *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [TserverGateWindow new];
    });
    return shared;
}

- (void)showGateView:(UIView *)view {
    [self showGateView:view makeKey:NO];
}

- (void)showGateView:(UIView *)view makeKey:(BOOL)makeKey {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showGateView:view makeKey:makeKey];
        });
        return;
    }
    NSUInteger generation = ++gTserverGatePresentationGeneration;
    [self showGateView:view makeKey:makeKey attempt:0 generation:generation];
}

- (void)showGateView:(UIView *)view makeKey:(BOOL)makeKey attempt:(NSInteger)attempt generation:(NSUInteger)generation {
    (void)makeKey;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!view || generation != gTserverGatePresentationGeneration) return;
        @try {
            UIView *hostView = [self preferredHostView];
            if (hostView) {
                if (generation != gTserverGatePresentationGeneration) return;
                [self showGateViewOnHost:view hostView:hostView];
                return;
            }
            if (attempt < 48) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (generation != gTserverGatePresentationGeneration) return;
                    [self showGateView:view makeKey:NO attempt:attempt + 1 generation:generation];
                });
                return;
            }
            if (generation != gTserverGatePresentationGeneration) return;
            [self showGateViewOnFallbackWindow:view];
        } @catch (__unused NSException *exception) {
        }
    });
}

- (void)showGateViewOnHost:(UIView *)view hostView:(UIView *)hostView {
    [self dismissHostOverlay];
    [self hideFallbackWindow];

    [hostView endEditing:YES];
    for (UIView *subview in hostView.subviews) {
        if (subview.tag == kTserverGateOverlayTag) {
            [subview removeFromSuperview];
        }
    }

    self.hostContainerView = hostView;

    TserverGateTouchBlocker *blocker = [[TserverGateTouchBlocker alloc] initWithFrame:CGRectZero];
    blocker.tag = kTserverGateOverlayTag;
    blocker.translatesAutoresizingMaskIntoConstraints = NO;
    blocker.backgroundColor = UIColor.clearColor;
    blocker.userInteractionEnabled = YES;
    blocker.multipleTouchEnabled = YES;
    blocker.exclusiveTouch = YES;

    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.userInteractionEnabled = YES;
    view.multipleTouchEnabled = YES;

    [hostView addSubview:blocker];
    UIView *contentHost = [self secureContentHostIfNeeded:blocker];
    [contentHost addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [blocker.topAnchor constraintEqualToAnchor:hostView.topAnchor],
        [blocker.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
        [blocker.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
        [blocker.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],
        [view.topAnchor constraintEqualToAnchor:contentHost.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:contentHost.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:contentHost.trailingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:contentHost.bottomAnchor]
    ]];
    [hostView bringSubviewToFront:blocker];
    self.hostOverlayView = blocker;
    [self installCaptureProtectionOnContainer:blocker];
}

- (void)showGateViewOnFallbackWindow:(UIView *)view {
    [self dismissHostOverlay];
    [self ensureWindow];
    [self attachToActiveSceneIfNeeded];

    [self.rootViewController.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *contentHost = [self secureContentHostIfNeeded:self.rootViewController.view];
    [contentHost addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:contentHost.topAnchor],
        [view.leadingAnchor constraintEqualToAnchor:contentHost.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:contentHost.trailingAnchor],
        [view.bottomAnchor constraintEqualToAnchor:contentHost.bottomAnchor]
    ]];

    self.window.hidden = NO;
    self.window.userInteractionEnabled = YES;
    // Never steal keyWindow from Unity/game — overlay only.
    if (TserverIsIOS13OrNewer()) {
        id scene = nil;
        if ([self.window respondsToSelector:@selector(windowScene)]) {
            scene = [self.window valueForKey:@"windowScene"];
        }
        if (!scene) {
            self.window.hidden = YES;
            self.window.userInteractionEnabled = NO;
        }
    }
    [self installCaptureProtectionOnContainer:self.rootViewController.view];
}

- (void)dismiss {
    gTserverGatePresentationGeneration += 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [self teardownCaptureProtection];
            [self dismissHostOverlay];
            [self hideFallbackWindow];
        } @catch (__unused NSException *exception) {
        }
    });
}

- (UIView *)secureContentHostIfNeeded:(UIView *)container {
    if (!TserverGateCaptureHidingEnabled()) return container;
    // Secure UITextField trick: content hosted in the secure field's layer is omitted from
    // screenshots / many screen-recording captures.
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.secureTextEntry = YES;
    field.userInteractionEnabled = NO;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.topAnchor constraintEqualToAnchor:container.topAnchor],
        [field.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [field.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [field.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];
    [container layoutIfNeeded];
    [field layoutIfNeeded];
    self.secureCaptureField = field;
    UIView *secureHost = field.subviews.firstObject;
    if (!secureHost) {
        // Some iOS builds delay creating the secure subview until the next layout pass.
        [container setNeedsLayout];
        [container layoutIfNeeded];
        [field layoutIfNeeded];
        secureHost = field.subviews.firstObject;
    }
    if (!secureHost) return container;
    secureHost.userInteractionEnabled = YES;
    return secureHost;
}

- (UIView *)currentGateContentView {
    NSArray<UIView *> *roots = nil;
    if (self.hostOverlayView.superview) {
        roots = @[self.hostOverlayView];
    } else if (self.window && !self.window.hidden && self.rootViewController.view) {
        roots = @[self.rootViewController.view];
    }
    for (UIView *root in roots) {
        for (UIView *child in root.subviews) {
            if (child == self.secureCaptureField) continue;
            return child;
        }
        UIView *secureHost = self.secureCaptureField.subviews.firstObject;
        for (UIView *child in secureHost.subviews) {
            return child;
        }
    }
    return nil;
}

- (void)refreshCaptureProtection {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshCaptureProtection];
        });
        return;
    }
    @try {
        UIView *gateView = [self currentGateContentView];
        if (!gateView) {
            UIView *container = self.hostOverlayView.superview ? self.hostOverlayView : self.rootViewController.view;
            [self installCaptureProtectionOnContainer:container];
            return;
        }
        // Rebuild host so hideScreenCapture (secure field) and protectScreenContent
        // pick up packageSettings that arrived after the cold-start LOADING overlay.
        if (self.hostOverlayView.superview && self.hostContainerView) {
            [self showGateViewOnHost:gateView hostView:self.hostContainerView];
            return;
        }
        if (self.window && !self.window.hidden) {
            [self showGateViewOnFallbackWindow:gateView];
        }
    } @catch (__unused NSException *exception) {
    }
}

/// Nothing is drawn over the screen.
///
/// The old implementation installed a near-opaque black view across the whole
/// host window whenever a capture was detected. That produced exactly the two
/// complaints this replaces: the SDK UI was still visible in the recording (the
/// mask was rendered by the app, so the recorder captured the mask *and* whatever
/// it was hiding), and the user lost the entire screen while recording — no taps
/// at all, including on the game.
///
/// Both policies are now served entirely by `secureContentHostIfNeeded:`, which
/// reparents the SDK's views into a secure-text-entry canvas. iOS excludes that
/// canvas from screen recordings, screenshots and AirPlay, so the UI disappears
/// from the recorded output while remaining fully visible and interactive on the
/// device. Nothing is added to the host's view hierarchy, so the game stays
/// visible and tappable during recording.
- (void)installCaptureProtectionOnContainer:(__unused UIView *)container {
    // Kept for the existing call sites: capture hiding is applied where the SDK
    // content is attached (secureContentHostIfNeeded:), not here.
}

- (void)screenCaptureChanged {
    [self applyCaptureState];
}

// MARK: - Host content protection

/// The host's own root view, excluding the SDK's fallback window.
- (UIView *)hostContentView {
    for (UIWindow *candidate in [UIApplication.sharedApplication.windows reverseObjectEnumerator]) {
        if (!candidate || candidate.hidden || candidate == self.window) continue;
        UIViewController *root = candidate.rootViewController;
        if (!root || !root.viewIfLoaded.window) continue;
        return root.view;
    }
    return nil;
}

- (void)applyCaptureState {
    // No mask to show or hide. The secure canvas is unconditional, so the SDK UI
    // is already absent from the capture regardless of when it started.
}

- (void)setHostCaptureProtectionActive:(BOOL)active {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setHostCaptureProtectionActive:active];
        });
        return;
    }
    self.hostCaptureRequested = active;
    if (!active) {
        [self teardownHostCaptureProtection];
        return;
    }
    // Either toggle is enough: the portal copy promises gate AND menu are hidden.
    if (!TserverGateCaptureHidingEnabled()) {
        [self teardownHostCaptureProtection];
        return;
    }
    // The gate is already on screen by the time an authorized session starts, and
    // it was attached through the secure canvas. Re-parenting the host's own view
    // hierarchy into that canvas is not an option (it breaks Unity/Unreal), so the
    // authorized state only needs to keep the observer alive for diagnostics.
    if (!self.captureObserverInstalled) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screenCaptureChanged)
                                                     name:UIScreenCapturedDidChangeNotification
                                                   object:nil];
        self.captureObserverInstalled = YES;
    }
    self.hostCaptureObserverInstalled = YES;
    [self applyCaptureState];
    // Hoisted out of the boxed expression: clang in Objective-C++ fails to parse
    // a chained property access compared against nil inside @( ... )
    // ("expected identifier" on the nil token).
    UIView *secureCanvas = self.secureCaptureField.subviews.firstObject;
    TserverDiagnosticsRecord(@"capture", @"host content protection active", @{
        @"hostView": NSStringFromClass([self hostContentView].class),
        @"secureCanvas": @(secureCanvas != nil),
        @"hideScreenCapture": @(TserverSecurityPolicyHideScreenCapture()),
        @"protectScreenContent": @(TserverSecurityPolicyProtectScreenContent())
    });
}

- (void)teardownHostCaptureProtection {
    if (!self.hostCaptureObserverInstalled && !self.hostCaptureRequested) return;
    self.hostCaptureRequested = NO;
    if (self.hostCaptureObserverInstalled) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIScreenCapturedDidChangeNotification
                                                      object:nil];
        self.captureObserverInstalled = NO;
    }
    self.hostCaptureObserverInstalled = NO;
    TserverDiagnosticsRecord(@"capture", @"host content protection released", nil);
}

- (void)teardownCaptureProtectionObservingOnly {
    if (self.captureObserverInstalled) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIScreenCapturedDidChangeNotification object:nil];
        self.captureObserverInstalled = NO;
    }
}

- (void)teardownCaptureProtection {
    [self teardownCaptureProtectionObservingOnly];
    [self.secureCaptureField removeFromSuperview];
    self.secureCaptureField = nil;
}

- (void)dismissHostOverlay {
    if (self.hostOverlayView) {
        [self.hostOverlayView endEditing:YES];
        [self.hostOverlayView removeFromSuperview];
        self.hostOverlayView = nil;
    }
    if (self.hostContainerView) {
        for (UIView *subview in self.hostContainerView.subviews) {
            if (subview.tag == kTserverGateOverlayTag) {
                [subview removeFromSuperview];
            }
        }
        self.hostContainerView = nil;
    }
}

- (void)hideFallbackWindow {
    if (self.rootViewController) {
        [self.rootViewController.view endEditing:YES];
        [self.rootViewController.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    }
    if (self.window) {
        self.window.hidden = YES;
        self.window.userInteractionEnabled = NO;
    }
}

- (BOOL)isVisible {
    if (self.hostOverlayView.superview) {
        return YES;
    }
    return self.window && !self.window.hidden;
}

- (UIView *)preferredHostView {
    UIWindow *appWindow = [self preferredAppWindow];
    if (!appWindow) {
        return nil;
    }
    if (appWindow.rootViewController) {
        UIViewController *top = TserverGateTopViewController(appWindow.rootViewController);
        if (top.isViewLoaded && top.view) {
            return top.view;
        }
        if (appWindow.rootViewController.isViewLoaded && appWindow.rootViewController.view) {
            return appWindow.rootViewController.view;
        }
    }
    return appWindow;
}

- (UIViewController *)presentationViewController {
    UIWindow *appWindow = [self preferredAppWindow];
    if (appWindow && appWindow.rootViewController) {
        UIViewController *top = TserverGateTopViewController(appWindow.rootViewController);
        if (top.isViewLoaded && top.view.window) {
            return top;
        }
    }
    if (self.window && !self.window.hidden && self.rootViewController) {
        return self.rootViewController;
    }
    return nil;
}

- (void)prepareForExternalPresentation {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // Keep the overlay attached so the auth state does not flash or lose
            // its in-flight callback, but release focus/keyboard before Safari is
            // presented from the actual host controller. Never steal keyWindow.
            [self.hostOverlayView endEditing:YES];
            [self.hostContainerView endEditing:YES];
            [self.rootViewController.view endEditing:YES];
            UIViewController *presenter = [self presentationViewController];
            [presenter.view endEditing:YES];
        } @catch (__unused NSException *exception) {
        }
    });
}

- (void)ensureWindow {
    if (self.window) return;
    self.rootViewController = [TserverGateRootViewController new];
    self.rootViewController.view.backgroundColor = UIColor.clearColor;

    CGRect frame = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:frame];

    if (TserverIsIOS13OrNewer()) {
        id scene = [self activeWindowSceneObject];
        if (scene && [self.window respondsToSelector:NSSelectorFromString(@"setWindowScene:")]) {
            @try {
                [self.window setValue:scene forKey:@"windowScene"];
                id coordinateSpace = [scene valueForKey:@"coordinateSpace"];
                if ([coordinateSpace respondsToSelector:@selector(bounds)]) {
                    NSValue *boundsValue = [coordinateSpace valueForKey:@"bounds"];
                    if ([boundsValue isKindOfClass:NSValue.class]) {
                        self.window.frame = boundsValue.CGRectValue;
                    }
                }
            } @catch (__unused NSException *exception) {
            }
        }
    }

    self.window.rootViewController = self.rootViewController;
    self.window.windowLevel = UIWindowLevelStatusBar + 1;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.hidden = YES;
}

- (void)attachToActiveSceneIfNeeded {
    if (!TserverIsIOS13OrNewer() || !self.window) return;
    id scene = [self activeWindowSceneObject];
    if (!scene) return;
    @try {
        id current = [self.window valueForKey:@"windowScene"];
        if (current != scene && [self.window respondsToSelector:NSSelectorFromString(@"setWindowScene:")]) {
            [self.window setValue:scene forKey:@"windowScene"];
            id coordinateSpace = [scene valueForKey:@"coordinateSpace"];
            NSValue *boundsValue = [coordinateSpace valueForKey:@"bounds"];
            if ([boundsValue isKindOfClass:NSValue.class]) {
                self.window.frame = boundsValue.CGRectValue;
            }
        }
    } @catch (__unused NSException *exception) {
    }
}

- (id)activeWindowSceneObject {
    if (!TserverIsIOS13OrNewer()) return nil;
    id fallback = nil;
    UIApplication *application = UIApplication.sharedApplication;
    if ([application respondsToSelector:@selector(connectedScenes)]) {
        @try {
            NSSet *scenes = [application valueForKey:@"connectedScenes"];
            for (id scene in scenes) {
                if (![NSStringFromClass([scene class]) containsString:@"WindowScene"]) continue;
                NSInteger state = 0;
                if ([scene respondsToSelector:@selector(activationState)]) {
                    state = [[scene valueForKey:@"activationState"] integerValue];
                }
                if (state == 0) {
                    return scene;
                }
                if (!fallback) fallback = scene;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return fallback;
}

- (UIWindow *)preferredAppWindow {
    UIWindow *best = nil;
    NSArray<UIWindow *> *windows = nil;

    if (TserverIsIOS13OrNewer()) {
        @try {
            id scene = [self activeWindowSceneObject];
            if (scene && [scene respondsToSelector:@selector(windows)]) {
                windows = [scene valueForKey:@"windows"];
            }
        } @catch (__unused NSException *exception) {
        }
    }
    if (windows.count == 0) {
        windows = UIApplication.sharedApplication.windows;
    }

    for (UIWindow *window in windows) {
        if (!window || window == self.window || window.hidden) continue;
        if (window.windowLevel > UIWindowLevelNormal + 1) continue;
        if (!window.rootViewController) continue;
        if (!best) {
            best = window;
            continue;
        }
        if (window.isKeyWindow && !best.isKeyWindow) {
            best = window;
            continue;
        }
        CGFloat bestArea = best.bounds.size.width * best.bounds.size.height;
        CGFloat area = window.bounds.size.width * window.bounds.size.height;
        if (area > bestArea) best = window;
    }

    if (!best) {
        for (UIWindow *candidate in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
            if (candidate && candidate != self.window && !candidate.hidden && candidate.rootViewController) {
                best = candidate;
                break;
            }
        }
    }
    return best;
}

@end