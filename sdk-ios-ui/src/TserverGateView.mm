#import <UIKit/UIKit.h>
#import <math.h>
#import "TserverNativeTemplateRenderer.h"
#import "TserverSimpleUiPack.h"
#import "TserverKeyEntryAssist.h"
#import "TserverTemplateRegistry.h"
#import "TserverGateUI.h"

typedef void (^TserverGateActivateBlock)(NSString *key);

@interface TserverUIConfig : NSObject
@property(nonatomic, strong) NSString *layout;
@property(nonatomic, strong) NSString *templateName;
@property(nonatomic, strong) NSDictionary *rawConfig;
- (NSDictionary *)screenConfig:(NSString *)screenName;
- (UIColor *)colorForKey:(NSString *)key fallback:(UIColor *)fallback;
- (CGFloat)radius;
- (BOOL)isLandscapeOrientation;
- (CGFloat)geometryNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
- (NSString *)geometryStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (CGFloat)typographyNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
- (NSString *)typographyStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (NSString *)flowStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (CGFloat)flowNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
- (NSString *)animationType;
- (NSTimeInterval)animationDuration;
- (NSTimeInterval)animationDelay;
- (CGFloat)animationDistance;
- (CGFloat)animationSpringDamping;
- (CGFloat)animationSpringVelocity;
- (NSString *)iconNameForStatus:(NSString *)status;
- (NSDictionary *)popupConfigForScreen:(NSString *)screenName;
@end

@interface TserverComponents : NSObject
+ (UIView *)backgroundViewWithConfig:(TserverUIConfig *)config;
+ (UIView *)logoViewWithConfig:(TserverUIConfig *)config;
+ (UIView *)cardViewWithConfig:(TserverUIConfig *)config;
+ (UILabel *)titleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UILabel *)subtitleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UILabel *)errorLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UIButton *)primaryButton:(NSString *)text config:(TserverUIConfig *)config;
+ (UITextField *)keyTextField:(NSString *)placeholder config:(TserverUIConfig *)config;
+ (UIView *)spinnerContainerWithConfig:(TserverUIConfig *)config;
+ (UILabel *)loadingTitleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UILabel *)loadingSubtitleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UIView *)iconViewForName:(NSString *)iconName config:(TserverUIConfig *)config;
+ (void)configureMultilineLabel:(UILabel *)label;
@end

@interface TserverKeyboard : NSObject
+ (void)installDismissGestureOnView:(UIView *)view;
@end

@interface TserverGateView : UIView
- (instancetype)initWithConfig:(TserverUIConfig *)config;
- (BOOL)renderNotice:(NSDictionary *)notice
             onClose:(dispatch_block_t)onClose
            onSnooze:(dispatch_block_t)onSnooze;
- (void)renderStatus:(NSString *)status
              result:(NSDictionary *)result
               retry:(dispatch_block_t)retry
          onNeedUUID:(dispatch_block_t)needUUID
          onActivate:(TserverGateActivateBlock)activate
       onShowNeedKey:(dispatch_block_t)showNeedKey
          onContinue:(dispatch_block_t)onContinue;
@end

@interface TserverGateView ()
@property(nonatomic, strong) TserverUIConfig *config;
@property(nonatomic, copy) dispatch_block_t needUUIDBlock;
@property(nonatomic, copy) TserverGateActivateBlock activateBlock;
@property(nonatomic, copy) dispatch_block_t retryBlock;
@property(nonatomic, copy) dispatch_block_t showNeedKeyBlock;
@property(nonatomic, copy) dispatch_block_t continueBlock;
@property(nonatomic, strong) UITextField *keyField;
@property(nonatomic, strong) UIView *card;
@property(nonatomic, assign) BOOL continueSubmitted;
@property(nonatomic, assign) NSInteger popupGeneration;
@property(nonatomic, strong) NSMutableArray<NSTimer *> *popupTimers;
@property(nonatomic, strong) NSMutableArray<UIGestureRecognizer *> *continueGestures;
@property(nonatomic, strong) id<TserverSimpleUiPack> simplePack;
- (UIView *)uuidGuidePanelForScreen:(NSDictionary *)screen secondary:(NSString *)secondary;
- (NSArray<NSString *> *)profileStepsForScreen:(NSDictionary *)screen;
- (UIView *)uuidStepRow:(NSString *)text index:(NSUInteger)index;
@end

@implementation TserverGateView

- (UIColor *)compatSystemColor:(SEL)selector fallback:(UIColor *)fallback {
    if ([UIColor respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIColor *color = [UIColor performSelector:selector];
#pragma clang diagnostic pop
        if (color) return color;
    }
    return fallback;
}

- (UIColor *)compatPurple { return [self compatSystemColor:@selector(systemPurpleColor) fallback:[UIColor colorWithRed:0.49 green:0.23 blue:0.93 alpha:1.0]]; }
- (UIColor *)compatTeal { return [self compatSystemColor:@selector(systemTealColor) fallback:[UIColor colorWithRed:0.0 green:0.50 blue:0.50 alpha:1.0]]; }
- (UIColor *)compatGreen { return [self compatSystemColor:@selector(systemGreenColor) fallback:[UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]]; }

- (instancetype)initWithConfig:(TserverUIConfig *)config {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.config = config;
        self.popupTimers = [NSMutableArray array];
        self.continueGestures = [NSMutableArray array];
        [TserverKeyboard installDismissGestureOnView:self];
    }
    return self;
}

