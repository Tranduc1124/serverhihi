#import "TserverPopupRenderer.h"
#import "TserverTemplateRegistry.h"

@interface TserverPopupRenderer ()
@property(nonatomic, weak) UIView *hostView;
@property(nonatomic, copy) NSDictionary *config;
@property(nonatomic, copy) NSString *presentation;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, assign) NSInteger generation;
@end

@implementation TserverPopupRenderer

- (instancetype)initWithHostView:(UIView *)hostView
                          config:(NSDictionary *)config
                    presentation:(NSString *)presentation {
    self = [super init];
    if (self) {
        _hostView = hostView;
        _config = [config isKindOfClass:NSDictionary.class] ? [config copy] : @{};
        _presentation = presentation.length > 0 ? [presentation copy] : @"generic_status";
    }
    return self;
}

- (void)dealloc {
    [self invalidate];
}

- (void)invalidate {
    self.generation += 1;
    [self.timer invalidate];
    self.timer = nil;
    [self.panel.layer removeAllAnimations];
    [self.panel removeFromSuperview];
    self.panel = nil;
}

- (BOOL)boolValue:(id)value fallback:(BOOL)fallback {
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

- (CGFloat)numberValue:(id)value fallback:(CGFloat)fallback {
    return [value respondsToSelector:@selector(doubleValue)] ? (CGFloat)[value doubleValue] : fallback;
}

- (NSString *)stringValue:(id)value fallback:(NSString *)fallback {
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : (fallback ?: @"");
}

- (NSDictionary *)deepMerge:(NSDictionary *)base override:(NSDictionary *)override {
    NSMutableDictionary *out = [base isKindOfClass:NSDictionary.class] ? [base mutableCopy] : [NSMutableDictionary dictionary];
    if (![override isKindOfClass:NSDictionary.class]) return out;
    [override enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || object == nil || object == NSNull.null) return;
        id existing = out[key];
        out[key] = ([existing isKindOfClass:NSDictionary.class] && [object isKindOfClass:NSDictionary.class])
            ? [self deepMerge:existing override:object]
            : object;
    }];
    return out;
}

- (NSDictionary *)popupForScreen:(NSString *)screenName {
    NSDictionary *root = [self.config[@"popup"] isKindOfClass:NSDictionary.class] ? self.config[@"popup"] : @{};
    NSMutableDictionary *base = [root mutableCopy];
    NSDictionary *screens = [base[@"screens"] isKindOfClass:NSDictionary.class] ? base[@"screens"] : @{};
    [base removeObjectForKey:@"screens"];
    NSDictionary *screen = [screens[screenName ?: @""] isKindOfClass:NSDictionary.class] ? screens[screenName ?: @""] : @{};
    return [self deepMerge:base override:screen];
}

