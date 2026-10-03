#import "TserverSimpleUiPack.h"
#import "TserverTemplateRegistry.h"
#import "TserverKeyEntryAssist.h"
#import "TserverTemplateCatalog.gen.mm"
#import "TserverGateUI.h"

@implementation TserverSimpleUiContext
@end

id<TserverSimpleUiPack> TserverSimpleUiPackCreateForRenderer(NSString *rendererId) {
    if (![rendererId isKindOfClass:NSString.class] || rendererId.length == 0) return nil;
    _TserverKeepPackClassesLive();

    Class cls = _TserverResolvedClassForRendererId(rendererId);
    if (!cls || ![cls conformsToProtocol:@protocol(TserverSimpleUiPack)]) return nil;
    return [[cls alloc] init];
}

// Force-load anchor used by host apps/tweaks linking libAPIClient.a.
void TserverForceLoadNativeUiPacks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _TserverForceLoadAllPacksOnce();
    });
}

@interface TserverSimpleUiPackBase ()
@property(nonatomic, strong, readwrite) UIView *root;
@property(nonatomic, strong, readwrite) UIView *content;
@property(nonatomic, strong, readwrite) UIStackView *stack;
@property(nonatomic, strong, nullable) UIScrollView *contentScroll;
@property(nonatomic, assign) BOOL shellInstalled;
@property(nonatomic, assign) BOOL didPlayEnterMotion;
@property(nonatomic, strong, nullable) UIButton *keyPasteButton;
@property(nonatomic, strong, nullable) UILabel *keyHintLabel;
@end

@implementation TserverSimpleUiPackBase

#pragma mark - Lifecycle

- (UIView *)makeViewWithContext:(TserverSimpleUiContext *)context {
    self.context = context;
    self.root = [UIView new];
    self.root.backgroundColor = UIColor.blackColor;
    self.root.accessibilityViewIsModal = YES;
    self.root.userInteractionEnabled = YES; // Blocking overlay owns all touches before auth completes.
    self.shellInstalled = NO;
    self.didPlayEnterMotion = NO;
    [self installShell];
    if (!self.shellInstalled) [self installCenteredCardShell];
    [self buildBackground];
    // Popup overlays are intentionally disabled system-wide.
    // The gate itself remains the single authorization surface.
    // Popup overlays are intentionally disabled system-wide.
    // Do not pre-build hero/HUD here — renderContext clears the stack and rebuilds
    // for the active status. Building twice left stale/empty lines under racey updates.
    [self renderContext:context];
    [self playEnterMotion];
    return self.root;
}

/// Packs may override to pick fullscreen/card/custom shell before defaults run.
- (void)installShell {
    [self installCenteredCardShell];
}