/// Render a signed package announcement with the pack assigned to this package.
/// A notice is operator content, not an authorization screen, so it never
/// touches the lease: the caller only supplies the two required dismiss actions.
- (BOOL)renderNotice:(NSDictionary *)notice
             onClose:(dispatch_block_t)onClose
            onSnooze:(dispatch_block_t)onSnooze {
    if (![notice isKindOfClass:NSDictionary.class]) return NO;
    self.continueBlock = nil;
    [self removeContinueGestures];
    [self invalidatePopupTimers];
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSDictionary *renderer = [self.config.rawConfig[@"renderer"] isKindOfClass:NSDictionary.class] ? self.config.rawConfig[@"renderer"] : @{};
    NSString *rendererId = [renderer[@"id"] isKindOfClass:NSString.class] ? renderer[@"id"] : @"";
    self.simplePack = TserverSimpleUiPackCreateForRenderer(rendererId);
    if (!self.simplePack) return NO;

    TserverSimpleUiContext *context = [TserverSimpleUiContext new];
    context.status = @"NOTICE";
    context.result = @{
        @"ok": @YES,
        @"status": @"NOTICE",
        @"noticeId": notice[@"id"] ?: @"",
        @"noticeTitle": notice[@"title"] ?: @"",
        @"noticeMessage": notice[@"message"] ?: @"",
        @"noticeType": notice[@"type"] ?: @"info",
        @"message": notice[@"message"] ?: @""
    };
    context.config = self.config.rawConfig ?: @{};
    // The announcement is modal until the operator/user picks one of the two
    // actions, so it owns touches for as long as it is on screen.
    context.blocksGameTouches = YES;
    context.continueMode = TserverUiContinueModeButton;
    context.noticeClose = onClose;
    context.noticeSnooze = onSnooze;

    UIView *packView = [self.simplePack makeViewWithContext:context];
    packView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:packView];
    [NSLayoutConstraint activateConstraints:@[
        [packView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [packView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [packView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [packView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
    self.accessibilityViewIsModal = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, packView);
    });
    return YES;
}

- (void)renderStatus:(NSString *)status
              result:(NSDictionary *)result
               retry:(dispatch_block_t)retry
          onNeedUUID:(dispatch_block_t)needUUID
          onActivate:(TserverGateActivateBlock)activate
       onShowNeedKey:(dispatch_block_t)showNeedKey
          onContinue:(dispatch_block_t)onContinue {
    self.needUUIDBlock = needUUID;
    self.activateBlock = activate;
    self.retryBlock = retry;
    self.showNeedKeyBlock = showNeedKey;
    self.continueBlock = onContinue;
    self.continueSubmitted = NO;
    self.popupGeneration += 1;
    [self invalidatePopupTimers];
    [self removeContinueGestures];
    self.keyField = nil;
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSDictionary *renderer = [self.config.rawConfig[@"renderer"] isKindOfClass:NSDictionary.class] ? self.config.rawConfig[@"renderer"] : @{};
    NSString *rendererId = [renderer[@"id"] isKindOfClass:NSString.class] ? renderer[@"id"] : @"";
    self.simplePack = TserverSimpleUiPackCreateForRenderer(rendererId);
    if (self.simplePack) {
        TserverSimpleUiContext *context = [TserverSimpleUiContext new];
        context.status = status ?: @"NETWORK_ERROR";
        context.result = result ?: @{};
        context.config = self.config.rawConfig ?: @{};
        context.blocksGameTouches = YES;
        NSDictionary *screens = [self.config.rawConfig[@"screens"] isKindOfClass:NSDictionary.class] ? self.config.rawConfig[@"screens"] : @{};
        NSDictionary *validScreen = [screens[@"valid"] isKindOfClass:NSDictionary.class] ? screens[@"valid"] : @{};
        NSString *screenContinue = [validScreen[@"continueMode"] isKindOfClass:NSString.class] ? validScreen[@"continueMode"] : @"";
        NSString *continueMode = TserverGateNormalizedValidContinueMode(screenContinue.length ? screenContinue : [self.config flowStringForKey:@"validAction" fallback:@"button"]);
        context.continueMode = [continueMode isEqualToString:@"anywhere"] ? TserverUiContinueModeOverlayTap : TserverUiContinueModeButton;
        context.startUuid = needUUID;
        context.submitKey = activate;
        context.retry = retry;
        context.continueAuth = onContinue;
        context.showNeedKey = showNeedKey;
        UIView *packView = [self.simplePack makeViewWithContext:context];
        packView.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:packView];
        [NSLayoutConstraint activateConstraints:@[
            [packView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [packView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [packView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [packView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
        ]];
        self.accessibilityViewIsModal = YES;
        dispatch_async(dispatch_get_main_queue(), ^{ UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, packView); });
        return;
    }

    UIView *background = [TserverComponents backgroundViewWithConfig:self.config];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:background];
    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:self.topAnchor],
        [background.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [background.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];

    UIView *card = [TserverComponents cardViewWithConfig:self.config];
    self.card = card;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:card];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];

    NSString *screenName = [self screenNameForStatus:status];
    NSDictionary *screen = [self.config screenConfig:screenName];
    NSString *message = [result[@"message"] isKindOfClass:NSString.class] ? result[@"message"] : @"";
    NSString *title = [self string:screen[@"title"] fallback:[self fallbackTitleForStatus:status]];
    // Server message wins over pack/default subtitle (custom package maintenance text, etc.).
    NSString *subtitle = message.length > 0
        ? message
        : [self string:screen[@"subtitle"] fallback:[self fallbackSubtitleForStatus:status]];
    NSString *buttonText = [self string:screen[@"buttonText"] fallback:[self fallbackButtonForStatus:status]];
    // A missing URL scheme is a build defect, not an auth outcome: name it, and
    // replace whatever retry/change-key copy the template picked with a Close.
    BOOL isFatalConfigError = TserverGateResultIsFatalConfigError(result);
    if (isFatalConfigError) {
        title = [self string:screen[@"title"] fallback:@"Cấu hình app chưa đúng"];
        buttonText = [self string:screen[@"closeButtonText"] fallback:TserverGateFatalConfigCloseButtonTitle()];
    }

    BOOL isLoading = [status isEqualToString:@"LOADING"];
    BOOL isValid = [self isValidStatus:status];
    stack.spacing = isLoading ? 12 : 14;
    // Optional package logo above content (assets.logo / logoUrl).
    UIView *logo = [TserverComponents logoViewWithConfig:self.config];
    if (logo) [stack addArrangedSubview:logo];
    if (isLoading) {
        [stack addArrangedSubview:[TserverComponents loadingTitleLabel:title config:self.config]];
        [stack addArrangedSubview:[TserverComponents spinnerContainerWithConfig:self.config]];
        [stack addArrangedSubview:[TserverComponents loadingSubtitleLabel:subtitle config:self.config]];
    } else {
        NSString *iconName = [self.config iconNameForStatus:status];
        // Prefer uploaded logo over status FA icon when both present.
        if (iconName.length > 0 && !logo) {
            UIView *icon = [TserverComponents iconViewForName:iconName config:self.config];
            UIView *iconRow = [[UIView alloc] initWithFrame:CGRectZero];
            iconRow.translatesAutoresizingMaskIntoConstraints = NO;
            [iconRow addSubview:icon];
            [NSLayoutConstraint activateConstraints:@[
                [icon.centerXAnchor constraintEqualToAnchor:iconRow.centerXAnchor],
                [icon.centerYAnchor constraintEqualToAnchor:iconRow.centerYAnchor],
                [iconRow.heightAnchor constraintEqualToAnchor:icon.heightAnchor]
            ]];
            [stack addArrangedSubview:iconRow];
        }
        // Optional badge above title (admin template studio).
        NSString *badgeText = [self string:screen[@"badgeText"] fallback:@""];
        if (badgeText.length > 0) {
            UILabel *badge = [TserverComponents subtitleLabel:badgeText config:self.config];
            badge.textAlignment = NSTextAlignmentCenter;
            badge.font = [UIFont systemFontOfSize:MAX(10.0, [self.config typographyNumberForKey:@"badgeSize" fallback:11.0]) weight:UIFontWeightHeavy];
            badge.textColor = [self.config colorForKey:@"accent" fallback:[self compatPurple]];
            [stack addArrangedSubview:badge];
        }
        [stack addArrangedSubview:[TserverComponents titleLabel:title config:self.config]];
        [stack addArrangedSubview:[TserverComponents subtitleLabel:subtitle config:self.config]];
        NSString *secondaryText = [self string:screen[@"secondaryText"] fallback:@""];
        if (secondaryText.length > 0 && ![status isEqualToString:@"NEED_UUID"]) {
            UILabel *secondary = [TserverComponents subtitleLabel:secondaryText config:self.config];
            secondary.font = [UIFont systemFontOfSize:MAX(10.0, [self.config typographyNumberForKey:@"footerSize" fallback:12.0])];
            [stack addArrangedSubview:secondary];
        }
    }

    if ([status isEqualToString:@"NEED_KEY"] || [status isEqualToString:@"INVALID_KEY"]) {
        NSString *placeholder = [self string:screen[@"placeholder"] fallback:@"TSRV-XXXX-XXXX"];
        self.keyField = [TserverComponents keyTextField:placeholder config:self.config];
        [stack addArrangedSubview:self.keyField];
        [self.keyField.heightAnchor constraintEqualToConstant:48].active = YES;

        UIButton *paste = [TserverComponents primaryButton:@"Dán từ clipboard" config:self.config];
        paste.hidden = YES;
        [TserverKeyEntryAssist bindPasteButton:paste toField:self.keyField];
        [stack addArrangedSubview:paste];

        UILabel *keyHint = [TserverComponents subtitleLabel:@"" config:self.config];
        keyHint.hidden = YES;
        keyHint.numberOfLines = 0;
        [TserverKeyEntryAssist bindHintLabel:keyHint toField:self.keyField];
        [stack addArrangedSubview:keyHint];
        UILabel *error = [TserverComponents errorLabel:[status isEqualToString:@"INVALID_KEY"] ? message : @"" config:self.config];
        [stack addArrangedSubview:error];
        UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
        [button addTarget:self action:@selector(activateTapped) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    } else if ([status isEqualToString:@"NEED_UUID"]) {
        // Compact Device Verify strip — keep CTA always visible (landscape / short screens).
        NSString *secondary = [self string:screen[@"secondaryText"]
                                  fallback:@"Cai ho so xac minh de lay ma may. Khong VPN / MDM."];
        UIView *guidePanel = [self uuidGuidePanelForScreen:screen secondary:secondary];
        [stack addArrangedSubview:guidePanel];

        UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
        [button addTarget:self action:@selector(needUUIDTapped) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
        // Prefer CTA over long helper text so the button is never pushed off-screen.
    } else if (isValid) {
        // validContinueMode:
        // - "button" (default): show primary "Tiếp tục" button
        // - "anywhere" / "tap_anywhere": no button; tap anywhere on card/overlay continues
        // "auto" is retired — it dismissed the screen on a timer, which would hide
        // the license details below the moment they were granted.
        // Also accept screens.valid.showButton=false / buttonText=""
        NSString *continueMode = [self validContinueModeForScreen:screen];
        // Report what was authorized before asking the user to continue.
        NSDictionary *licenseInfo = TserverGateLicenseInfoFromResult(result);
        UIView *licenseInfoView = TserverGateLicenseInfoView(licenseInfo,
                                                            [self.config colorForKey:@"text" fallback:UIColor.whiteColor],
                                                            [self.config colorForKey:@"mutedText" fallback:UIColor.lightGrayColor],
                                                            [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]);
        if (licenseInfo.count > 0) {
            [stack addArrangedSubview:licenseInfoView];
        }
        if ([continueMode isEqualToString:@"button"]) {
            UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
            [button addTarget:self action:@selector(continueTapped) forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:button];
        } else {
            // Hint text when user can tap anywhere
            NSString *hint = [self string:screen[@"tapHint"] fallback:@"Chạm vào màn hình để tiếp tục"];
            [stack addArrangedSubview:[TserverComponents subtitleLabel:hint config:self.config]];
            self.userInteractionEnabled = YES;
            self.card.userInteractionEnabled = YES;
            UITapGestureRecognizer *cardTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(continueTapped)];
            [self.card addGestureRecognizer:cardTap];
            [self.continueGestures addObject:cardTap];
            UITapGestureRecognizer *bgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(continueTapped)];
            [self addGestureRecognizer:bgTap];
            [self.continueGestures addObject:bgTap];
        }
    } else if ([status isEqualToString:@"EXPIRED"] ||
               [status isEqualToString:@"REVOKED"] ||
               [status isEqualToString:@"DEVICE_BLOCKED"] ||
               [status isEqualToString:@"DEVICE_MISMATCH"]) {
        UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
        [button addTarget:self action:@selector(showNeedKeyTapped) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    } else if ([status isEqualToString:@"BAD_SESSION"] || [status isEqualToString:@"PROFILE_EXPIRED"]) {
        [stack addArrangedSubview:[TserverComponents errorLabel:[self formattedErrorForStatus:status message:message] config:self.config]];
        UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
        [button addTarget:self action:@selector(needUUIDTapped) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    } else if ([status isEqualToString:@"NETWORK_ERROR"] || [status isEqualToString:@"SERVER_ERROR"]) {
        [stack addArrangedSubview:[TserverComponents errorLabel:[self formattedErrorForStatus:status message:message] config:self.config]];
        if (retry) {
            UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
            [button addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:button];
        }
    } else if ([status isEqualToString:@"UPDATE_REQUIRED"]) {
        UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
        [button addTarget:self action:@selector(openUpdateTapped) forControlEvents:UIControlEventTouchUpInside];
        button.accessibilityValue = [result[@"updateUrl"] isKindOfClass:NSString.class] ? result[@"updateUrl"] : @"";
        [stack addArrangedSubview:button];
    } else if ([status isEqualToString:@"MAINTENANCE"] ||
               [status isEqualToString:@"APP_DISABLED"] ||
               [status isEqualToString:@"STORE_DISABLED"] ||
               [status isEqualToString:@"PACKAGE_DISABLED"] ||
               [status isEqualToString:@"PACKAGE_MAINTENANCE"] ||
               [status isEqualToString:@"PACKAGE_BUNDLE_DENIED"] ||
               [status isEqualToString:@"BAD_PACKAGE_SESSION"] ||
               [status isEqualToString:@"INVALID_API_KEY"] ||
               [status isEqualToString:@"INVALID_CLIENT_API_KEY"]) {
        NSString *errorText = [self formattedErrorForStatus:status message:message];
        if (errorText.length > 0) [stack addArrangedSubview:[TserverComponents errorLabel:errorText config:self.config]];
        if ([status isEqualToString:@"BAD_PACKAGE_SESSION"] && retry) {
            UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
            [button addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:button];
        }
    } else if (isFatalConfigError) {
        // Single Close button that quits. No retry, no key entry: this app can
        // never complete Device Verify, so any other action is a dead end.
        NSString *errorText = [self formattedErrorForStatus:status message:message];
        if (errorText.length > 0) [stack addArrangedSubview:[TserverComponents errorLabel:errorText config:self.config]];
        UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
        [button addTarget:self action:@selector(closeAndTerminateTapped) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    } else if ([self isErrorStatus:status]) {
        NSString *errorText = [self formattedErrorForStatus:status message:message];
        if (errorText.length > 0) {
            [stack addArrangedSubview:[TserverComponents errorLabel:errorText config:self.config]];
        }
        if (retry) {
            UIButton *button = [TserverComponents primaryButton:buttonText config:self.config];
            [button addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
            [stack addArrangedSubview:button];
        }
    }

    // Optional footer/tip under actions (admin template studio: screen.footerText / tipText).
    if (!isLoading) {
        NSString *footerText = [self string:screen[@"footerText"] fallback:[self string:screen[@"tipText"] fallback:@""]];
        if (footerText.length > 0) {
            UILabel *footer = [TserverComponents subtitleLabel:footerText config:self.config];
            footer.font = [UIFont systemFontOfSize:MAX(10.0, [self.config typographyNumberForKey:@"footerSize" fallback:12.0])];
            footer.textColor = [self.config colorForKey:@"mutedText" fallback:UIColor.lightGrayColor];
            [stack addArrangedSubview:footer];
        }
    }

    BOOL landscape = [self.config isLandscapeOrientation];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    // Compact centered panel in landscape — avoid the old 70–72% strip.
    CGFloat landscapeMaxFallback = MIN(400.0, screenW * 0.52);
    CGFloat landscapeInsetFallback = MAX(40.0, screenW * 0.14);
    CGFloat horizontalInset = MIN(120.0, MAX(0.0, [self.config geometryNumberForKey:@"horizontalInset" fallback:landscape ? landscapeInsetFallback : 18.0]));
    CGFloat maxCardWidth = MAX(220.0, [self.config geometryNumberForKey:@"maxCardWidth" fallback:(landscape ? landscapeMaxFallback : ([self.layout isEqualToString:@"fullscreen"] ? 560.0 : 480.0))]);
    CGFloat defaultMinWidth = landscape ? 280.0 : (isLoading ? 320.0 : 300.0);
    CGFloat minCardWidth = MIN(maxCardWidth, MAX(180.0, [self.config geometryNumberForKey:@"minCardWidth" fallback:defaultMinWidth]));
    CGFloat minCardHeight = MAX(0.0, [self.config geometryNumberForKey:@"minCardHeight" fallback:(landscape ? 160.0 : 0.0)]);
    // Prefer intrinsic/content width with max cap. Only honor explicit geometry.width.
    CGFloat fixedWidth = [self.config geometryNumberForKey:@"width" fallback:0.0];
    CGFloat xOffset = [self.config geometryNumberForKey:@"xOffset" fallback:0.0];
    CGFloat yOffset = [self.config geometryNumberForKey:@"yOffset" fallback:0.0];
    NSString *position = [self.config geometryStringForKey:@"position" fallback:@"center"];
    (void)landscape; // orientation already applied via fallbacks above

    NSLayoutConstraint *minWidth = [card.widthAnchor constraintGreaterThanOrEqualToConstant:minCardWidth];
    minWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24],
        [card.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:12],
        [card.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [card.widthAnchor constraintLessThanOrEqualToConstant:maxCardWidth],
        minWidth,
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:horizontalInset],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-horizontalInset]
    ]];
    if (minCardHeight > 0.0) {
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:minCardHeight].active = YES;
    }
    if (fixedWidth > 0.0) {
        NSLayoutConstraint *width = [card.widthAnchor constraintEqualToConstant:MIN(maxCardWidth, MAX(minCardWidth, fixedWidth))];
        width.priority = UILayoutPriorityDefaultHigh;
        width.active = YES;
    } else {
        NSLayoutConstraint *preferredWidth = [card.widthAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.widthAnchor constant:-(horizontalInset * 2)];
        preferredWidth.priority = UILayoutPriorityDefaultHigh;
        preferredWidth.active = YES;
    }

    if ([self.layout isEqualToString:@"bottom_sheet"] || [position isEqualToString:@"bottom"]) {
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor constant:xOffset],
            [card.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-16.0 + yOffset]
        ]];
    } else if ([self.layout isEqualToString:@"fullscreen"]) {
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor constant:xOffset],
            [card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:yOffset],
            [card.heightAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.heightAnchor multiplier:0.92]
        ]];
    } else if ([position isEqualToString:@"top"]) {
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor constant:xOffset],
            [card.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:24.0 + yOffset]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor constant:xOffset],
            [card.centerYAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerYAnchor constant:yOffset]
        ]];
    }

    [TserverNativeTemplateRenderer decorateCard:card
                                    contentStack:stack
                                      background:background
                                          config:self.config.rawConfig ?: @{}
                                          status:status];
    if ([status isEqualToString:@"VALID"] || [status isEqualToString:@"OFFLINE_GRACE_VALID"]) {
        [TserverTemplateRegistry impactForAction:@"success" config:self.config.rawConfig ?: @{}];
    } else if ([self isErrorStatus:status]) {
        [TserverTemplateRegistry impactForAction:@"error" config:self.config.rawConfig ?: @{}];
    }
    self.accessibilityViewIsModal = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, card);
    });
    // Popup overlays are disabled system-wide.
}

