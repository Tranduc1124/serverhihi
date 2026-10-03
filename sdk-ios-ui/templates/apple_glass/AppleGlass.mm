#import "TserverSimpleUiPack.h"
#import "TserverTemplateRegistry.h"
#import "AppleGlassPrivate.h"
#import <objc/runtime.h>

// APPLE GLASS ALERT / PACK SHELL
// Native iOS Liquid Glass Alert Dialog with system blur, hairline specular borders,
// Apple system dynamic colors and spring motion.

#pragma mark - Font Awesome Helper

static UIFont *TAGFontAwesomeFont(CGFloat size) {
    Class fa = NSClassFromString(@"TserverFontAwesome");
    SEL sel = NSSelectorFromString(@"solidFontOfSize:");
    if (fa && [fa respondsToSelector:sel]) {
        typedef UIFont *(*FAFontIMP)(id, SEL, CGFloat);
        FAFontIMP imp = (FAFontIMP)[fa methodForSelector:sel];
        if (imp) {
            UIFont *font = imp(fa, sel, size);
            if (font) return font;
        }
    }
    return [UIFont systemFontOfSize:size weight:UIFontWeightBold];
}

#pragma mark - Component Builders

UIView *TAGIconBadge(NSString *glyph, UIColor *tint, CGFloat iconSize) {
    UIView *badge = [UIView new];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = [tint colorWithAlphaComponent:0.14];
    badge.layer.cornerRadius = 24.0;
    badge.layer.borderWidth = 0.5;
    badge.layer.borderColor = [tint colorWithAlphaComponent:0.32].CGColor;
    badge.clipsToBounds = YES;

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = glyph ?: @"";
    label.textColor = tint;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = TAGFontAwesomeFont(iconSize);
    [badge addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:48.0],
        [badge.heightAnchor constraintEqualToConstant:48.0],
        [label.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor]
    ]];
    return badge;
}

UIButton *TAGActionButton(TserverSimpleUiPackBase *pack, NSString *title, UIColor *bgColor, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title ?: @"OK" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    button.backgroundColor = bgColor ?: TAGSystemBlue();
    button.layer.cornerRadius = 12.0;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 18, 12, 18);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    [button addTarget:pack action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

UIView *TAGGroupedContainer(void) {
    UIView *container = [UIView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = TAGGroupedBackgroundColor();
    container.layer.cornerRadius = 12.0;
    container.layer.borderWidth = 0.5;
    container.layer.borderColor = TAGHairlineColor().CGColor;
    container.clipsToBounds = YES;
    return container;
}

UIView *TAGInfoRow(NSString *label, NSString *value, UIColor *textColor, UIColor *mutedColor) {
    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = label ?: @"";
    lbl.textColor = mutedColor ?: TAGSecondaryLabelColor();
    lbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];

    UILabel *val = [UILabel new];
    val.translatesAutoresizingMaskIntoConstraints = NO;
    val.text = value ?: @"—";
    val.textColor = textColor ?: TAGLabelColor();
    val.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    val.textAlignment = NSTextAlignmentRight;

    [row addSubview:lbl];
    [row addSubview:val];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [lbl.topAnchor constraintEqualToAnchor:row.topAnchor],
        [lbl.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [val.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [val.centerYAnchor constraintEqualToAnchor:lbl.centerYAnchor],
        [val.leadingAnchor constraintGreaterThanOrEqualToAnchor:lbl.trailingAnchor constant:8.0]
    ]];
    return row;
}

#pragma mark - Pack Shell Class

@interface TserverPack_apple_glass : TserverSimpleUiPackBase {
    BOOL _didPlayAppleMotion;
}
@end

@implementation TserverPack_apple_glass

- (void)installShell {
    [self installCenteredCardShell];
}

- (void)buildBackground {
    self.root.backgroundColor = TAGScrimColor();

    for (UIView *sub in self.content.subviews.copy) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) {
            [sub removeFromSuperview];
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:TAGAdaptiveBlur()];
#pragma clang diagnostic pop
    blurView.frame = self.content.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blurView.userInteractionEnabled = NO;
    [self.content insertSubview:blurView atIndex:0];

    // Adaptive base tint under the material; near-transparent so blur dominates.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    if (TAGIsIOS13OrLater()) {
        self.content.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.12 alpha:0.55]
                : [UIColor colorWithWhite:1.0 alpha:0.55];
        }];
    } else {
        self.content.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.50];
    }
