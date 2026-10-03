#import "TserverSimpleUiPack.h"
#import "TserverTemplateRegistry.h"
#import "CyberTerminalPrivate.h"
#import <objc/runtime.h>

// CYBER TERMINAL / PACK SHELL
// Hacker terminal chrome: monospace stream, typed commands, scanline, cursor.

void TserverCyberTerminalBuildLoading(TserverSimpleUiPackBase *pack);
void TserverCyberTerminalBuildKeyEntry(TserverSimpleUiPackBase *pack);
void TserverCyberTerminalBuildDeviceVerify(TserverSimpleUiPackBase *pack);
void TserverCyberTerminalBuildResult(TserverSimpleUiPackBase *pack);

static char kTCTStreamTokenKey;
static char kTCTCursorTimerKey;
static char kTCTScanlineKey;

UIFont *TCTFont(CGFloat size) {
    UIFont *mono = [UIFont fontWithName:@"Menlo-Bold" size:size] ?: [UIFont fontWithName:@"CourierNewPS-BoldMT" size:size];
    if (!mono) {
        // Avoid @available (needs ___isOSVersionAtLeast in consumer link).
        if ([UIFont respondsToSelector:@selector(monospacedSystemFontOfSize:weight:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
            mono = [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightBold];
#pragma clang diagnostic pop
        } else {
            mono = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
        }
    }
    return mono;
}

UILabel *TCTLine(TserverSimpleUiPackBase *pack, NSString *text, UIColor *color, CGFloat size) {
    UILabel *label = [pack label:text ?: @"" size:size weight:UIFontWeightBold];
    label.font = TCTFont(size);
    label.textAlignment = NSTextAlignmentLeft;
    label.textColor = color ?: [pack accentColor];
    label.numberOfLines = 0;
    return label;
}

void TCTAppendLine(TserverSimpleUiPackBase *pack, NSString *text, UIColor *color) {
    [pack.stack addArrangedSubview:TCTLine(pack, text, color, 11)];
}

void TCTTypeLines(TserverSimpleUiPackBase *pack, NSArray<NSString *> *lines, NSArray<UIColor *> *colors, NSTimeInterval gap) {
    if (![pack isKindOfClass:TserverSimpleUiPackBase.class] || lines.count == 0) return;
    // Typing animation can leave blank labels if a status change cancels mid-stream.
    // Landscape / Reduce Motion always render instantly so key/result text never vanishes.
    BOOL reduce = [TserverTemplateRegistry reduceMotionEnabled] || [pack isCompactLandscape];
    NSNumber *tokenNumber = objc_getAssociatedObject(pack, &kTCTStreamTokenKey);
    NSInteger token = tokenNumber.integerValue + 1;
    objc_setAssociatedObject(pack, &kTCTStreamTokenKey, @(token), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (reduce) {
        for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
            UIColor *color = (i < (NSInteger)colors.count) ? colors[i] : [pack accentColor];
            TCTAppendLine(pack, lines[i], color);
        }
        return;
    }

    __weak TserverSimpleUiPackBase *weakPack = pack;
    __block NSInteger index = 0;
    __block void (^typeNext)(void);
    __block void (^typeNextWeak)(void) = nil;
    typeNext = ^{
        TserverSimpleUiPackBase *strongPack = weakPack;
        if (!strongPack) return;
        NSInteger current = [objc_getAssociatedObject(strongPack, &kTCTStreamTokenKey) integerValue];
        if (current != token) return;
        if (index >= (NSInteger)lines.count) return;

        NSString *full = lines[index] ?: @"";
        UIColor *color = (index < (NSInteger)colors.count) ? colors[index] : [strongPack accentColor];
        // Start with full text immediately, then optionally animate later lines only.
        // Empty starter labels were the "chữ không hiện" intermittent failure mode.
        UILabel *line = TCTLine(strongPack, full, color, 11);
        [strongPack.stack addArrangedSubview:line];
        index += 1;
        if (index < (NSInteger)lines.count && typeNextWeak) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(gap, 0.02) * NSEC_PER_SEC)), dispatch_get_main_queue(), typeNextWeak);
        }
    };
    typeNextWeak = typeNext;
    typeNext();
}

@interface TserverPack_cyber_terminal : TserverSimpleUiPackBase
- (void)stopTerminalMotion;
@end

@implementation TserverPack_cyber_terminal

- (void)installShell {
    [self installCenteredCardShell];
}