- (void)addPopupForScreenName:(NSString *)screenName
                       status:(NSString *)status
                      message:(NSString *)message {
    NSDictionary *popup = [self.config popupConfigForScreen:screenName];
    if (![self boolFromValue:popup[@"enabled"] fallback:NO]) return;

    NSArray<NSDictionary *> *instances = [self popupInstancesFromConfig:popup];
    NSInteger generation = self.popupGeneration;
    // Allow up to 4 concurrent popup instances (was 2).
    NSUInteger limit = MIN((NSUInteger)4, instances.count);
    for (NSUInteger index = 0; index < limit; index += 1) {
        NSDictionary *instance = instances[index];
        CGFloat initialProgress = [self popupInitialProgressForConfig:instance status:status];
        UILabel *progressLabel = nil;
        UILabel *titleLabel = nil;
        UILabel *subtitleLabel = nil;
        NSLayoutConstraint *progressWidth = nil;
        UIView *panel = [self popupPanelForConfig:instance
                                           status:status
                                          message:message
                                         progress:initialProgress
                                    progressLabel:&progressLabel
                                       titleLabel:&titleLabel
                                    subtitleLabel:&subtitleLabel
                                    progressWidth:&progressWidth];
        [self addSubview:panel];
        [self positionPopupPanel:panel config:instance index:index];
        panel.alpha = 0.0;
        panel.transform = CGAffineTransformMakeTranslation(0.0, -10.0);
        [UIView animateWithDuration:0.22 delay:0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
            panel.alpha = 1.0;
            panel.transform = CGAffineTransformIdentity;
        } completion:nil];
        [self animatePopupPanel:panel
                         config:instance
                         status:status
                     generation:generation
                  progressLabel:progressLabel
                     titleLabel:titleLabel
                  subtitleLabel:subtitleLabel
                  progressWidth:progressWidth];
    }
}

- (NSArray<NSDictionary *> *)popupInstancesFromConfig:(NSDictionary *)popup {
    NSMutableDictionary *base = [popup isKindOfClass:NSDictionary.class] ? [popup mutableCopy] : [NSMutableDictionary dictionary];
    NSArray *rawInstances = [base[@"instances"] isKindOfClass:NSArray.class] ? base[@"instances"] : nil;
    NSArray *selectedTemplates = [base[@"selectedTemplates"] isKindOfClass:NSArray.class] ? base[@"selectedTemplates"] : nil;
    [base removeObjectForKey:@"instances"];
    [base removeObjectForKey:@"selectedTemplates"];
    [base removeObjectForKey:@"screens"];

    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    if (rawInstances.count > 0) {
        for (id item in rawInstances) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *merged = [self popupDictionaryByMerging:base override:item];
            if (![self boolFromValue:merged[@"enabled"] fallback:YES]) continue;
            [out addObject:merged];
            if (out.count >= 4) break;
        }
    } else if (selectedTemplates.count > 0) {
        NSArray *fallbackPositions = @[@"topTrailing", @"topLeading", @"bottomTrailing", @"bottomLeading"];
        for (id item in selectedTemplates) {
            if (![item isKindOfClass:NSString.class]) continue;
            NSMutableDictionary *instance = [[self popupDictionaryByMerging:base override:@{ @"template": item }] mutableCopy];
            if (out.count < fallbackPositions.count) {
                instance[@"position"] = fallbackPositions[out.count];
            }
            [out addObject:instance];
            if (out.count >= 4) break;
            if (out.count >= 2) break;
        }
    } else {
        [out addObject:[base copy]];
    }
    return out;
}

- (NSDictionary *)popupDictionaryByMerging:(NSDictionary *)base override:(NSDictionary *)override {
    NSMutableDictionary *merged = [base isKindOfClass:NSDictionary.class] ? [base mutableCopy] : [NSMutableDictionary dictionary];
    if (![override isKindOfClass:NSDictionary.class]) return merged;
    [override enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || object == nil || object == NSNull.null) return;
        id existing = merged[key];
        if ([existing isKindOfClass:NSDictionary.class] && [object isKindOfClass:NSDictionary.class]) {
            merged[key] = [self popupDictionaryByMerging:existing override:object];
        } else {
            merged[key] = object;
        }
    }];
    return merged;
}

- (CGFloat)popupInitialProgressForConfig:(NSDictionary *)popup status:(NSString *)status {
    if (popup[@"progressFrom"] != nil) {
        return MIN(100.0, MAX(0.0, [self numberFromValue:popup[@"progressFrom"] fallback:1.0]));
    }
    CGFloat legacy = [self numberFromValue:popup[@"progress"] fallback:[self isValidStatus:status] ? 100.0 : 40.0];
    return MIN(100.0, MAX(0.0, legacy));
}

