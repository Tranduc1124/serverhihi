#import <UIKit/UIKit.h>

@interface TserverTheme : NSObject
+ (UIColor *)colorFromHex:(NSString *)hex fallback:(UIColor *)fallback;
+ (UIFont *)titleFont;
+ (UIFont *)subtitleFont;
+ (UIFont *)loadingTitleFont;
+ (UIFont *)loadingSubtitleFont;
+ (UIFont *)buttonFont;
+ (UIFont *)inputFont;
@end

@implementation TserverTheme

+ (UIColor *)colorFromHex:(NSString *)hex fallback:(UIColor *)fallback {
    if (![hex isKindOfClass:NSString.class] || hex.length == 0) {
        return fallback;
    }
    NSString *clean = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length == 3) {
        unichar r = [clean characterAtIndex:0];
        unichar g = [clean characterAtIndex:1];
        unichar b = [clean characterAtIndex:2];
        clean = [NSString stringWithFormat:@"%C%C%C%C%C%C", r, r, g, g, b, b];
    }
    if (clean.length != 6) return fallback;

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) return fallback;
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
                           green:((rgb >> 8) & 0xff) / 255.0
                            blue:(rgb & 0xff) / 255.0
                           alpha:1.0];
}

+ (UIFont *)titleFont {
    return [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
}

+ (UIFont *)subtitleFont {
    return [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
}

+ (UIFont *)loadingTitleFont {
    return [UIFont systemFontOfSize:23 weight:UIFontWeightBold];
}

+ (UIFont *)loadingSubtitleFont {
    return [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
}

+ (UIFont *)buttonFont {
    return [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
}

+ (UIFont *)inputFont {
    return [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
}

@end