- (void)renderContext:(TserverSimpleUiContext *)context {
    self.context = context;
    self.keyField = nil;
    // No popup overlay is created or retained.
    // Cancel in-flight content animations so a new status cannot leave alpha=0 / half-typed lines.
    [self.content.layer removeAllAnimations];
    self.content.alpha = 1;
    self.content.transform = CGAffineTransformIdentity;
    for (UIView *view in self.stack.arrangedSubviews.copy) {
        [self.stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (UIGestureRecognizer *gesture in self.root.gestureRecognizers.copy) {
        if ([gesture isKindOfClass:UITapGestureRecognizer.class]) [self.root removeGestureRecognizer:gesture];
    }
    NSString *status = context.status ?: @"";
    if ([status isEqualToString:@"NOTICE"]) {
        // An announcement is a modal message, not an authorization screen. Keep
        // the pack's background/shell but skip hero and HUD decorations so the
        // operator content stays readable.
        [self buildNoticeArea];
        [self playStatusMotion];
        return;
    }
    self.keyPasteButton = nil;
    self.keyHintLabel = nil;
    [self buildHero];
    if ([status isEqualToString:@"LOADING"]) {
        [self buildResultArea];
    } else if ([status isEqualToString:@"NEED_KEY"] || [status isEqualToString:@"INVALID_KEY"]) {
        [self buildKeyArea];
    } else if ([status isEqualToString:@"NEED_UUID"]) {
        [self buildUuidArea];
    } else {
        [self buildResultArea];
    }
    [self buildHud];
    [self playStatusMotion];
}

#pragma mark - Shells

- (BOOL)isLandscapeConfig {
    NSString *orientation = [self.context.config[@"orientation"] isKindOfClass:NSString.class]
        ? [self.context.config[@"orientation"] lowercaseString]
        : @"portrait";
    return [orientation isEqualToString:@"landscape"] || [orientation isEqualToString:@"horizontal"] || [orientation isEqualToString:@"ngang"];
}

- (BOOL)isCompactLandscape {
    CGRect bounds = UIScreen.mainScreen.bounds;
    BOOL wideScreen = bounds.size.width > bounds.size.height;
    return [self isLandscapeConfig] || wideScreen;
}

- (CGFloat)geometryNumber:(NSString *)key fallback:(CGFloat)fallback {
    NSDictionary *geometry = [self.context.config[@"geometry"] isKindOfClass:NSDictionary.class] ? self.context.config[@"geometry"] : @{};
    id value = geometry[key ?: @""];
    if ([value respondsToSelector:@selector(doubleValue)]) return (CGFloat)[value doubleValue];
    return fallback;
}

- (void)installCenteredCardShell {
    if (self.shellInstalled) return;
    self.shellInstalled = YES;
    BOOL landscape = [self isCompactLandscape];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    // Medium centered panel. Do NOT host the stack inside a height-capped UIScrollView:
    // that pattern collapsed the card to a thin accent bar (no intrinsic height path).
    CGFloat insetFallback = landscape ? MAX(36.0, screenW * 0.12) : 16.0;
    CGFloat maxFallback = landscape ? MIN(420.0, screenW * 0.56) : 440.0;
    CGFloat minFallback = landscape ? 300.0 : 280.0;
    CGFloat inset = [self geometryNumber:@"horizontalInset" fallback:insetFallback];
    CGFloat maxWidth = [self geometryNumber:@"maxCardWidth" fallback:maxFallback];
    CGFloat minWidth = [self geometryNumber:@"minCardWidth" fallback:minFallback];
    // Soft height cap only in landscape; 0 disables. Never use scroll+maxHeight together.
    CGFloat maxHeightFallback = landscape ? MIN(300.0, screenH - 24.0) : 0.0;
    CGFloat maxHeight = [self geometryNumber:@"maxCardHeight" fallback:maxHeightFallback];
    if (!landscape) maxHeight = 0.0; // portrait must size to content
    if (maxWidth < minWidth) maxWidth = minWidth;
    CGFloat stackPadX = landscape ? 16.0 : 20.0;
    CGFloat stackPadY = landscape ? 12.0 : 22.0;

    self.content = [UIView new];
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    self.content.layer.cornerRadius = landscape ? 14 : 22;
    self.content.clipsToBounds = YES;
    self.content.alpha = 1;
    [self.root addSubview:self.content];
    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = landscape ? 8 : 12;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentScroll = nil;
    [self.content addSubview:self.stack];

    NSMutableArray<NSLayoutConstraint *> *constraints = [@[
        [self.content.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.root.safeAreaLayoutGuide.leadingAnchor constant:inset],
        [self.content.trailingAnchor constraintLessThanOrEqualToAnchor:self.root.safeAreaLayoutGuide.trailingAnchor constant:-inset],
        [self.content.centerXAnchor constraintEqualToAnchor:self.root.safeAreaLayoutGuide.centerXAnchor],
        [self.content.centerYAnchor constraintEqualToAnchor:self.root.safeAreaLayoutGuide.centerYAnchor],
        [self.content.topAnchor constraintGreaterThanOrEqualToAnchor:self.root.safeAreaLayoutGuide.topAnchor constant:8],
        [self.content.bottomAnchor constraintLessThanOrEqualToAnchor:self.root.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [self.content.widthAnchor constraintLessThanOrEqualToConstant:maxWidth],
        [self.content.widthAnchor constraintGreaterThanOrEqualToConstant:minWidth],
        [self.stack.topAnchor constraintEqualToAnchor:self.content.topAnchor constant:stackPadY],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor constant:stackPadX],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-stackPadX],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor constant:-stackPadY]
    ] mutableCopy];
    if (maxHeight > 0.0) {
        // Soft cap — must not fight the stack-driven intrinsic height into a zero-height card.
        NSLayoutConstraint *heightCap = [self.content.heightAnchor constraintLessThanOrEqualToConstant:maxHeight];
        heightCap.priority = UILayoutPriorityDefaultHigh; // 750
        [constraints addObject:heightCap];
    }
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)installFullscreenShell {
    if (self.shellInstalled) return;
    self.shellInstalled = YES;
    self.content = [UIView new];
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    self.content.layer.cornerRadius = 0;
    self.content.clipsToBounds = YES;
    [self.root addSubview:self.content];
    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 14;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.content addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.content.topAnchor constraintEqualToAnchor:self.root.topAnchor],
        [self.content.leadingAnchor constraintEqualToAnchor:self.root.leadingAnchor],
        [self.content.trailingAnchor constraintEqualToAnchor:self.root.trailingAnchor],
        [self.content.bottomAnchor constraintEqualToAnchor:self.root.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.content.safeAreaLayoutGuide.topAnchor constant:20],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.content.safeAreaLayoutGuide.leadingAnchor constant:20],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.content.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [self.stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.content.safeAreaLayoutGuide.bottomAnchor constant:-20]
    ]];
}