#pragma clang diagnostic pop
    self.content.layer.cornerRadius = 18.0;
    self.content.layer.borderWidth = 0.5;
    self.content.layer.borderColor = TAGHairlineColor().CGColor;
    self.content.clipsToBounds = YES;
}

- (void)buildHero {
    NSString *status = self.context.status ?: @"";
    NSString *glyph = @""; // key
    UIColor *tint = TAGSystemBlue();

    if ([status hasPrefix:@"VALID"] || [status isEqualToString:@"OFFLINE_GRACE_VALID"]) {
        glyph = @""; // check
        tint = TAGSystemGreen();
    } else if ([status isEqualToString:@"EXPIRED"] || [status isEqualToString:@"OFFLINE_GRACE_EXPIRED"] || [status isEqualToString:@"PROFILE_EXPIRED"]) {
        glyph = @""; // clock
        tint = TAGSystemOrange();
    } else if ([status isEqualToString:@"REVOKED"] || [status isEqualToString:@"DEVICE_BLOCKED"]) {
        glyph = @""; // ban
        tint = TAGSystemRed();
    } else if ([status isEqualToString:@"NEED_UUID"]) {
        glyph = @""; // shield
        tint = TAGSystemBlue();
    } else if ([status isEqualToString:@"LOADING"]) {
        glyph = @""; // spinner
        tint = TAGSystemBlue();
    } else if ([status isEqualToString:@"UPDATE_REQUIRED"]) {
        glyph = @""; // arrow-up
        tint = TAGSystemBlue();
    } else if ([status isEqualToString:@"NETWORK_ERROR"] || [status isEqualToString:@"SERVER_ERROR"] ||
               [status isEqualToString:@"INVALID_KEY"] || [status isEqualToString:@"DEVICE_MISMATCH"]) {
        glyph = @""; // triangle-exclamation
        tint = TAGSystemRed();
    }

    UIView *badge = TAGIconBadge(glyph, tint, 22.0);
    UIView *wrapper = [UIView new];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [wrapper addSubview:badge];
    [NSLayoutConstraint activateConstraints:@[
        [badge.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [badge.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:2.0],
        [badge.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-4.0]
    ]];
    [self.stack addArrangedSubview:wrapper];
}

- (void)buildKeyArea {
    TserverAppleGlassBuildKeyEntry(self);
}

- (void)buildUuidArea {
    TserverAppleGlassBuildDeviceVerify(self);
}

- (void)buildResultArea {
    if ([self.context.status isEqualToString:@"LOADING"]) {
        TserverAppleGlassBuildLoading(self);
        return;
    }
    TserverAppleGlassBuildResult(self);
}

- (void)playEnterMotion {
    if (_didPlayAppleMotion) {
        self.content.alpha = 1;
        self.content.transform = CGAffineTransformIdentity;
        return;
    }
    _didPlayAppleMotion = YES;
    if ([TserverTemplateRegistry reduceMotionEnabled] || !self.content) {
        self.content.alpha = 1;
        return;
    }
    [self.content.layer removeAllAnimations];
    self.content.alpha = 0.05;
    self.content.transform = CGAffineTransformMakeScale(1.12, 1.12);
    [UIView animateWithDuration:0.28
                          delay:0
         usingSpringWithDamping:0.75
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.content.alpha = 1;
        self.content.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.content.alpha = 1;
        self.content.transform = CGAffineTransformIdentity;
    }];
}

@end
