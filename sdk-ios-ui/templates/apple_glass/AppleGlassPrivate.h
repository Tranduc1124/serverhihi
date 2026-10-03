#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class TserverSimpleUiPackBase;

#ifdef __cplusplus
extern "C" {
#endif

void TserverAppleGlassBuildLoading(TserverSimpleUiPackBase *pack);
void TserverAppleGlassBuildKeyEntry(TserverSimpleUiPackBase *pack);
void TserverAppleGlassBuildDeviceVerify(TserverSimpleUiPackBase *pack);
void TserverAppleGlassBuildResult(TserverSimpleUiPackBase *pack);

__attribute__((unused)) static inline BOOL TAGIsIOS13OrLater(void) {
    static BOOL sIsIOS13;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sIsIOS13 = [UIColor respondsToSelector:NSSelectorFromString(@"systemBlueColor")];
    });
    return sIsIOS13;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

__attribute__((unused)) static inline UIColor *TAGSystemBlue(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor systemBlueColor];
    }
    return [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
}

__attribute__((unused)) static inline UIColor *TAGLabelColor(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor labelColor];
    }
    return [UIColor whiteColor];
}

__attribute__((unused)) static inline UIColor *TAGSecondaryLabelColor(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor secondaryLabelColor];
    }
    return [UIColor colorWithWhite:0.75 alpha:1.0];
}

__attribute__((unused)) static inline UIColor *TAGSystemGreen(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor systemGreenColor];
    }
    return [UIColor colorWithRed:0.196 green:0.843 blue:0.294 alpha:1.0];
}

__attribute__((unused)) static inline UIColor *TAGSystemRed(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor systemRedColor];
    }
    return [UIColor colorWithRed:1.0 green:0.271 blue:0.227 alpha:1.0];
}

__attribute__((unused)) static inline UIColor *TAGSystemOrange(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor systemOrangeColor];
    }
    return [UIColor colorWithRed:1.0 green:0.624 blue:0.039 alpha:1.0];
}

__attribute__((unused)) static inline UIColor *TAGInputBackgroundColor(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor tertiarySystemFillColor];
    }
    return [UIColor colorWithWhite:1.0 alpha:0.10];
}

__attribute__((unused)) static inline UIColor *TAGGroupedBackgroundColor(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor secondarySystemFillColor];
    }
    return [UIColor colorWithWhite:1.0 alpha:0.07];
}

__attribute__((unused)) static inline UIColor *TAGHairlineColor(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor separatorColor];
    }
    return [UIColor colorWithWhite:1.0 alpha:0.16];
}

// Adaptive blur material — follows the device Light/Dark appearance automatically.
__attribute__((unused)) static inline UIBlurEffect *TAGAdaptiveBlur(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
}

// Dim scrim behind the alert; slightly stronger in dark, lighter in light.
__attribute__((unused)) static inline UIColor *TAGScrimColor(void) {
    if (TAGIsIOS13OrLater()) {
        return [UIColor colorWithWhite:0.0 alpha:0.32];
    }
    return [UIColor colorWithWhite:0.0 alpha:0.42];
}

// Placeholder / very-muted text that adapts to Light and Dark.
__attribute__((unused)) static inline UIColor *TAGPlaceholderTextColor(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    if (TAGIsIOS13OrLater()) {
        return [UIColor placeholderTextColor];
    }
#pragma clang diagnostic pop
    return [UIColor colorWithWhite:0.55 alpha:1.0];
}

#pragma clang diagnostic pop

UIView *TAGIconBadge(NSString *glyph, UIColor *tint, CGFloat iconSize);
UIButton *TAGActionButton(TserverSimpleUiPackBase *pack, NSString *title, UIColor *bgColor, SEL action);
UIView *TAGGroupedContainer(void);
UIView *TAGInfoRow(NSString *label, NSString *value, UIColor *textColor, UIColor *mutedColor);

#ifdef __cplusplus
}
#endif