#pragma mark - Config helpers

- (NSString *)screenNameForStatus:(NSString *)status {
    if ([status isEqualToString:@"NOTICE"]) return @"notice";
    if ([status isEqualToString:@"LOADING"]) return @"loading";
    if ([status isEqualToString:@"NEED_UUID"]) return @"needUuid";
    if ([status isEqualToString:@"NEED_KEY"] || [status isEqualToString:@"INVALID_KEY"]) return @"needKey";
    if ([status hasPrefix:@"VALID"] || [status isEqualToString:@"OFFLINE_GRACE_VALID"]) return @"valid";
    if ([status isEqualToString:@"EXPIRED"] || [status isEqualToString:@"OFFLINE_GRACE_EXPIRED"]) return @"expired";
    if ([status isEqualToString:@"REVOKED"]) return @"revoked";
    if ([status isEqualToString:@"DEVICE_MISMATCH"]) return @"deviceMismatch";
    if ([status isEqualToString:@"DEVICE_BLOCKED"]) return @"deviceBlocked";
    if ([status isEqualToString:@"NETWORK_ERROR"] || [status isEqualToString:@"BAD_CLIENT_SIGNATURE"] ||
        [status isEqualToString:@"REPLAY_REQUEST"] || [status isEqualToString:@"RATE_LIMITED"] ||
        [status isEqualToString:@"BAD_RESPONSE_SIGNATURE"] || [status isEqualToString:@"BAD_SIGNATURE"]) return @"networkError";
    if ([status isEqualToString:@"SERVER_ERROR"] || [status isEqualToString:@"AUTHORIZATION_LEASE_INVALID"]) return @"serverError";
    if ([status isEqualToString:@"UPDATE_REQUIRED"]) return @"updateRequired";
    if ([status isEqualToString:@"MAINTENANCE"]) return @"maintenance";
    if ([status isEqualToString:@"APP_DISABLED"]) return @"appDisabled";
    if ([status isEqualToString:@"STORE_DISABLED"]) return @"storeDisabled";
    if ([status isEqualToString:@"PACKAGE_DISABLED"]) return @"packageDisabled";
    if ([status isEqualToString:@"PACKAGE_MAINTENANCE"]) return @"packageMaintenance";
    if ([status isEqualToString:@"PACKAGE_BUNDLE_DENIED"]) return @"packageBundleDenied";
    if ([status isEqualToString:@"BAD_PACKAGE_SESSION"]) return @"badPackageSession";
    if ([status isEqualToString:@"INVALID_API_KEY"] || [status isEqualToString:@"INVALID_CLIENT_API_KEY"] ||
        [status isEqualToString:@"CLIENT_KEY_UNAVAILABLE"]) return @"invalidApiKey";
    return @"networkError";
}