- (UIView *)popupPanelForConfig:(NSDictionary *)popup
                         status:(NSString *)status
                        message:(NSString *)message
                       progress:(CGFloat)progress
                  progressLabel:(UILabel **)progressLabel
                     titleLabel:(UILabel **)titleLabel
                  subtitleLabel:(UILabel **)subtitleLabel
                  progressWidth:(NSLayoutConstraint **)progressWidth {
    NSString *templateName = [self string:popup[@"template"] fallback:@"resource_panel"].lowercaseString;
    BOOL compact = [templateName isEqualToString:@"compact_toast"];
    CGFloat width = MIN(compact ? 320.0 : 380.0, MAX(150.0, [self numberFromValue:popup[@"width"] fallback:compact ? 232.0 : 264.0]));
    CGFloat opacity = MIN(1.0, MAX(0.08, [self numberFromValue:popup[@"opacity"] fallback:compact ? 0.90 : 0.84]));
    CGFloat radius = MIN(36.0, MAX(8.0, [self numberFromValue:popup[@"radius"] fallback:compact ? 22.0 : 24.0]));
    NSString *title = [self string:popup[@"title"] fallback:[self fallbackTitleForStatus:status]];
    NSString *subtitle = [self string:popup[@"subtitle"] fallback:message.length > 0 ? message : [self fallbackSubtitleForStatus:status]];
    BOOL showProgress = [self boolFromValue:popup[@"showProgress"] fallback:YES];
    BOOL showSteps = [self boolFromValue:popup[@"showSteps"] fallback:!compact];

    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [[self.config colorForKey:@"card" fallback:[UIColor colorWithWhite:0.08 alpha:1.0]] colorWithAlphaComponent:opacity];
    panel.layer.cornerRadius = radius;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [[self.config colorForKey:@"mutedText" fallback:UIColor.grayColor] colorWithAlphaComponent:0.25].CGColor;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.28;
    panel.layer.shadowRadius = compact ? 12.0 : 18.0;
    panel.layer.shadowOffset = CGSizeMake(0, compact ? 8.0 : 10.0);

    UIStackView *root = [[UIStackView alloc] initWithFrame:CGRectZero];
    root.axis = UILayoutConstraintAxisVertical;
    root.spacing = compact ? 7.0 : 9.0;
    root.alignment = UIStackViewAlignmentFill;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:root];

    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = compact ? 9.0 : 12.0;
    [root addArrangedSubview:row];

    UILabel *badgeLabel = nil;
    if (showProgress) {
        CGFloat size = compact ? 30.0 : 42.0;
        UIView *badge = [[UIView alloc] initWithFrame:CGRectZero];
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        badge.layer.cornerRadius = size * 0.5;
        badge.layer.borderWidth = compact ? 2.0 : 3.0;
        UIColor *accent = [self.config colorForKey:@"accent" fallback:[self compatTeal]];
        badge.layer.borderColor = accent.CGColor;
        badge.backgroundColor = [accent colorWithAlphaComponent:0.16];
        [NSLayoutConstraint activateConstraints:@[
            [badge.widthAnchor constraintEqualToConstant:size],
            [badge.heightAnchor constraintEqualToConstant:size]
        ]];
        badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        badgeLabel.textAlignment = NSTextAlignmentCenter;
        badgeLabel.textColor = accent;
        badgeLabel.font = [UIFont systemFontOfSize:compact ? 10.0 : 11.0 weight:UIFontWeightBold];
        [badge addSubview:badgeLabel];
        [NSLayoutConstraint activateConstraints:@[
            [badgeLabel.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
            [badgeLabel.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor]
        ]];
        [row addArrangedSubview:badge];
    }

    UIStackView *content = [[UIStackView alloc] initWithFrame:CGRectZero];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = compact ? 3.0 : 5.0;
    content.alignment = UIStackViewAlignmentFill;
    [row addArrangedSubview:content];

    UILabel *titleOut = [self popupLabel:title size:compact ? 13.0 : 15.0 weight:UIFontWeightBold colorKey:@"text"];
    [content addArrangedSubview:titleOut];
    UILabel *subtitleOut = [self popupLabel:subtitle size:compact ? 11.0 : 12.0 weight:UIFontWeightRegular colorKey:@"mutedText"];
    if (subtitle.length > 0) [content addArrangedSubview:subtitleOut];

    UIView *barTrack = nil;
    NSLayoutConstraint *barWidthOut = nil;
    if (showProgress && !compact) {
        barTrack = [[UIView alloc] initWithFrame:CGRectZero];
        barTrack.translatesAutoresizingMaskIntoConstraints = NO;
        barTrack.backgroundColor = [[self.config colorForKey:@"mutedText" fallback:UIColor.grayColor] colorWithAlphaComponent:0.18];
        barTrack.layer.cornerRadius = 3.0;
        [root addArrangedSubview:barTrack];
        UIView *bar = [[UIView alloc] initWithFrame:CGRectZero];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        bar.backgroundColor = [self.config colorForKey:@"accent" fallback:[self compatTeal]];
        bar.layer.cornerRadius = 3.0;
        [barTrack addSubview:bar];
        barWidthOut = [bar.widthAnchor constraintEqualToConstant:0.0];
        [NSLayoutConstraint activateConstraints:@[
            [barTrack.heightAnchor constraintEqualToConstant:6.0],
            [bar.leadingAnchor constraintEqualToAnchor:barTrack.leadingAnchor],
            [bar.topAnchor constraintEqualToAnchor:barTrack.topAnchor],
            [bar.bottomAnchor constraintEqualToAnchor:barTrack.bottomAnchor],
            barWidthOut
        ]];
    }

    NSArray *steps = [popup[@"steps"] isKindOfClass:NSArray.class] ? popup[@"steps"] : @[];
    if (showSteps && steps.count > 0 && !compact) {
        UIStackView *stepStack = [[UIStackView alloc] initWithFrame:CGRectZero];
        stepStack.axis = UILayoutConstraintAxisVertical;
        stepStack.spacing = 8.0;
        [root addArrangedSubview:stepStack];
        NSUInteger limit = MIN((NSUInteger)4, steps.count);
        for (NSUInteger index = 0; index < limit; index += 1) {
            NSString *stepText = [steps[index] isKindOfClass:NSString.class] ? steps[index] : @"";
            stepText = [stepText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (stepText.length == 0) continue;
            [stepStack addArrangedSubview:[self popupStepRow:stepText done:(progress >= ((CGFloat)(index + 1) / (CGFloat)limit) * 100.0)]];
        }
    }

    CGFloat pad = compact ? 10.0 : 12.0;
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:panel.topAnchor constant:pad],
        [root.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],
        [root.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-pad - 2.0],
        [root.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-pad],
        [panel.widthAnchor constraintEqualToConstant:width]
    ]];

    [self updatePopupProgressLabel:badgeLabel titleLabel:titleOut subtitleLabel:subtitleOut progress:progress status:status complete:NO config:popup];
    [self updatePopupProgressWidth:barWidthOut progress:progress];
    if (progressLabel) *progressLabel = badgeLabel;
    if (titleLabel) *titleLabel = titleOut;
    if (subtitleLabel) *subtitleLabel = subtitleOut;
    if (progressWidth) *progressWidth = barWidthOut;
    return panel;
}

- (void)positionPopupPanel:(UIView *)panel config:(NSDictionary *)popup index:(NSUInteger)index {
    NSString *position = [self string:popup[@"position"] fallback:@"topTrailing"];
    CGFloat inset = 20.0;
    CGFloat offset = (CGFloat)index * 108.0;
    // Free placement modes:
    // - position=custom + xPercent/yPercent (0–100 of safe area)
    // - position=free / px + xPx/yPx (absolute pt from safe-area top-leading)
    // - legacy x/y treated as percent when no *Px keys
    BOOL hasPx = popup[@"xPx"] != nil || popup[@"yPx"] != nil || [position isEqualToString:@"free"] || [position isEqualToString:@"px"];
    BOOL hasFreeX = popup[@"xPercent"] != nil || popup[@"x"] != nil;
    BOOL hasFreeY = popup[@"yPercent"] != nil || popup[@"y"] != nil;
    if ([position isEqualToString:@"custom"] || [position isEqualToString:@"free"] || [position isEqualToString:@"px"] || hasFreeX || hasFreeY || hasPx) {
        CGFloat xOff = [self numberFromValue:popup[@"xOffset"] fallback:0.0];
        CGFloat yOff = [self numberFromValue:popup[@"yOffset"] fallback:0.0] + offset * 0.15;
        if (hasPx && (popup[@"xPx"] != nil || popup[@"yPx"] != nil || [position isEqualToString:@"free"] || [position isEqualToString:@"px"])) {
            CGFloat xPx = [self numberFromValue:popup[@"xPx"] fallback:[self numberFromValue:popup[@"x"] fallback:inset]];
            CGFloat yPx = [self numberFromValue:popup[@"yPx"] fallback:[self numberFromValue:popup[@"y"] fallback:inset]] + offset * 0.15;
            [NSLayoutConstraint activateConstraints:@[
                [panel.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:MAX(0.0, xPx + xOff)],
                [panel.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:MAX(0.0, yPx + yOff)]
            ]];
            return;
        }
        CGFloat xPercent = MIN(100.0, MAX(0.0, [self numberFromValue:popup[@"xPercent"] fallback:[self numberFromValue:popup[@"x"] fallback:80.0]]));
        CGFloat yPercent = MIN(100.0, MAX(0.0, [self numberFromValue:popup[@"yPercent"] fallback:[self numberFromValue:popup[@"y"] fallback:8.0]]));
        // Percent of safe-area size via layout guides + multipliers on width/height.
        // centerX = leading + safeWidth * (xPercent/100); approximate with center offset from mid.
        CGFloat screenW = MAX(1.0, UIScreen.mainScreen.bounds.size.width);
        CGFloat screenH = MAX(1.0, UIScreen.mainScreen.bounds.size.height);
        CGFloat xConst = ((xPercent / 100.0) - 0.5) * screenW + xOff;
        CGFloat yConst = ((yPercent / 100.0) - 0.5) * screenH + yOff;
        [NSLayoutConstraint activateConstraints:@[
            [panel.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor constant:xConst],
            [panel.centerYAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerYAnchor constant:yConst]
        ]];
        return;
    }
    if ([position isEqualToString:@"topLeading"]) {
        [NSLayoutConstraint activateConstraints:@[
            [panel.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:inset + offset],
            [panel.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:inset]
        ]];
    } else if ([position isEqualToString:@"bottomTrailing"]) {
        [NSLayoutConstraint activateConstraints:@[
            [panel.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-inset - offset],
            [panel.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-inset]
        ]];
    } else if ([position isEqualToString:@"bottomLeading"]) {
        [NSLayoutConstraint activateConstraints:@[
            [panel.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-inset - offset],
            [panel.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:inset]
        ]];
    } else if ([position isEqualToString:@"center"]) {
        [NSLayoutConstraint activateConstraints:@[
            [panel.centerXAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerXAnchor],
            [panel.centerYAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.centerYAnchor constant:offset * 0.2]
        ]];
    } else {
        // topTrailing default
        [NSLayoutConstraint activateConstraints:@[
            [panel.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:inset + offset],
            [panel.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-inset]
        ]];
    }
}