- (void)stopTerminalMotion {
    NSNumber *tokenNumber = objc_getAssociatedObject(self, &kTCTStreamTokenKey);
    objc_setAssociatedObject(self, &kTCTStreamTokenKey, @(tokenNumber.integerValue + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSTimer *timer = objc_getAssociatedObject(self, &kTCTCursorTimerKey);
    [timer invalidate];
    objc_setAssociatedObject(self, &kTCTCursorTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *scanline = objc_getAssociatedObject(self, &kTCTScanlineKey);
    [scanline.layer removeAllAnimations];
}

#pragma mark - BACKGROUND
- (void)buildBackground {
    [self stopTerminalMotion];
    UIColor *card = [self cardColor];
    UIColor *accent = [self accentColor];
    self.root.backgroundColor = [UIColor colorWithRed:0.01 green:0.03 blue:0.02 alpha:0.72];
    self.content.backgroundColor = card;
    self.content.alpha = 1;
    self.content.layer.borderWidth = 1.2;
    self.content.layer.borderColor = [accent colorWithAlphaComponent:0.72].CGColor;
    self.content.layer.cornerRadius = 12;
    self.content.clipsToBounds = YES;

    NSArray *sublayers = self.content.layer.sublayers.copy;
    for (CALayer *layer in sublayers) {
        if ([layer isKindOfClass:CAGradientLayer.class]) [layer removeFromSuperlayer];
    }
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[accent colorWithAlphaComponent:0.22].CGColor,
        (id)[card colorWithAlphaComponent:1].CGColor,
        (id)[UIColor colorWithRed:0.01 green:0.05 blue:0.03 alpha:1].CGColor
    ];
    gradient.locations = @[ @0.0, @0.5, @1.0 ];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 1);
    gradient.frame = UIScreen.mainScreen.bounds;
    [self.content.layer insertSublayer:gradient atIndex:0];

    UIView *oldScan = objc_getAssociatedObject(self, &kTCTScanlineKey);
    [oldScan removeFromSuperview];
    UIView *scanline = [UIView new];
    scanline.userInteractionEnabled = NO;
    scanline.translatesAutoresizingMaskIntoConstraints = NO;
    scanline.backgroundColor = [accent colorWithAlphaComponent:0.10];
    [self.content addSubview:scanline];
    [NSLayoutConstraint activateConstraints:@[
        [scanline.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],
        [scanline.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],
        [scanline.topAnchor constraintEqualToAnchor:self.content.topAnchor constant:-20],
        [scanline.heightAnchor constraintEqualToConstant:16]
    ]];
    objc_setAssociatedObject(self, &kTCTScanlineKey, scanline, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![TserverTemplateRegistry reduceMotionEnabled]) {
        CABasicAnimation *scan = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        scan.fromValue = @0;
        scan.toValue = @(420);
        scan.duration = 2.6;
        scan.repeatCount = HUGE_VALF;
        scan.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [scanline.layer addAnimation:scan forKey:@"tserver.scanline"];
    }
}

#pragma mark - HERO / HUD
- (void)buildHero {
    BOOL compact = [self isCompactLandscape];
    UILabel *prompt = TCTLine(self,
        compact ? @"root@tserver:~# ./authenticate" : @"root@tserver:~# ./authenticate --secure --verbose",
        [self accentColor],
        compact ? 10 : 11);
    UILabel *cursor = TCTLine(self, compact ? @"█ awaiting_input" : @"█ awaiting_input", [self accentColor], compact ? 10 : 11);

    UIStackView *heroStack = [UIStackView new];
    heroStack.axis = UILayoutConstraintAxisVertical;
    heroStack.spacing = compact ? 5 : 7;
    heroStack.translatesAutoresizingMaskIntoConstraints = NO;
    [heroStack addArrangedSubview:TCTLine(self, @"● ● ●  tserver-auth", [self mutedTextColor], compact ? 8 : 9)];
    [heroStack addArrangedSubview:prompt];
    [heroStack addArrangedSubview:cursor];

    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.30];
    panel.layer.cornerRadius = compact ? 9 : 10;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [[self accentColor] colorWithAlphaComponent:0.28].CGColor;
    [panel addSubview:heroStack];
    CGFloat pad = compact ? 9 : 10;
    [NSLayoutConstraint activateConstraints:@[
        [heroStack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:pad],
        [heroStack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],
        [heroStack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-pad],
        [heroStack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-pad]
    ]];
    [self.stack addArrangedSubview:panel];

    NSTimer *old = objc_getAssociatedObject(self, &kTCTCursorTimerKey);
    [old invalidate];
    if (![TserverTemplateRegistry reduceMotionEnabled]) {
        __weak UILabel *weakCursor = cursor;
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.45 repeats:YES block:^(__unused NSTimer *t) {
            weakCursor.alpha = weakCursor.alpha > 0.5 ? 0.15 : 1.0;
        }];
        [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        objc_setAssociatedObject(self, &kTCTCursorTimerKey, timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSString *status = self.context.status ?: @"UNKNOWN";
    if (compact) {
        // Medium landscape: one status line, not the full typed dump.
        TCTAppendLine(self, [NSString stringWithFormat:@"> status = %@", status], [self accentColor]);
    } else {
        TCTTypeLines(self,
            @[ @"> init secure_channel", @"> load package_token", [NSString stringWithFormat:@"> status = %@", status] ],
            @[ [self mutedTextColor], [self mutedTextColor], [self accentColor] ],
            0.07);
    }
}

- (void)buildHud {
    // Popups are presented by TserverPopupRenderer on the root overlay so they
    // share the selected terminal palette without changing card layout.
}

#pragma mark - SCREEN ROUTER
- (void)buildKeyArea { TserverCyberTerminalBuildKeyEntry(self); }
- (void)buildUuidArea { TserverCyberTerminalBuildDeviceVerify(self); }
- (void)buildResultArea {
    if ([self.context.status isEqualToString:@"LOADING"]) {
        TserverCyberTerminalBuildLoading(self);
        return;
    }
    TserverCyberTerminalBuildResult(self);
}

- (void)buildNoticeArea {
    // Package announcement rendered in the pack's own terminal language instead
    // of a generic card, so it reads like the rest of the Cyber Terminal gate.
    BOOL compact = [self isCompactLandscape];
    NSString *title = [self.context.result[@"noticeTitle"] isKindOfClass:NSString.class]
        ? self.context.result[@"noticeTitle"] : @"Thông báo";
    NSString *message = [self.context.result[@"noticeMessage"] isKindOfClass:NSString.class]
        ? self.context.result[@"noticeMessage"] : @"";
    NSString *type = [self.context.result[@"noticeType"] isKindOfClass:NSString.class]
        ? self.context.result[@"noticeType"] : @"info";
    NSString *closeText = [self screenString:@"closeButtonText" fallback:@"Đóng"];
    NSString *snoozeText = [self screenString:@"snoozeButtonText" fallback:@"Đóng trong 3 giờ"];

    UIColor *tone = [type isEqualToString:@"danger"] ? [self dangerColor]
        : ([type isEqualToString:@"success"] ? [self successColor] : [self accentColor]);

    TCTAppendLine(self, @"> broadcast_received", tone);
    TCTAppendLine(self, [NSString stringWithFormat:@"> title: %@", title], tone);
    if (message.length > 0 && !compact) {
        TCTAppendLine(self, [NSString stringWithFormat:@"> %@", message], [self mutedTextColor]);
    }

    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.34];
    panel.layer.cornerRadius = compact ? 10 : 12;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [tone colorWithAlphaComponent:0.45].CGColor;

    UIStackView *inner = [UIStackView new];
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = compact ? 9 : 10;
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:inner];
    CGFloat pad = compact ? 11 : 12;
    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:panel.topAnchor constant:pad],
        [inner.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],
        [inner.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-pad],
        [inner.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-pad]
    ]];
    [inner addArrangedSubview:TCTLine(self, [NSString stringWithFormat:@"> notice_id = %@",
        [self.context.result[@"noticeId"] isKindOfClass:NSString.class] ? self.context.result[@"noticeId"] : @"active"],
        [self mutedTextColor], compact ? 10 : 11)];

    UIButton *snooze = [self button:snoozeText action:@selector(noticeSnoozeTapped)];
    snooze.backgroundColor = [[self accentColor] colorWithAlphaComponent:0.20];
    [snooze setTitleColor:[self textColor] forState:UIControlStateNormal];
    snooze.titleLabel.font = TCTFont(compact ? 12 : 13);
    snooze.layer.cornerRadius = 10;
    [inner addArrangedSubview:snooze];

    UIButton *close = [self button:closeText action:@selector(noticeCloseTapped)];
    close.backgroundColor = tone;
    close.titleLabel.font = TCTFont(compact ? 13 : 14);
    close.layer.cornerRadius = 10;
    [inner addArrangedSubview:close];

    [self.stack addArrangedSubview:panel];
}

- (void)playEnterMotion {
    // Use the base implementation — it guards against interrupted alpha=0 fades
    // that made labels/buttons disappear during rapid status updates.
    [super playEnterMotion];
}

@end