- (NSDictionary *)currentScreenConfig {
    NSDictionary *screens = [self.context.config[@"screens"] isKindOfClass:NSDictionary.class] ? self.context.config[@"screens"] : @{};
    NSString *name = [self screenNameForStatus:self.context.status ?: @""];
    NSDictionary *screen = [screens[name] isKindOfClass:NSDictionary.class] ? screens[name] : @{};
    return screen;
}

- (NSString *)screenString:(NSString *)key fallback:(NSString *)fallback {
    id value = [self currentScreenConfig][key];
    if ([value isKindOfClass:NSString.class] && [((NSString *)value) length] > 0) return (NSString *)value;
    return fallback ?: @"";
}

- (UIColor *)colorFromHex:(NSString *)hex fallback:(UIColor *)fallback {
    if (![hex isKindOfClass:NSString.class] || hex.length < 7) return fallback;
    NSString *clean = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length != 6 && clean.length != 8) return fallback;
    unsigned int value = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&value];
    CGFloat a = 1.0, r = 0, g = 0, b = 0;
    if (clean.length == 8) {
        a = ((value >> 24) & 0xFF) / 255.0;
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

- (UIColor *)styleColor:(NSString *)key fallback:(UIColor *)fallback {
    NSDictionary *style = [self.context.config[@"style"] isKindOfClass:NSDictionary.class] ? self.context.config[@"style"] : @{};
    id raw = style[key];
    if ([raw isKindOfClass:NSString.class]) return [self colorFromHex:(NSString *)raw fallback:fallback];
    return fallback;
}

- (UIColor *)accentColor { return [self styleColor:@"accent" fallback:[UIColor colorWithRed:0.49 green:0.23 blue:0.93 alpha:1]]; }
- (UIColor *)textColor { return [self styleColor:@"text" fallback:UIColor.whiteColor]; }
- (UIColor *)mutedTextColor { return [self styleColor:@"mutedText" fallback:[UIColor colorWithWhite:0.75 alpha:1]]; }
- (UIColor *)cardColor { return [self styleColor:@"card" fallback:[UIColor colorWithWhite:0.1 alpha:1]]; }
- (UIColor *)dangerColor { return [self styleColor:@"danger" fallback:[UIColor colorWithRed:1 green:0.38 blue:0.48 alpha:1]]; }
- (UIColor *)successColor { return [self styleColor:@"success" fallback:[UIColor colorWithRed:0.31 green:1 blue:0.72 alpha:1]]; }

- (TserverUiContinueMode)resolvedContinueMode {
    NSString *fromScreen = [self screenString:@"continueMode" fallback:@""];
    NSDictionary *flow = [self.context.config[@"flow"] isKindOfClass:NSDictionary.class] ? self.context.config[@"flow"] : @{};
    NSString *fromFlow = [flow[@"validAction"] isKindOfClass:NSString.class] ? flow[@"validAction"] : @"";
    // "auto" is retired: a self-dismissing VALID screen would hide the license
    // details the moment they were granted.
    NSString *mode = TserverGateNormalizedValidContinueMode(fromScreen.length ? fromScreen : (fromFlow.length ? fromFlow : @"button"));
    return [mode isEqualToString:@"anywhere"] ? TserverUiContinueModeOverlayTap : TserverUiContinueModeButton;
}

#pragma mark - Widgets

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.text = text ?: @"";
    label.textColor = [self textColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title ?: @"OK" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    button.backgroundColor = [self accentColor];
    button.layer.cornerRadius = 12;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 18, 12, 18);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark - Sections

- (void)buildBackground { self.content.backgroundColor = [self cardColor]; }
- (void)buildHero {}
- (void)buildKeyArea { [self buildDefaultKeyArea]; }
- (void)buildUuidArea { [self buildDefaultUuidArea]; }
- (void)buildResultArea { [self buildDefaultResultArea]; }
- (void)buildNoticeArea { [self buildDefaultNoticeArea]; }
- (void)buildHud {}

- (void)buildDefaultKeyArea {
    NSString *title = [self screenString:@"title" fallback:@"Nhập key"];
    NSString *subtitle = [self screenString:@"subtitle" fallback:(self.context.result[@"message"] ?: @"Nhập key để tiếp tục")];
    NSString *placeholder = [self screenString:@"placeholder" fallback:@"TSRV-XXXX-XXXX"];
    NSString *buttonText = [self screenString:@"buttonText" fallback:@"Kích hoạt"];

    UILabel *titleLabel = [self label:title size:18 weight:UIFontWeightBold];
    UILabel *subtitleLabel = [self label:subtitle size:14 weight:UIFontWeightRegular];
    subtitleLabel.textColor = [self mutedTextColor];
    [self.stack addArrangedSubview:titleLabel];
    [self.stack addArrangedSubview:subtitleLabel];

    self.keyField = [UITextField new];
    self.keyField.placeholder = placeholder;
    self.keyField.textAlignment = NSTextAlignmentCenter;
    self.keyField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.keyField.backgroundColor = [UIColor colorWithWhite:0 alpha:0.24];
    self.keyField.textColor = [self textColor];
    self.keyField.layer.cornerRadius = 12;
    self.keyField.layer.borderWidth = 1;
    self.keyField.layer.borderColor = [[self accentColor] colorWithAlphaComponent:0.35].CGColor;
    self.keyField.accessibilityLabel = @"Mã license";
    self.keyField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    self.keyField.leftViewMode = UITextFieldViewModeAlways;
    [self.keyField.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.stack addArrangedSubview:self.keyField];

    // Smart entry: offer the clipboard when it holds a key, and show a live
    // shape hint. The key body is never reformatted because the prefix belongs
    // to the member's plan.
    self.keyPasteButton = nil;
    self.keyHintLabel = nil;
    UIButton *pasteButton = [self button:@"Dán từ clipboard" action:@selector(pasteKeyFromClipboardTapped)];
    pasteButton.backgroundColor = [[self accentColor] colorWithAlphaComponent:0.18];
    [pasteButton setTitleColor:[self textColor] forState:UIControlStateNormal];
    pasteButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    pasteButton.layer.cornerRadius = 10;
    [TserverKeyEntryAssist bindPasteButton:pasteButton toField:self.keyField];
    [self.stack addArrangedSubview:pasteButton];
    self.keyPasteButton = pasteButton;

    UILabel *hint = [self label:@"" size:12 weight:UIFontWeightMedium];
    hint.textColor = [self styleColor:@"warningText" fallback:[self dangerColor]];
    hint.numberOfLines = 0;
    [TserverKeyEntryAssist bindHintLabel:hint toField:self.keyField];
    [self.stack addArrangedSubview:hint];
    self.keyHintLabel = hint;

    [self.stack addArrangedSubview:[self button:buttonText action:@selector(submitKeyTapped)]];
}

- (void)buildDefaultUuidArea {
    NSString *title = [self screenString:@"title" fallback:@"Xác minh thiết bị"];
    NSString *subtitle = [self screenString:@"subtitle" fallback:@"Xác minh thiết bị để tiếp tục"];
    NSString *buttonText = [self screenString:@"buttonText" fallback:@"Lấy UUID"];
    UILabel *titleLabel = [self label:title size:18 weight:UIFontWeightBold];
    UILabel *subtitleLabel = [self label:subtitle size:14 weight:UIFontWeightRegular];
    subtitleLabel.textColor = [self mutedTextColor];
    [self.stack addArrangedSubview:titleLabel];
    [self.stack addArrangedSubview:subtitleLabel];
    [self.stack addArrangedSubview:[self button:buttonText action:@selector(uuidTapped)]];
}

- (void)buildDefaultResultArea {
    BOOL valid = [self.context.status hasPrefix:@"VALID"] || [self.context.status isEqualToString:@"OFFLINE_GRACE_VALID"];
    BOOL loading = [self.context.status isEqualToString:@"LOADING"];
    BOOL updateRequired = [self.context.status isEqualToString:@"UPDATE_REQUIRED"];
    NSString *updateUrl = [self.context.result[@"updateUrl"] isKindOfClass:NSString.class] ? self.context.result[@"updateUrl"] : nil;
    NSString *fallbackTitle = loading ? @"Đang kiểm tra" : (valid ? @"Key hợp lệ" : (updateRequired ? @"Cần cập nhật" : @"Không thể tiếp tục"));
    NSString *message = [self.context.result[@"message"] isKindOfClass:NSString.class] ? self.context.result[@"message"] : nil;
    NSString *title = [self screenString:@"title" fallback:fallbackTitle];
    // Prefer live server message (e.g. custom PACKAGE_MAINTENANCE text) over pack defaults.
    NSString *subtitle = (message.length > 0)
        ? message
        : [self screenString:@"subtitle" fallback:(loading ? @"Vui lòng chờ…" : (updateRequired ? @"Vui lòng cập nhật để tiếp tục." : @"Đang xử lý xác thực…"))];
    NSString *buttonText = [self screenString:@"buttonText" fallback:(valid ? @"Tiếp tục" : (updateRequired ? @"Cập nhật" : @"Thử lại"))];
    NSString *tapHint = [self screenString:@"tapHint" fallback:@"Chạm để tiếp tục"];
    // A missing URL scheme is a build defect, not an auth outcome: name it, and
    // replace whatever retry/change-key copy the pack picked with a Close.
    BOOL fatalConfigError = TserverGateResultIsFatalConfigError(self.context.result);
    if (fatalConfigError) {
        title = [self screenString:@"title" fallback:@"Cấu hình app chưa đúng"];
        buttonText = [self screenString:@"closeButtonText" fallback:TserverGateFatalConfigCloseButtonTitle()];
    }

    UILabel *titleLabel = [self label:title size:18 weight:UIFontWeightBold];
    titleLabel.textColor = valid ? [self successColor] : (loading ? [self textColor] : [self dangerColor]);
    UILabel *subtitleLabel = [self label:subtitle size:14 weight:UIFontWeightRegular];
    subtitleLabel.textColor = [self mutedTextColor];
    [self.stack addArrangedSubview:titleLabel];
    [self.stack addArrangedSubview:subtitleLabel];

    TserverUiContinueMode mode = [self resolvedContinueMode];
    if (valid) {
        // Report what was authorized before asking the user to continue.
        NSDictionary *licenseInfo = TserverGateLicenseInfoFromResult(self.context.result);
        if (licenseInfo.count > 0) {
            [self.stack addArrangedSubview:TserverGateLicenseInfoView(licenseInfo,
                                                                      [self textColor],
                                                                      [self mutedTextColor],
                                                                      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold])];
        }
        if (mode == TserverUiContinueModeButton) {
            [self.stack addArrangedSubview:[self button:buttonText action:@selector(continueFromOverlay)]];
        } else {
            UILabel *hint = [self label:tapHint size:12 weight:UIFontWeightMedium];
            hint.textColor = [self mutedTextColor];
            [self.stack addArrangedSubview:hint];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(continueFromOverlay)];
            [self.root addGestureRecognizer:tap];
        }
    } else if (updateRequired) {
        UIButton *button = [self button:buttonText action:@selector(openUpdateTapped:)];
        if (updateUrl.length > 0) button.accessibilityValue = updateUrl;
        [self.stack addArrangedSubview:button];
    } else if (fatalConfigError) {
        // Single Close button that quits. No retry, no key entry: this app can
        // never complete Device Verify, so any other action is a dead end.
        [self.stack addArrangedSubview:[self button:buttonText action:@selector(closeAndTerminateTapped)]];
    } else if (!loading) {
        SEL action = (self.context.showNeedKey || !self.context.retry) ? @selector(changeKeyTapped) : @selector(retryTapped);
        NSString *fallbackActionTitle = self.context.showNeedKey ? @"Đổi key khác" : @"Thử lại";
        NSString *actionTitle = (buttonText.length > 0 && ![buttonText isEqualToString:@"Thử lại"]) ? buttonText : fallbackActionTitle;
        [self.stack addArrangedSubview:[self button:actionTitle action:action]];
        UILabel *hint = [self label:[self screenString:@"tapHint" fallback:@"Chạm vào màn hình để đổi key"] size:12 weight:UIFontWeightMedium];
        hint.textColor = [self mutedTextColor];
        [self.stack addArrangedSubview:hint];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:action];
        [self.root addGestureRecognizer:tap];
    }
}