- (UIColor *)colorForKey:(NSString *)key fallback:(UIColor *)fallback {
    NSDictionary *style = [self.config[@"style"] isKindOfClass:NSDictionary.class] ? self.config[@"style"] : @{};
    NSString *hex = [style[key] isKindOfClass:NSString.class] ? style[key] : nil;
    if (hex.length < 7) return fallback;
    NSString *value = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([value hasPrefix:@"#"]) value = [value substringFromIndex:1];
    if (value.length != 6 && value.length != 8) return fallback;
    unsigned int raw = 0;
    if (![[NSScanner scannerWithString:value] scanHexInt:&raw]) return fallback;
    CGFloat alpha = value.length == 8 ? ((raw >> 24) & 0xFF) / 255.0 : 1.0;
    CGFloat red = ((raw >> 16) & 0xFF) / 255.0;
    CGFloat green = ((raw >> 8) & 0xFF) / 255.0;
    CGFloat blue = (raw & 0xFF) / 255.0;
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color terminal:(BOOL)terminal {
    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.text = text ?: @"";
    label.textColor = color;
    if (terminal) {
        UIFont *font = [UIFont fontWithName:@"Menlo-Bold" size:size] ?: [UIFont fontWithName:@"CourierNewPS-BoldMT" size:size];
        if (!font) {
            // Avoid @available (needs ___isOSVersionAtLeast in consumer link).
            if ([UIFont respondsToSelector:@selector(monospacedSystemFontOfSize:weight:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
                font = [UIFont monospacedSystemFontOfSize:size weight:weight];
#pragma clang diagnostic pop
            } else {
                font = [UIFont systemFontOfSize:size weight:weight];
            }
        }
        label.font = font;
    } else {
        label.font = [UIFont systemFontOfSize:size weight:weight];
    }
    return label;
}

- (void)presentForStatus:(NSString *)status
              screenName:(NSString *)screenName
                 message:(NSString *)message {
    [self invalidate];
    UIView *host = self.hostView;
    if (!host) return;
    NSDictionary *popup = [self popupForScreen:screenName];
    if (![self boolValue:popup[@"enabled"] fallback:NO]) return;

    NSInteger generation = self.generation;
    BOOL terminal = [self.presentation isEqualToString:@"terminal_status"];
    NSString *configuredPresentation = [self stringValue:popup[@"presentation"] fallback:self.presentation];
    if ([configuredPresentation isEqualToString:@"terminal_status"]) terminal = YES;
    NSDictionary *screens = [self.config[@"screens"] isKindOfClass:NSDictionary.class] ? self.config[@"screens"] : @{};
    NSDictionary *screen = [screens[screenName ?: @""] isKindOfClass:NSDictionary.class] ? screens[screenName ?: @""] : @{};
    NSString *fallbackTitle = [self stringValue:screen[@"title"] fallback:status ?: @"STATUS"];
    NSString *fallbackSubtitle = [self stringValue:screen[@"subtitle"] fallback:message ?: @""];
    NSString *title = [self stringValue:popup[@"title"] fallback:fallbackTitle];
    NSString *subtitle = [self stringValue:popup[@"subtitle"] fallback:(message.length ? message : fallbackSubtitle)];
    BOOL showProgress = [self boolValue:popup[@"showProgress"] fallback:YES];
    BOOL showSteps = [self boolValue:popup[@"showSteps"] fallback:NO];
    NSArray *rawSteps = [popup[@"steps"] isKindOfClass:NSArray.class] ? popup[@"steps"] : @[];
    NSMutableArray<NSString *> *steps = [NSMutableArray array];
    for (id item in rawSteps) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *step = [((NSString *)item) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (step.length == 0) continue;
        [steps addObject:step];
        if (steps.count >= 6) break;
    }
    CGFloat opacity = MIN(1.0, MAX(0.25, [self numberValue:popup[@"opacity"] fallback:0.92]));
    CGFloat width = MIN(380.0, MAX(170.0, [self numberValue:popup[@"width"] fallback:(terminal ? (showSteps ? 280.0 : 246.0) : 264.0)]));
    CGFloat radius = MIN(30.0, MAX(8.0, [self numberValue:popup[@"radius"] fallback:(terminal ? 10.0 : 20.0)]));
    CGFloat from = MIN(100.0, MAX(0.0, [self numberValue:popup[@"progressFrom"] fallback:0.0]));
    CGFloat to = MIN(100.0, MAX(from, [self numberValue:popup[@"progressTo"] fallback:100.0]));

    UIColor *accent = [self colorForKey:@"accent" fallback:[UIColor colorWithRed:0.22 green:0.96 blue:0.75 alpha:1]];
    UIColor *card = [self colorForKey:@"card" fallback:[UIColor colorWithWhite:0.08 alpha:1]];
    UIColor *text = [self colorForKey:@"text" fallback:UIColor.whiteColor];
    UIColor *muted = [self colorForKey:@"mutedText" fallback:[UIColor colorWithWhite:0.72 alpha:1]];
    UIColor *border = terminal ? [accent colorWithAlphaComponent:0.70] : [muted colorWithAlphaComponent:0.28];

    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.userInteractionEnabled = NO;
    panel.accessibilityElementsHidden = YES;
    panel.backgroundColor = [card colorWithAlphaComponent:opacity];
    panel.layer.cornerRadius = radius;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = border.CGColor;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.30;
    panel.layer.shadowRadius = terminal ? 14.0 : 18.0;
    panel.layer.shadowOffset = CGSizeMake(0, 8);

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = terminal ? 5.0 : 7.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    if (terminal) {
        [stack addArrangedSubview:[self label:@"> tserver status" size:9 weight:UIFontWeightBold color:accent terminal:YES]];
    }
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = terminal ? 8.0 : 10.0;
    [stack addArrangedSubview:row];

    UILabel *badge = nil;
    if (showProgress) {
        UIView *badgeView = [UIView new];
        badgeView.translatesAutoresizingMaskIntoConstraints = NO;
        badgeView.backgroundColor = [accent colorWithAlphaComponent:0.16];
        badgeView.layer.cornerRadius = terminal ? 13 : 16;
        badgeView.layer.borderWidth = 1;
        badgeView.layer.borderColor = [accent colorWithAlphaComponent:0.65].CGColor;
        [badgeView.widthAnchor constraintEqualToConstant:terminal ? 26 : 32].active = YES;
        [badgeView.heightAnchor constraintEqualToConstant:terminal ? 26 : 32].active = YES;
        badge = [self label:@"0%" size:terminal ? 9 : 10 weight:UIFontWeightBold color:accent terminal:terminal];
        badge.textAlignment = NSTextAlignmentCenter;
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [badgeView addSubview:badge];
        [NSLayoutConstraint activateConstraints:@[
            [badge.centerXAnchor constraintEqualToAnchor:badgeView.centerXAnchor],
            [badge.centerYAnchor constraintEqualToAnchor:badgeView.centerYAnchor]
        ]];
        [row addArrangedSubview:badgeView];
    }

    UIStackView *copy = [UIStackView new];
    copy.axis = UILayoutConstraintAxisVertical;
    copy.spacing = 2;
    [copy addArrangedSubview:[self label:title size:terminal ? 11 : 13 weight:UIFontWeightBold color:text terminal:terminal]];
    if (subtitle.length) [copy addArrangedSubview:[self label:subtitle size:terminal ? 9 : 11 weight:UIFontWeightRegular color:muted terminal:terminal]];
    [row addArrangedSubview:copy];

    UIView *track = nil;
    NSLayoutConstraint *progressWidth = nil;
    if (showProgress) {
        track = [UIView new];
        track.translatesAutoresizingMaskIntoConstraints = NO;
        track.backgroundColor = [muted colorWithAlphaComponent:0.18];
        track.layer.cornerRadius = 2;
        [stack addArrangedSubview:track];
        UIView *bar = [UIView new];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        bar.backgroundColor = accent;
        bar.layer.cornerRadius = 2;
        [track addSubview:bar];
        progressWidth = [bar.widthAnchor constraintEqualToConstant:0];
        [NSLayoutConstraint activateConstraints:@[
            [track.heightAnchor constraintEqualToConstant:terminal ? 3 : 5],
            [bar.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
            [bar.topAnchor constraintEqualToAnchor:track.topAnchor],
            [bar.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
            progressWidth
        ]];
    }

    NSMutableArray<UILabel *> *stepLabels = [NSMutableArray array];
    if (showSteps && steps.count > 0) {
        UIStackView *stepStack = [UIStackView new];
        stepStack.axis = UILayoutConstraintAxisVertical;
        stepStack.spacing = terminal ? 3.0 : 5.0;
        [stack addArrangedSubview:stepStack];
        for (NSUInteger index = 0; index < steps.count; index += 1) {
            UILabel *stepLabel = [self label:[NSString stringWithFormat:@"• %@", steps[index]]
                                       size:terminal ? 9 : 10
                                     weight:UIFontWeightRegular
                                      color:muted
                                   terminal:terminal];
            [stepStack addArrangedSubview:stepLabel];
            [stepLabels addObject:stepLabel];
        }
    }

    CGFloat pad = terminal ? 10 : 12;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:pad],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-pad],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-pad],
        [panel.widthAnchor constraintEqualToConstant:width]
    ]];
    [host addSubview:panel];
    self.panel = panel;

    NSString *position = [self stringValue:popup[@"position"] fallback:@"topTrailing"];
    UILayoutGuide *guide = host.safeAreaLayoutGuide;
    CGFloat inset = 14;
    if ([position isEqualToString:@"topLeading"]) {
        [panel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:inset].active = YES;
        [panel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:inset].active = YES;
    } else if ([position isEqualToString:@"bottomTrailing"]) {
        [panel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-inset].active = YES;
        [panel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-inset].active = YES;
    } else if ([position isEqualToString:@"bottomLeading"]) {
        [panel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-inset].active = YES;
        [panel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:inset].active = YES;
    } else {
        [panel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:inset].active = YES;
        [panel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-inset].active = YES;
    }

    void (^update)(CGFloat) = ^(CGFloat progress) {
        if (generation != self.generation || !panel.superview) return;
        if (badge) badge.text = progress >= 100 ? @"✓" : [NSString stringWithFormat:@"%.0f%%", progress];
        if (progressWidth && track) {
            [host layoutIfNeeded];
            progressWidth.constant = MAX(0, CGRectGetWidth(track.bounds) * progress / 100.0);
            [host layoutIfNeeded];
        }
        if (stepLabels.count > 0) {
            for (NSUInteger index = 0; index < stepLabels.count; index += 1) {
                BOOL done = progress >= ((CGFloat)(index + 1) / (CGFloat)stepLabels.count) * 100.0;
                NSString *prefix = done ? @"✓ " : @"• ";
                stepLabels[index].text = [NSString stringWithFormat:@"%@%@", prefix, steps[index]];
                stepLabels[index].textColor = done ? accent : muted;
            }
        }
    };
    update(from);
    BOOL reduceMotion = [TserverTemplateRegistry reduceMotionEnabled];
    panel.alpha = reduceMotion ? 1 : 0.02;
    panel.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, -8);
    [UIView animateWithDuration:reduceMotion ? 0 : 0.20 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        panel.alpha = 1;
        panel.transform = CGAffineTransformIdentity;
    } completion:nil];

    NSTimeInterval duration = MIN(30.0, MAX(0.15, [self numberValue:popup[@"durationMs"] fallback:1800.0] / 1000.0));
    BOOL animate = [self boolValue:popup[@"animateProgress"] fallback:YES] && !reduceMotion;
    if (animate && to > from) {
        NSDate *started = [NSDate date];
        __weak __typeof__(self) weakSelf = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
            __typeof__(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || generation != strongSelf.generation || !panel.superview) { [timer invalidate]; return; }
            CGFloat elapsed = -[started timeIntervalSinceNow];
            CGFloat fraction = MIN(1.0, elapsed / duration);
            update(from + (to - from) * fraction);
            if (fraction >= 1.0) {
                [timer invalidate];
                strongSelf.timer = nil;
                if ([strongSelf boolValue:popup[@"collapseOnComplete"] fallback:YES]) {
                    NSTimeInterval delay = MAX(0, [strongSelf numberValue:popup[@"collapseDelayMs"] fallback:650.0] / 1000.0);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (generation != strongSelf.generation || !panel.superview) return;
                        [UIView animateWithDuration:0.18 animations:^{ panel.alpha = 0; panel.transform = CGAffineTransformMakeScale(0.94, 0.94); } completion:^(__unused BOOL finished) { [panel removeFromSuperview]; }];
                    });
                }
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    } else {
        update(to);
    }
}

@end