- (void)animatePopupPanel:(UIView *)panel
                   config:(NSDictionary *)popup
                   status:(NSString *)status
               generation:(NSInteger)generation
            progressLabel:(UILabel *)progressLabel
               titleLabel:(UILabel *)titleLabel
            subtitleLabel:(UILabel *)subtitleLabel
            progressWidth:(NSLayoutConstraint *)progressWidth {
    BOOL hasLegacyProgress = popup[@"progress"] != nil;
    BOOL animateProgress = [self boolFromValue:popup[@"animateProgress"] fallback:!hasLegacyProgress];
    CGFloat from = [self popupInitialProgressForConfig:popup status:status];
    CGFloat to = MIN(100.0, MAX(0.0, [self numberFromValue:popup[@"progressTo"] fallback:hasLegacyProgress ? from : 100.0]));
    BOOL terminalStatus = [self isValidStatus:status] || (![status isEqualToString:@"LOADING"] &&
        ![status isEqualToString:@"NEED_UUID"] && ![status isEqualToString:@"NEED_KEY"]);
    if (!terminalStatus) to = MIN(95.0, to);
    NSTimeInterval duration = MIN(30.0, MAX(0.15, [self numberFromValue:popup[@"durationMs"] fallback:1800.0] / 1000.0));
    BOOL shouldComplete = terminalStatus && to >= 100.0 &&
        (animateProgress || popup[@"completeTitle"] || popup[@"completeSubtitle"] || popup[@"durationMs"]);
    if (!animateProgress || fabs(to - from) < 0.1) {
        [self updatePopupProgressLabel:progressLabel titleLabel:titleLabel subtitleLabel:subtitleLabel progress:to status:status complete:shouldComplete config:popup];
        [self updatePopupProgressWidth:progressWidth progress:to];
        [self updatePopupStepsInPanel:panel progress:to complete:shouldComplete];
        if (shouldComplete) [self completePopupPanel:panel config:popup generation:generation titleLabel:titleLabel subtitleLabel:subtitleLabel];
        return;
    }

    __block NSInteger tick = 0;
    NSInteger tickCount = MAX(1, (NSInteger)ceil(duration / 0.08));
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.08 repeats:YES block:^(NSTimer *timer) {
        if (generation != self.popupGeneration || !panel.superview) {
            [timer invalidate];
            return;
        }
        tick += 1;
        CGFloat t = MIN(1.0, (CGFloat)tick / (CGFloat)tickCount);
        CGFloat eased = 1.0 - pow(1.0 - t, 2.0);
        CGFloat progress = from + ((to - from) * eased);
        BOOL complete = t >= 1.0 && shouldComplete;
        [self updatePopupProgressLabel:progressLabel titleLabel:titleLabel subtitleLabel:subtitleLabel progress:progress status:status complete:complete config:popup];
        [self updatePopupProgressWidth:progressWidth progress:progress];
        [self updatePopupStepsInPanel:panel progress:progress complete:complete];
        if (t >= 1.0) {
            [timer invalidate];
            if (shouldComplete) {
                [self completePopupPanel:panel config:popup generation:generation titleLabel:titleLabel subtitleLabel:subtitleLabel];
            }
        }
    }];
    [self.popupTimers addObject:timer];
}

- (void)updatePopupProgressLabel:(UILabel *)progressLabel
                      titleLabel:(UILabel *)titleLabel
                   subtitleLabel:(UILabel *)subtitleLabel
                        progress:(CGFloat)progress
                          status:(NSString *)status
                        complete:(BOOL)complete
                          config:(NSDictionary *)popup {
    BOOL done = complete || progress >= 100.0 || [self isValidStatus:status];
    UIColor *accent = [self.config colorForKey:@"accent" fallback:[self compatTeal]];
    UIColor *success = [self.config colorForKey:@"success" fallback:[self compatGreen]];
    if (progressLabel) {
        progressLabel.textColor = done ? success : accent;
        progressLabel.font = [UIFont systemFontOfSize:done ? 18.0 : 11.0 weight:UIFontWeightBold];
        progressLabel.text = done ? @"✓" : [NSString stringWithFormat:@"%.0f", MIN(100.0, MAX(0.0, progress))];
    }
    if (done) {
        NSString *completeTitle = [self string:popup[@"completeTitle"] fallback:titleLabel.text ?: @""];
        NSString *completeSubtitle = [self string:popup[@"completeSubtitle"] fallback:subtitleLabel.text ?: @""];
        if (completeTitle.length > 0) titleLabel.text = completeTitle;
        if (completeSubtitle.length > 0) subtitleLabel.text = completeSubtitle;
    }
}

- (void)updatePopupProgressWidth:(NSLayoutConstraint *)progressWidth progress:(CGFloat)progress {
    if (!progressWidth) return;
    UIView *bar = progressWidth.firstItem;
    UIView *track = bar.superview;
    if (!bar || !track) return;
    CGFloat ratio = MIN(1.0, MAX(0.0, progress / 100.0));
    CGFloat trackWidth = CGRectGetWidth(track.bounds);
    if (trackWidth <= 0.0) trackWidth = 160.0;
    CGFloat width = trackWidth * ratio;
    if (width <= 0.0 && ratio > 0.0) width = 2.0;
    progressWidth.constant = width;
    [track layoutIfNeeded];
}

- (void)completePopupPanel:(UIView *)panel
                    config:(NSDictionary *)popup
                generation:(NSInteger)generation
                titleLabel:(UILabel *)titleLabel
             subtitleLabel:(UILabel *)subtitleLabel {
    BOOL collapse = [self boolFromValue:popup[@"collapseOnComplete"] fallback:YES];
    if (!collapse) return;
    NSTimeInterval delay = MIN(10.0, MAX(0.0, [self numberFromValue:popup[@"collapseDelayMs"] fallback:550.0] / 1000.0));
    NSTimeInterval duration = MIN(2.0, MAX(0.12, [self numberFromValue:popup[@"collapseDurationMs"] fallback:260.0] / 1000.0));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self.popupGeneration || !panel.superview) return;
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            panel.alpha = 0.0;
            panel.transform = CGAffineTransformMakeScale(0.82, 0.82);
        } completion:^(__unused BOOL finished) {
            [panel removeFromSuperview];
        }];
    });
}

- (UIView *)uuidGuidePanelForScreen:(NSDictionary *)screen secondary:(NSString *)secondary {
    // Minimal Device Verify strip — short copy + up to 3 compact steps so CTA stays on screen.
    UIColor *accent = [self.config colorForKey:@"accent" fallback:[UIColor colorWithRed:0.47 green:0.40 blue:0.93 alpha:1.0]];
    UIColor *card = [self.config colorForKey:@"card" fallback:[UIColor colorWithRed:0.08 green:0.12 blue:0.19 alpha:1.0]];
    UIColor *muted = [self.config colorForKey:@"mutedText" fallback:[UIColor colorWithWhite:0.72 alpha:1.0]];

    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [card colorWithAlphaComponent:0.55];
    panel.layer.cornerRadius = 14.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;

    UIStackView *root = [[UIStackView alloc] initWithFrame:CGRectZero];
    root.axis = UILayoutConstraintAxisVertical;
    root.spacing = 8.0;
    root.alignment = UIStackViewAlignmentFill;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:root];

    UIStackView *head = [[UIStackView alloc] initWithFrame:CGRectZero];
    head.axis = UILayoutConstraintAxisHorizontal;
    head.alignment = UIStackViewAlignmentCenter;
    head.spacing = 8.0;
    [root addArrangedSubview:head];

    UILabel *pill = [[UILabel alloc] initWithFrame:CGRectZero];
    pill.text = @"  Device Verify  ";
    pill.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightHeavy];
    pill.textColor = accent;
    pill.backgroundColor = [accent colorWithAlphaComponent:0.14];
    pill.layer.cornerRadius = 999.0;
    pill.layer.masksToBounds = YES;
    pill.layer.borderWidth = 1.0;
    pill.layer.borderColor = [accent colorWithAlphaComponent:0.24].CGColor;
    [head addArrangedSubview:pill];

    UILabel *oneLine = [[UILabel alloc] initWithFrame:CGRectZero];
    NSString *profileSubtitle = [self string:screen[@"profileSubtitle"]
                                    fallback:(secondary.length > 0 ? secondary : @"Ho so chi de xac minh thiet bi.")];
    oneLine.text = profileSubtitle;
    oneLine.textColor = muted;
    oneLine.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    oneLine.numberOfLines = 2;
    [root addArrangedSubview:oneLine];

    NSArray<NSString *> *profileSteps = [self profileStepsForScreen:screen];
    if (profileSteps.count > 0) {
        UIStackView *stepsStack = [[UIStackView alloc] initWithFrame:CGRectZero];
        stepsStack.axis = UILayoutConstraintAxisVertical;
        stepsStack.spacing = 4.0;
        [root addArrangedSubview:stepsStack];
        // Max 3 short rows — enough guidance without covering the Lay UUID button.
        NSUInteger limit = MIN((NSUInteger)3, profileSteps.count);
        for (NSUInteger index = 0; index < limit; index += 1) {
            [stepsStack addArrangedSubview:[self uuidStepRow:profileSteps[index] index:index + 1]];
        }
    }

    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:panel.topAnchor constant:10.0],
        [root.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12.0],
        [root.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12.0],
        [root.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-10.0]
    ]];
    return panel;
}

- (NSArray<NSString *> *)profileStepsForScreen:(NSDictionary *)screen {
    id raw = screen[@"profileSteps"] ?: screen[@"profileStepsText"];
    NSMutableArray<NSString *> *steps = [NSMutableArray array];
    if ([raw isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)raw) {
            NSString *text = [item isKindOfClass:NSString.class] ? item : @"";
            text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (text.length > 0) [steps addObject:text];
            if (steps.count >= 3) break;
        }
    } else if ([raw isKindOfClass:NSString.class]) {
        for (NSString *item in [(NSString *)raw componentsSeparatedByString:@"\n"]) {
            NSString *text = [item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (text.length > 0) [steps addObject:text];
            if (steps.count >= 3) break;
        }
    }
    if (steps.count > 0) return [steps copy];
    return @[
        @"Bam Lay UUID",
        @"Cho phep tai ho so",
        @"Cai dat > Ho so da tai > Cai dat"
    ];
}