#pragma mark - Package announcement (ALL_SDK_UI)

- (void)buildDefaultNoticeArea {
    NSDictionary *result = self.context.result ?: @{};
    NSString *title = [result[@"noticeTitle"] isKindOfClass:NSString.class] ? result[@"noticeTitle"] : @"Thông báo";
    NSString *message = [result[@"noticeMessage"] isKindOfClass:NSString.class] ? result[@"noticeMessage"] : @"";
    NSString *type = [result[@"noticeType"] isKindOfClass:NSString.class] ? result[@"noticeType"] : @"info";

    // Operator copy always wins. A template may only override button labels from
    // its own `notice` screen, so unrelated screen copy (for example the network
    // error title) can never leak into an announcement.
    NSString *resolvedTitle = [self screenString:@"title" fallback:title];
    if (resolvedTitle.length == 0) resolvedTitle = title.length > 0 ? title : @"Thông báo";
    NSString *resolvedMessage = message.length > 0 ? message : [self screenString:@"subtitle" fallback:@""];
    NSString *closeText = [self screenString:@"closeButtonText" fallback:@"Đóng"];
    NSString *snoozeText = [self screenString:@"snoozeButtonText" fallback:@"Đóng trong 3 giờ"];

    UILabel *titleLabel = [self label:resolvedTitle size:18 weight:UIFontWeightBold];
    titleLabel.numberOfLines = 0;
    if ([type isEqualToString:@"danger"]) {
        titleLabel.textColor = [self dangerColor];
    } else if ([type isEqualToString:@"success"]) {
        titleLabel.textColor = [self successColor];
    } else if ([type isEqualToString:@"warning"]) {
        titleLabel.textColor = [self styleColor:@"warningText" fallback:[self accentColor]];
    } else {
        titleLabel.textColor = [self textColor];
    }
    [self.stack addArrangedSubview:titleLabel];

    if (resolvedMessage.length > 0) {
        UILabel *messageLabel = [self label:resolvedMessage size:14 weight:UIFontWeightRegular];
        messageLabel.numberOfLines = 0;
        messageLabel.textColor = [self mutedTextColor];
        [self.stack addArrangedSubview:messageLabel];
    }

    // Primary action stays visually dominant; snooze is the quiet secondary.
    UIButton *snoozeButton = [self button:snoozeText action:@selector(noticeSnoozeTapped)];
    snoozeButton.backgroundColor = [[self accentColor] colorWithAlphaComponent:0.18];
    [snoozeButton setTitleColor:[self textColor] forState:UIControlStateNormal];
    snoozeButton.layer.cornerRadius = 10;
    snoozeButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.stack addArrangedSubview:snoozeButton];
    [self.stack addArrangedSubview:[self button:closeText action:@selector(noticeCloseTapped)]];
    [self playHaptic:@"tap"];
}

