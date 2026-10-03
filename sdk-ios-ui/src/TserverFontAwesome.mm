#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#include <stddef.h>
#include <stdint.h>

// Embedded by sdk-ios-ui/scripts/embed_fa_font.sh into TserverFontAwesomeData.gen.mm
// and linked into libAPIClient.a so the consumer dylib does not need a separate font file.
extern "C" {
extern const uint8_t kTserverFontAwesomeSolidBytes[];
extern const size_t kTserverFontAwesomeSolidLength;
}

@interface TserverFontAwesome : NSObject
+ (void)ensureRegistered;
+ (UIFont *)solidFontOfSize:(CGFloat)size;
+ (BOOL)isEmbeddedAvailable;
@end

@implementation TserverFontAwesome

static NSString *gRegisteredFamily = nil;
static BOOL gTriedRegister = NO;

+ (BOOL)isEmbeddedAvailable {
    return kTserverFontAwesomeSolidLength > 1000;
}

+ (void)ensureRegistered {
    if (gTriedRegister) return;
    gTriedRegister = YES;

    // 1) Already present in process (host app shipped FA).
    NSArray<NSString *> *known = @[
        @"FontAwesome6Free-Solid",
        @"Font Awesome 6 Free",
        @"FontAwesome6FreeSolid",
        @"FontAwesome5Free-Solid",
        @"Font Awesome 5 Free",
        @"FontAwesome"
    ];
    for (NSString *name in known) {
        UIFont *font = [UIFont fontWithName:name size:16.0];
        if (font) {
            gRegisteredFamily = font.fontName;
            return;
        }
    }

    // 2) Register embedded bytes shipped inside libAPIClient.a.
    if (![self isEmbeddedAvailable]) return;

    CFDataRef data = CFDataCreate(kCFAllocatorDefault,
                                  kTserverFontAwesomeSolidBytes,
                                  (CFIndex)kTserverFontAwesomeSolidLength);
    if (!data) return;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    if (!provider) return;
    CGFontRef cgFont = CGFontCreateWithDataProvider(provider);
    CGDataProviderRelease(provider);
    if (!cgFont) return;

    CFErrorRef error = NULL;
    Boolean ok = CTFontManagerRegisterGraphicsFont(cgFont, &error);
    if (!ok && error) {
        // Already registered is fine.
        CFRelease(error);
    }

    CFStringRef psName = CGFontCopyPostScriptName(cgFont);
    if (psName) {
        gRegisteredFamily = CFBridgingRelease(psName);
    }
    CGFontRelease(cgFont);

    // Probe a few names in case PostScript name differs from UIFont name.
    if (!gRegisteredFamily.length || ![UIFont fontWithName:gRegisteredFamily size:12]) {
        for (NSString *name in known) {
            if ([UIFont fontWithName:name size:12]) {
                gRegisteredFamily = name;
                break;
            }
        }
    }
}

+ (UIFont *)solidFontOfSize:(CGFloat)size {
    [self ensureRegistered];
    if (gRegisteredFamily.length) {
        UIFont *font = [UIFont fontWithName:gRegisteredFamily size:size];
        if (font) return font;
    }
    // Last try common names without prior success flag.
    NSArray<NSString *> *known = @[
        @"FontAwesome6Free-Solid",
        @"Font Awesome 6 Free",
        @"FontAwesome6FreeSolid",
        @"FontAwesome5Free-Solid",
        @"Font Awesome 5 Free"
    ];
    for (NSString *name in known) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) return font;
    }
    return nil;
}

@end