- (UIView *)uuidStepRow:(NSString *)text index:(NSUInteger)index {
    UIColor *accent = [self.config colorForKey:@"accent" fallback:[UIColor colorWithRed:0.47 green:0.40 blue:0.93 alpha:1.0]];
    UIColor *textColor = [self.config colorForKey:@"text" fallback:UIColor.whiteColor];

    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8.0;
    row.alignment = UIStackViewAlignmentCenter;

    UILabel *number = [[UILabel alloc] initWithFrame:CGRectZero];
    number.translatesAutoresizingMaskIntoConstraints = NO;
    number.textAlignment = NSTextAlignmentCenter;
    number.text = [NSString stringWithFormat:@"%lu", (unsigned long)index];
    number.textColor = UIColor.whiteColor;
    number.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBlack];
    number.backgroundColor = accent;
    number.layer.cornerRadius = 9.0;
    number.layer.masksToBounds = YES;
    [row addArrangedSubview:number];
    [NSLayoutConstraint activateConstraints:@[
        [number.widthAnchor constraintEqualToConstant:18.0],
        [number.heightAnchor constraintEqualToConstant:18.0]
    ]];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text ?: @"";
    label.textColor = textColor;
    label.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [row addArrangedSubview:label];
    return row;
}

- (UIView *)popupBadgeForProgress:(CGFloat)progress status:(NSString *)status {
    CGFloat size = 42.0;
    UIView *badge = [[UIView alloc] initWithFrame:CGRectZero];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.layer.cornerRadius = size * 0.5;
    badge.layer.borderWidth = 3.0;
    UIColor *accent = [self.config colorForKey:@"accent" fallback:[self compatTeal]];
    UIColor *success = [self.config colorForKey:@"success" fallback:[self compatGreen]];
    BOOL done = progress >= 100.0 || [self isValidStatus:status];
    badge.layer.borderColor = (done ? success : accent).CGColor;
    badge.backgroundColor = [(done ? success : accent) colorWithAlphaComponent:0.16];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:size],
        [badge.heightAnchor constraintEqualToConstant:size]
    ]];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = done ? success : accent;
    label.font = [UIFont systemFontOfSize:done ? 20.0 : 11.0 weight:UIFontWeightBold];
    label.text = done ? @"✓" : [NSString stringWithFormat:@"%.0f", progress];
    [badge addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:badge.leadingAnchor constant:2.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:badge.trailingAnchor constant:-2.0]
    ]];
    return badge;
}

- (UIView *)popupStepRow:(NSString *)text done:(BOOL)done {
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 9.0;
    row.alignment = UIStackViewAlignmentCenter;
    row.accessibilityValue = done ? @"done" : @"pending";

    UILabel *check = [[UILabel alloc] initWithFrame:CGRectZero];
    check.text = done ? @"✓" : @"•";
    check.tag = 7001;
    check.textAlignment = NSTextAlignmentCenter;
    check.textColor = done ? [self.config colorForKey:@"success" fallback:[self compatGreen]] : [self.config colorForKey:@"mutedText" fallback:UIColor.grayColor];
    check.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    [row addArrangedSubview:check];
    [check.widthAnchor constraintEqualToConstant:18.0].active = YES;

    UILabel *label = [self popupLabel:text size:12.0 weight:UIFontWeightRegular colorKey:@"mutedText"];
    label.tag = 7002;
    label.textAlignment = NSTextAlignmentLeft;
    [row addArrangedSubview:label];
    return row;
}

- (void)updatePopupStepsInPanel:(UIView *)panel progress:(CGFloat)progress complete:(BOOL)complete {
    NSMutableArray<UIStackView *> *rows = [NSMutableArray array];
    [self collectPopupStepRowsInView:panel rows:rows];
    if (rows.count == 0) return;
    CGFloat safeProgress = MIN(100.0, MAX(0.0, progress));
    UIColor *success = [self.config colorForKey:@"success" fallback:[self compatGreen]];
    UIColor *muted = [self.config colorForKey:@"mutedText" fallback:UIColor.grayColor];
    for (NSUInteger index = 0; index < rows.count; index += 1) {
        UIStackView *row = rows[index];
        BOOL done = complete || safeProgress >= (((CGFloat)index + 1.0) / (CGFloat)rows.count) * 100.0;
        if ([row.accessibilityValue isEqualToString:(done ? @"done" : @"pending")]) continue;
        row.accessibilityValue = done ? @"done" : @"pending";
        for (UIView *subview in row.arrangedSubviews) {
            if ([subview isKindOfClass:UILabel.class]) {
                UILabel *label = (UILabel *)subview;
                if (label.tag == 7001) {
                    label.text = done ? @"✓" : @"•";
                    label.textColor = done ? success : muted;
                } else if (label.tag == 7002) {
                    label.textColor = done ? [self.config colorForKey:@"text" fallback:UIColor.whiteColor] : muted;
                }
            }
        }
    }
}

- (void)collectPopupStepRowsInView:(UIView *)view rows:(NSMutableArray<UIStackView *> *)rows {
    if ([view isKindOfClass:UIStackView.class] && (((UIStackView *)view).arrangedSubviews.count > 0)) {
        UIStackView *stack = (UIStackView *)view;
        BOOL isStepRow = NO;
        for (UIView *subview in stack.arrangedSubviews) {
            if ([subview isKindOfClass:UILabel.class] && ((UILabel *)subview).tag == 7001) {
                isStepRow = YES;
                break;
            }
        }
        if (isStepRow) [rows addObject:stack];
    }
    for (UIView *subview in view.subviews) {
        [self collectPopupStepRowsInView:subview rows:rows];
    }
}

- (UILabel *)popupLabel:(NSString *)text
                   size:(CGFloat)size
                 weight:(UIFontWeight)weight
               colorKey:(NSString *)colorKey {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text ?: @"";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentLeft;
    label.textColor = [self.config colorForKey:colorKey fallback:UIColor.whiteColor];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    [TserverComponents configureMultilineLabel:label];
    return label;
}