- (void)noticeCloseTapped {
    dispatch_block_t handler = self.context.noticeClose;
    if (handler) handler();
}

- (void)noticeSnoozeTapped {
    dispatch_block_t handler = self.context.noticeSnooze;
    if (handler) handler();
}

#pragma mark - Motion / actions

- (void)playEnterMotion {
    if (self.didPlayEnterMotion) {
        self.content.alpha = 1;
        self.content.transform = CGAffineTransformIdentity;
        return;
    }
    self.didPlayEnterMotion = YES;
    if ([TserverTemplateRegistry reduceMotionEnabled] || !self.content) {
        self.content.alpha = 1;
        return;
    }
    [self.content.layer removeAllAnimations];
    self.content.alpha = 0.02; // never leave fully invisible if animation is interrupted
    self.content.transform = CGAffineTransformMakeScale(0.985, 0.985);
    [UIView animateWithDuration:0.22
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.content.alpha = 1;
        self.content.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.content.alpha = 1;
        self.content.transform = CGAffineTransformIdentity;
    }];
}

- (void)playStatusMotion {
    if ([TserverTemplateRegistry reduceMotionEnabled] || !self.content) return;
    // Status updates happen often; avoid alpha fades that can stick at 0 under interruption.
    [self.content.layer removeAllAnimations];
    self.content.alpha = 1;
    self.content.transform = CGAffineTransformMakeScale(0.985, 0.985);
    [UIView animateWithDuration:0.16
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.content.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.content.alpha = 1;
        self.content.transform = CGAffineTransformIdentity;
    }];
}

- (void)playHaptic:(NSString *)event {
    [TserverTemplateRegistry impactForAction:event config:self.context.config ?: @{}];
}

- (void)pasteKeyFromClipboardTapped {
    // TserverKeyEntryAssist owns the clipboard read; the retained button carries
    // the field binding, so simply forward the tap to it.
    [self.keyPasteButton sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (void)submitKeyTapped {
    if (![TserverKeyEntryAssist looksLikeLicenseKey:self.keyField.text]) {
        // Surface the same hint the live validation uses instead of stacking a
        // new label on every failed tap.
        [TserverKeyEntryAssist revealValidationHintForField:self.keyField];
        [self playHaptic:@"error"];
        return;
    }
    if (self.keyHintLabel) self.keyHintLabel.hidden = YES;
    [self playHaptic:@"tap"];
    NSString *key = [[self.keyField.text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if (self.context.submitKey) self.context.submitKey(key);
}

- (void)uuidTapped {
    [self playHaptic:@"tap"];
    if (self.context.startUuid) self.context.startUuid();
}

- (void)retryTapped {
    [self playHaptic:@"tap"];
    if (self.context.retry) self.context.retry();
}

- (void)changeKeyTapped {
    [self playHaptic:@"tap"];
    if (self.context.showNeedKey) {
        self.context.showNeedKey();
    } else if (self.context.retry) {
        self.context.retry();
    }
}

- (void)closeAndTerminateTapped {
    [self playHaptic:@"tap"];
    TserverGateTerminateApp();
}

- (void)openUpdateTapped:(UIButton *)sender {
    [self playHaptic:@"tap"];
    NSString *raw = sender.accessibilityValue.length > 0
        ? sender.accessibilityValue
        : ([self.context.result[@"updateUrl"] isKindOfClass:NSString.class] ? self.context.result[@"updateUrl"] : nil);
    NSURL *url = raw.length > 0 ? [NSURL URLWithString:raw] : nil;
    if (!url || !url.scheme.length) return;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)continueFromOverlay {
    [self playHaptic:@"success"];
    if (self.context.continueAuth) self.context.continueAuth();
}

@end