- (BOOL)boolFromValue:(id)value fallback:(BOOL)fallback {
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

- (CGFloat)numberFromValue:(id)value fallback:(CGFloat)fallback {
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

- (void)invalidatePopupTimers {
    for (NSTimer *timer in self.popupTimers) {
        [timer invalidate];
    }
    [self.popupTimers removeAllObjects];
}

- (void)removeContinueGestures {
    for (UIGestureRecognizer *gesture in self.continueGestures) {
        [gesture.view removeGestureRecognizer:gesture];
    }
    [self.continueGestures removeAllObjects];
}

- (void)dealloc {
    [self invalidatePopupTimers];
    [self removeContinueGestures];
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (!self.superview || !self.card) return;
    if ([TserverTemplateRegistry reduceMotionEnabled]) return;
    NSString *type = self.config.animationType.lowercaseString ?: @"scale";
    NSTimeInterval duration = self.config.animationDuration;
    if (duration <= 0.0 || [type isEqualToString:@"none"]) return;
    CGFloat distance = self.config.animationDistance;
    CGFloat finalAlpha = MIN(1.0, MAX(0.0, [self.config geometryNumberForKey:@"cardOpacity" fallback:1.0]));
    CGAffineTransform initialTransform = CGAffineTransformIdentity;
    BOOL useSpring = NO;
    CGFloat damping = 0.72;
    CGFloat velocity = 0.85;
    if ([type isEqualToString:@"scale"]) {
        initialTransform = CGAffineTransformMakeScale(0.92, 0.92);
    } else if ([type isEqualToString:@"slide_up"]) {
        initialTransform = CGAffineTransformMakeTranslation(0.0, distance);
    } else if ([type isEqualToString:@"slide_down"]) {
        initialTransform = CGAffineTransformMakeTranslation(0.0, -distance);
    } else if ([type isEqualToString:@"slide_left"]) {
        initialTransform = CGAffineTransformMakeTranslation(distance, 0.0);
    } else if ([type isEqualToString:@"slide_right"]) {
        initialTransform = CGAffineTransformMakeTranslation(-distance, 0.0);
    } else if ([type isEqualToString:@"bounce"]) {
        initialTransform = CGAffineTransformMakeScale(0.86, 0.86);
        useSpring = YES;
        damping = 0.62;
        velocity = 1.05;
    } else if ([type isEqualToString:@"spring"]) {
        // Spring = scale-in + slight rise with soft spring curve.
        initialTransform = CGAffineTransformConcat(
            CGAffineTransformMakeScale(0.88, 0.88),
            CGAffineTransformMakeTranslation(0.0, distance * 0.55)
        );
        useSpring = YES;
        damping = 0.68;
        velocity = 0.95;
    } else if ([type isEqualToString:@"fade"] || [type isEqualToString:@"fade_only"]) {
        initialTransform = CGAffineTransformIdentity;
    }
    // unknown type → fade only
    self.card.alpha = 0.0;
    self.card.transform = initialTransform;
    damping = self.config.animationSpringDamping;
    velocity = self.config.animationSpringVelocity;
    if (useSpring) {
        [UIView animateWithDuration:MAX(0.18, duration)
                              delay:self.config.animationDelay
             usingSpringWithDamping:damping
              initialSpringVelocity:velocity
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            self.card.alpha = finalAlpha;
            self.card.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:duration
                              delay:self.config.animationDelay
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.card.alpha = finalAlpha;
            self.card.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (NSString *)layout {
    return self.config.layout ?: @"floating";
}

- (BOOL)isValidStatus:(NSString *)status {
    return [status isEqualToString:@"VALID"] || [status isEqualToString:@"OFFLINE_GRACE_VALID"];
}

- (NSString *)screenNameForStatus:(NSString *)status {
    if ([status isEqualToString:@"LOADING"]) return @"loading";
    if ([status isEqualToString:@"NEED_UUID"]) return @"needUuid";
    if ([status isEqualToString:@"NEED_KEY"] || [status isEqualToString:@"INVALID_KEY"]) return @"needKey";
    if ([self isValidStatus:status]) return @"valid";
    if ([status isEqualToString:@"EXPIRED"]) return @"expired";
    if ([status isEqualToString:@"REVOKED"]) return @"revoked";
    if ([status isEqualToString:@"DEVICE_MISMATCH"]) return @"deviceMismatch";
    if ([status isEqualToString:@"NETWORK_ERROR"]) return @"networkError";
    if ([status isEqualToString:@"SERVER_ERROR"]) return @"serverError";
    if ([status isEqualToString:@"BAD_CLIENT_SIGNATURE"] || [status isEqualToString:@"REPLAY_REQUEST"] || [status isEqualToString:@"RATE_LIMITED"]) return @"networkError";
    if ([status isEqualToString:@"BAD_RESPONSE_SIGNATURE"] || [status isEqualToString:@"BAD_SIGNATURE"]) return @"networkError";
    if ([status isEqualToString:@"AUTHORIZATION_LEASE_INVALID"]) return @"serverError";
    if ([status isEqualToString:@"BAD_SESSION"] || [status isEqualToString:@"PROFILE_EXPIRED"] ||
        [status hasPrefix:@"PROFILE_CHALLENGE_"] || [status isEqualToString:@"PROFILE_UDID_MISSING"] ||
        [status isEqualToString:@"PROFILE_SESSION_NOT_CONFIRMABLE"]) return @"needUuid";
    if ([status isEqualToString:@"BAD_PACKAGE_SESSION"]) return @"badPackageSession";
    if ([status isEqualToString:@"DEVICE_BLOCKED"]) return @"deviceBlocked";
    if ([status isEqualToString:@"TRIAL_ALREADY_USED"]) return @"needKey";
    if ([status isEqualToString:@"OFFLINE_GRACE_EXPIRED"]) return @"expired";
    if ([status isEqualToString:@"UPDATE_REQUIRED"]) return @"updateRequired";
    if ([status isEqualToString:@"MAINTENANCE"]) return @"maintenance";
    if ([status isEqualToString:@"APP_DISABLED"]) return @"appDisabled";
    if ([status isEqualToString:@"STORE_DISABLED"]) return @"storeDisabled";
    if ([status isEqualToString:@"PACKAGE_DISABLED"]) return @"packageDisabled";
    if ([status isEqualToString:@"PACKAGE_MAINTENANCE"]) return @"packageMaintenance";
    if ([status isEqualToString:@"PACKAGE_BUNDLE_DENIED"]) return @"packageBundleDenied";
    if ([status isEqualToString:@"INVALID_API_KEY"]) return @"invalidApiKey";
    if ([status isEqualToString:@"INVALID_CLIENT_API_KEY"]) return @"invalidClientApiKey";
    if ([status isEqualToString:@"CLIENT_KEY_UNAVAILABLE"]) return @"clientKeyUnavailable";
    return @"networkError";
}

- (NSString *)fallbackTitleForStatus:(NSString *)status {
    if ([status isEqualToString:@"LOADING"]) return @"Dang kiem tra key";
    if ([self isValidStatus:status]) return @"Key hop le";
    if ([status isEqualToString:@"NEED_UUID"]) return @"Xac minh thiet bi";
    if ([status isEqualToString:@"NEED_KEY"]) return @"Nhap key";
    if ([status isEqualToString:@"INVALID_KEY"]) return @"Key khong hop le";
    if ([status isEqualToString:@"EXPIRED"]) return @"Key da het han";
    if ([status isEqualToString:@"REVOKED"]) return @"Ban da bi ban key";
    if ([status isEqualToString:@"DEVICE_MISMATCH"]) return @"Sai thiet bi";
    if ([status isEqualToString:@"DEVICE_BLOCKED"]) return @"Thiet bi bi ban";
    if ([status isEqualToString:@"BAD_RESPONSE_SIGNATURE"]) return @"Loi chu ky server";
    if ([status isEqualToString:@"BAD_CLIENT_SIGNATURE"]) return @"Loi chu ky client request";
    if ([status isEqualToString:@"REPLAY_REQUEST"]) return @"Yeu cau da bi lap lai";
    if ([status isEqualToString:@"RATE_LIMITED"]) return @"Qua nhieu yeu cau";
    if ([status isEqualToString:@"BAD_SIGNATURE"]) return @"Loi chu ky request";
    if ([status isEqualToString:@"PROFILE_NOT_INSTALLED"] ||
        [status isEqualToString:@"PROFILE_DOWNLOAD_REQUIRED"] ||
        [status isEqualToString:@"BAD_PROFILE_PAYLOAD"] ||
        [status hasPrefix:@"PROFILE_CALLBACK_"]) return @"Cai ho so chua thanh cong";
    if ([status isEqualToString:@"BAD_SESSION"] || [status isEqualToString:@"PROFILE_EXPIRED"] ||
        [status hasPrefix:@"PROFILE_CHALLENGE_"] || [status isEqualToString:@"PROFILE_UDID_MISSING"] ||
        [status isEqualToString:@"PROFILE_SESSION_NOT_CONFIRMABLE"]) return @"Can xac nhan lai";
    if ([status isEqualToString:@"APP_DISABLED"]) return @"Server dang tat";
    if ([status isEqualToString:@"STORE_DISABLED"]) return @"He thong dang tat";
    if ([status isEqualToString:@"PACKAGE_DISABLED"]) return @"Package dang tat";
    if ([status isEqualToString:@"PACKAGE_MAINTENANCE"]) return @"Package dang bao tri";
    if ([status isEqualToString:@"PACKAGE_BUNDLE_DENIED"]) return @"Sai ung dung";
    if ([status isEqualToString:@"BAD_PACKAGE_SESSION"]) return @"Phien package het han";
    if ([status isEqualToString:@"INVALID_API_KEY"]) return @"Package token khong hop le";
    if ([status isEqualToString:@"INVALID_CLIENT_API_KEY"]) return @"Client auth bi server tu choi";
    if ([status isEqualToString:@"CLIENT_KEY_UNAVAILABLE"]) return @"Client auth khong kha dung";
    if ([status isEqualToString:@"TRIAL_ALREADY_USED"]) return @"Da dung trial";
    if ([status isEqualToString:@"OFFLINE_GRACE_EXPIRED"]) return @"Het han offline";
    if ([status isEqualToString:@"REQUEST_VALIDATION_FAILED"]) return @"Du lieu khong hop le";
    if ([status isEqualToString:@"SERVER_ERROR"]) return @"Loi server";
    if ([status isEqualToString:@"NETWORK_ERROR"]) return @"Loi mang";
    if ([status isEqualToString:@"ACTIVATION_TIMEOUT"]) return @"Het thoi gian kich hoat";
    if ([status isEqualToString:@"ACTIVATION_CANCELLED"]) return @"Kich hoat da huy";
    if ([status isEqualToString:@"UNSAFE_ENVIRONMENT"]) return @"Moi truong khong an toan";
    if ([status isEqualToString:@"AUTHORIZATION_LEASE_INVALID"]) return @"Lease khong hop le";
    if ([status isEqualToString:@"CALLBACK_FAILURE"]) return @"Loi callback";
    if ([status isEqualToString:@"UI_FAILURE"]) return @"Loi hien thi";
    if ([status isEqualToString:@"TRANSPORT_SESSION_ERROR"]) return @"Loi phien bao mat";
    if ([status isEqualToString:@"UPDATE_REQUIRED"]) return @"Can cap nhat";
    if ([status isEqualToString:@"MAINTENANCE"]) return @"Bao tri";
    return @"Loi xac thuc";
}

- (NSString *)fallbackSubtitleForStatus:(NSString *)status {
    if ([status isEqualToString:@"LOADING"]) return @"Vui long doi trong giay lat...";
    if ([self isValidStatus:status]) return @"Xac nhan de vao menu.";
    if ([status isEqualToString:@"NEED_UUID"]) return @"Lien ket may nay voi license bang Device Verify an toan.";
    if ([status isEqualToString:@"NEED_KEY"]) return @"Nhap license key de kich hoat.";
    if ([status isEqualToString:@"INVALID_KEY"]) return @"Bạn đã nhập sai key";
    if ([status isEqualToString:@"EXPIRED"]) return @"Vui long nhap key moi de tiep tuc.";
    if ([status isEqualToString:@"REVOKED"]) return @"Key nay da bi ban / thu hoi. Lien he nguoi ban de duoc ho tro.";
    if ([status isEqualToString:@"DEVICE_MISMATCH"]) return @"Key nay da duoc lien ket voi thiet bi khac.";
    if ([status isEqualToString:@"DEVICE_BLOCKED"]) return @"Thiet bi nay da bi ban tren he thong.";
    if ([status isEqualToString:@"BAD_RESPONSE_SIGNATURE"]) return @"Server tra ve chu ky khong hop le.";
    if ([status isEqualToString:@"BAD_CLIENT_SIGNATURE"]) return @"Chu ky request client khong hop le. Kiem tra dong ho thiet bi va ban dylib hien tai.";
    if ([status isEqualToString:@"REPLAY_REQUEST"]) return @"Yeu cau bi lap lai. Vui long thu lai.";
    if ([status isEqualToString:@"RATE_LIMITED"]) return @"Qua nhieu yeu cau. Vui long doi it phut roi thu lai.";
    if ([status isEqualToString:@"BAD_SIGNATURE"]) return @"Chu ky request khong hop le.";
    if ([status isEqualToString:@"PROFILE_NOT_INSTALLED"] ||
        [status isEqualToString:@"PROFILE_DOWNLOAD_REQUIRED"] ||
        [status isEqualToString:@"BAD_PROFILE_PAYLOAD"] ||
        [status hasPrefix:@"PROFILE_CALLBACK_"]) {
        return @"Cai ho so that bai. Mo lai Safari, cai trong Cai dat > Ho so da tai, sau do quay lai app.";
    }
    if ([status isEqualToString:@"BAD_SESSION"] || [status isEqualToString:@"PROFILE_EXPIRED"]) return @"Phien xac nhan da het han, vui long lay UUID lai.";
    if ([status isEqualToString:@"APP_DISABLED"]) return @"Server key dang tam tat. Vui long thu lai sau.";
    if ([status isEqualToString:@"STORE_DISABLED"]) return @"Store/server hien dang tam tat.";
    if ([status isEqualToString:@"PACKAGE_DISABLED"]) return @"Package nay da bi tat boi chu package.";
    if ([status isEqualToString:@"PACKAGE_MAINTENANCE"]) return @"Package nay dang bao tri/update, vui long thu lai sau.";
    if ([status isEqualToString:@"PACKAGE_BUNDLE_DENIED"]) return @"Package nay khong duoc phep chay tren app hien tai.";
    if ([status isEqualToString:@"BAD_PACKAGE_SESSION"]) return @"Phien package da het han, vui long mo lai app.";
    if ([status isEqualToString:@"INVALID_API_KEY"]) return @"Package token khong hop le. Kiem tra token pkg_... trong dylib.";
    if ([status isEqualToString:@"INVALID_CLIENT_API_KEY"]) return @"Server tu choi client auth. Kiem tra SHA-256 cua dylib dang inject co dung ban da xac nhan.";
    if ([status isEqualToString:@"CLIENT_KEY_UNAVAILABLE"]) return @"Client auth khong kha dung trong process nay. Tat debugger, Frida, SSL-bypass va dung ban dylib da xac nhan.";
    if ([status isEqualToString:@"TRIAL_ALREADY_USED"]) return @"May nay da dung trial trong nhom nay.";
    if ([status isEqualToString:@"OFFLINE_GRACE_EXPIRED"]) return @"Cache license offline da het han.";
    if ([status isEqualToString:@"REQUEST_VALIDATION_FAILED"]) return @"Du lieu gui len server khong hop le.";
    if ([status isEqualToString:@"SERVER_ERROR"]) return @"Server dang loi, vui long thu lai.";
    if ([status isEqualToString:@"NETWORK_ERROR"]) return @"Loi mang. Vui long thu lai sau.";
    if ([status isEqualToString:@"ACTIVATION_TIMEOUT"]) return @"Khong nhan duoc ket qua kich hoat. Vui long thu lai.";
    if ([status isEqualToString:@"ACTIVATION_CANCELLED"]) return @"Lan kich hoat nay da bi huy.";
    if ([status isEqualToString:@"UNSAFE_ENVIRONMENT"]) return @"Moi truong chay khong an toan.";
    if ([status isEqualToString:@"AUTHORIZATION_LEASE_INVALID"]) return @"Authorization lease khong hop le. Kiem tra dong ho thiet bi / ban app moi.";
    if ([status isEqualToString:@"CALLBACK_FAILURE"]) return @"Callback bi tu choi hoac khong hop le.";
    if ([status isEqualToString:@"UI_FAILURE"]) return @"Khong the hien thi ket qua kich hoat.";
    if ([status isEqualToString:@"TRANSPORT_SESSION_ERROR"]) return @"Khong tao duoc phien bao mat voi server.";
    if ([status isEqualToString:@"UPDATE_REQUIRED"]) return @"Vui long cap nhat de tiep tuc.";
    if ([status isEqualToString:@"MAINTENANCE"]) return @"Server dang bao tri, vui long thu lai sau.";
    return @"Server tu choi request xac thuc.";
}

- (NSString *)fallbackButtonForStatus:(NSString *)status {
    if ([self isValidStatus:status]) return @"Tiep tuc";
    if ([status isEqualToString:@"NEED_UUID"]) return @"Lay UUID";
    if ([status isEqualToString:@"NEED_KEY"]) return @"Kich hoat";
    if ([status isEqualToString:@"INVALID_KEY"]) return @"Thu lai";
    if ([status isEqualToString:@"EXPIRED"]) return @"Nhap key moi";
    if ([status isEqualToString:@"REVOKED"]) return @"Nhap key khac";
    if ([status isEqualToString:@"DEVICE_MISMATCH"]) return @"Nhap key khac";
    if ([status isEqualToString:@"DEVICE_BLOCKED"]) return @"OK";
    if ([status isEqualToString:@"PROFILE_NOT_INSTALLED"] ||
        [status isEqualToString:@"PROFILE_DOWNLOAD_REQUIRED"] ||
        [status isEqualToString:@"BAD_PROFILE_PAYLOAD"] ||
        [status hasPrefix:@"PROFILE_CALLBACK_"]) return @"Mo lai Safari";
    if ([status isEqualToString:@"BAD_SESSION"] || [status isEqualToString:@"PROFILE_EXPIRED"]) return @"Lay UUID lai";
    if ([status isEqualToString:@"UPDATE_REQUIRED"]) return @"Cap nhat";
    if ([status isEqualToString:@"BAD_CLIENT_SIGNATURE"] || [status isEqualToString:@"REPLAY_REQUEST"] || [status isEqualToString:@"RATE_LIMITED"]) return @"Thu lai";
    if ([status isEqualToString:@"BAD_PACKAGE_SESSION"]) return @"Thu lai";
    if ([status isEqualToString:@"MAINTENANCE"] ||
        [status isEqualToString:@"APP_DISABLED"] ||
        [status isEqualToString:@"STORE_DISABLED"] ||
        [status isEqualToString:@"PACKAGE_DISABLED"] ||
        [status isEqualToString:@"PACKAGE_MAINTENANCE"] ||
        [status isEqualToString:@"PACKAGE_BUNDLE_DENIED"] ||
        [status isEqualToString:@"INVALID_API_KEY"] ||
        [status isEqualToString:@"INVALID_CLIENT_API_KEY"]) return @"OK";
    return @"Thu lai";
}

- (BOOL)isErrorStatus:(NSString *)status {
    if (status.length == 0) return YES;
    if ([status isEqualToString:@"LOADING"] || [self isValidStatus:status]) return NO;
    if ([status isEqualToString:@"NEED_UUID"] || [status isEqualToString:@"NEED_KEY"] || [status isEqualToString:@"INVALID_KEY"]) return NO;
    if ([status isEqualToString:@"EXPIRED"] || [status isEqualToString:@"REVOKED"] || [status isEqualToString:@"DEVICE_MISMATCH"]) return NO;
    if ([status isEqualToString:@"UPDATE_REQUIRED"] ||
        [status isEqualToString:@"MAINTENANCE"] ||
        [status isEqualToString:@"APP_DISABLED"] ||
        [status isEqualToString:@"STORE_DISABLED"] ||
        [status isEqualToString:@"PACKAGE_DISABLED"] ||
        [status isEqualToString:@"PACKAGE_MAINTENANCE"] ||
        [status isEqualToString:@"PACKAGE_BUNDLE_DENIED"] ||
        [status isEqualToString:@"BAD_PACKAGE_SESSION"] ||
        [status isEqualToString:@"INVALID_API_KEY"] ||
        [status isEqualToString:@"INVALID_CLIENT_API_KEY"]) return NO;
    return YES;
}

- (NSString *)formattedErrorForStatus:(NSString *)status message:(NSString *)message {
    return message.length > 0 ? message : [self fallbackSubtitleForStatus:status];
}

- (NSString *)string:(id)value fallback:(NSString *)fallback {
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : fallback;
}

- (void)needUUIDTapped {
    [TserverTemplateRegistry impactForAction:@"tap" config:self.config.rawConfig ?: @{}];
    if (self.needUUIDBlock) self.needUUIDBlock();
}

- (void)activateTapped {
    // Only strip accidental paste noise; the prefix is chosen per plan/package
    // so the SDK must not rewrite the key the customer typed.
    NSString *typed = [TserverKeyEntryAssist cleanedKeyText:self.keyField.text];
    if (![TserverKeyEntryAssist looksLikeLicenseKey:typed]) {
        // Surface the shared validation hint instead of stacking a new label on
        // every failed tap, and never hit the network with a broken key.
        [TserverKeyEntryAssist revealValidationHintForField:self.keyField];
        [TserverTemplateRegistry impactForAction:@"error" config:self.config.rawConfig ?: @{}];
        return;
    }
    NSString *key = typed.uppercaseString;
    [TserverTemplateRegistry impactForAction:@"tap" config:self.config.rawConfig ?: @{}];
    if (self.activateBlock) self.activateBlock(key);
}

- (void)retryTapped {
    [TserverTemplateRegistry impactForAction:@"tap" config:self.config.rawConfig ?: @{}];
    if (self.retryBlock) self.retryBlock();
}

- (void)closeAndTerminateTapped {
    [TserverTemplateRegistry impactForAction:@"tap" config:self.config.rawConfig ?: @{}];
    TserverGateTerminateApp();
}
- (void)showNeedKeyTapped {
    [TserverTemplateRegistry impactForAction:@"tap" config:self.config.rawConfig ?: @{}];
    if (self.showNeedKeyBlock) self.showNeedKeyBlock();
}
- (void)continueTapped {
    if (self.continueSubmitted) return;
    self.continueSubmitted = YES;
    [TserverTemplateRegistry impactForAction:@"success" config:self.config.rawConfig ?: @{}];
    self.userInteractionEnabled = NO;
    if (self.continueBlock) self.continueBlock();
}

/// Resolve continue UX for VALID screen.
/// Priority: screens.valid.continueMode → screens.valid.showButton → flow.validAction → default "button"
- (NSString *)validContinueModeForScreen:(NSDictionary *)screen {
    NSString *mode = [self string:screen[@"continueMode"] fallback:@""];
    if (mode.length == 0) mode = [self string:screen[@"validContinueMode"] fallback:@""];
    if (mode.length == 0) {
        id showButton = screen[@"showButton"];
        if ([showButton respondsToSelector:@selector(boolValue)] && ![showButton boolValue]) {
            mode = @"anywhere";
        } else {
            NSString *buttonText = [self string:screen[@"buttonText"] fallback:@"__unset__"];
            // Explicit empty buttonText means hide button and allow tap anywhere
            if ([buttonText isEqualToString:@""]) mode = @"anywhere";
        }
    }
    if (mode.length == 0) {
        mode = [self.config flowStringForKey:@"validAction" fallback:@"button"];
    }
    mode = TserverGateNormalizedValidContinueMode(mode);
    return mode;
}

- (void)openUpdateTapped {
    UIButton *button = (UIButton *)[self findSenderInView:self];
    NSURL *url = [NSURL URLWithString:button.accessibilityValue ?: @""];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (UIView *)findSenderInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UIButton.class] && ((UIButton *)subview).accessibilityValue.length > 0) return subview;
        UIView *found = [self findSenderInView:subview];
        if (found) return found;
    }
    return nil;
}

@end
