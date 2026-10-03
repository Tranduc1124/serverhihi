#import <UIKit/UIKit.h>
#import "TserverStringCrypto.h"

@interface TserverUIConfig : NSObject
@property(nonatomic, strong) NSDictionary *style;
@property(nonatomic, strong) NSDictionary *assets;
- (UIColor *)colorForKey:(NSString *)key fallback:(UIColor *)fallback;
- (CGFloat)radius;
- (BOOL)shadowEnabled;
- (CGFloat)geometryNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
- (NSString *)geometryStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (CGFloat)typographyNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
@end

@interface TserverTheme : NSObject
+ (UIFont *)titleFont;
+ (UIFont *)subtitleFont;
+ (UIFont *)loadingTitleFont;
+ (UIFont *)loadingSubtitleFont;
+ (UIFont *)buttonFont;
+ (UIFont *)inputFont;
@end

@interface TserverKeyTextField : UITextField <UITextFieldDelegate>
@end

@implementation TserverKeyTextField

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.delegate = self;
        self.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.spellCheckingType = UITextSpellCheckingTypeNo;
        self.clearButtonMode = UITextFieldViewModeWhileEditing;
    }
    return self;
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    NSString *current = textField.text ?: @"";
    NSString *updated = [current stringByReplacingCharactersInRange:range withString:string ?: @""];
    textField.text = [[updated stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    return NO;
}

@end

@interface TserverComponents : NSObject
+ (UIView *)backgroundViewWithConfig:(TserverUIConfig *)config;
+ (UIView *)logoViewWithConfig:(TserverUIConfig *)config;
+ (UIView *)cardViewWithConfig:(TserverUIConfig *)config;
+ (UILabel *)titleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UILabel *)subtitleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UILabel *)errorLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UIButton *)primaryButton:(NSString *)text config:(TserverUIConfig *)config;
+ (UIButton *)secondaryButton:(NSString *)text config:(TserverUIConfig *)config;
+ (UITextField *)keyTextField:(NSString *)placeholder config:(TserverUIConfig *)config;
+ (UIView *)spinnerContainerWithConfig:(TserverUIConfig *)config;
+ (UIView *)iconViewForName:(NSString *)iconName config:(TserverUIConfig *)config;
+ (UILabel *)loadingTitleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (UILabel *)loadingSubtitleLabel:(NSString *)text config:(TserverUIConfig *)config;
+ (void)configureMultilineLabel:(UILabel *)label;
+ (void)addTouchFeedbackToButton:(UIButton *)button;
@end

@implementation TserverComponents

+ (UIColor *)compatSystemColor:(SEL)selector fallback:(UIColor *)fallback {
    if ([UIColor respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIColor *color = [UIColor performSelector:selector];
#pragma clang diagnostic pop
        if (color) return color;
    }
    return fallback;
}

+ (UIColor *)compatPurple { return [self compatSystemColor:@selector(systemPurpleColor) fallback:[UIColor colorWithRed:0.49 green:0.23 blue:0.93 alpha:1.0]]; }
+ (UIColor *)compatRed { return [self compatSystemColor:@selector(systemRedColor) fallback:[UIColor colorWithRed:0.90 green:0.20 blue:0.24 alpha:1.0]]; }
+ (UIColor *)compatBlue { return [self compatSystemColor:@selector(systemBlueColor) fallback:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]]; }

+ (UIImage *)imageFromAssetValue:(id)value {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *raw = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (raw.length == 0) return nil;
    // data:image/...;base64,...
    if ([raw hasPrefix:@"data:image"]) {
        NSRange comma = [raw rangeOfString:@","];
        if (comma.location == NSNotFound) return nil;
        NSString *b64 = [raw substringFromIndex:comma.location + 1];
        NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
        return data ? [UIImage imageWithData:data] : nil;
    }
    // Remote template config is presentation-only. Never resolve arbitrary local
    // file paths from it, and never block the gate on a synchronous HTTP request.
    if ([raw hasPrefix:TS_OBF_NS("file://")] || [raw hasPrefix:@"/"]) return nil;
    if ([raw hasPrefix:TS_OBF_NS("http://")] || [raw hasPrefix:TS_OBF_NS("https://")]) return nil;
    // Bundle resource name (logo.webp etc.)
    UIImage *named = [UIImage imageNamed:raw];
    if (named) return named;
    NSString *path = [[NSBundle mainBundle] pathForResource:raw.stringByDeletingPathExtension ofType:raw.pathExtension];
    if (path.length) return [UIImage imageWithContentsOfFile:path];
    return nil;
}

+ (void)loadRemoteImage:(NSString *)raw intoImageView:(UIImageView *)imageView {
    if (![raw hasPrefix:TS_OBF_NS("https://")]) return;
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) return;
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:4.0];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0 || data.length > 1500000) return;
        if ([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode >= 400) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            imageView.image = image;
            imageView.alpha = 0.0;
            [UIView animateWithDuration:0.18 animations:^{ imageView.alpha = 1.0; }];
        });
    }] resume];
}

+ (UIView *)backgroundViewWithConfig:(TserverUIConfig *)config {
    UIColor *fallback = [UIColor colorWithWhite:0 alpha:0.62];
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [config colorForKey:@"background" fallback:fallback];
    CGFloat overlayOpacity = [config geometryNumberForKey:@"overlayOpacity" fallback:0.96];
    view.alpha = MIN(1.0, MAX(0.0, overlayOpacity));
    view.clipsToBounds = YES;

    id bgAsset = config.assets[@"background"] ?: config.assets[@"bg"] ?: config.assets[@"backgroundUrl"];
    UIImage *bgImage = [self imageFromAssetValue:bgAsset];
    if (bgImage || ([bgAsset isKindOfClass:NSString.class] && [(NSString *)bgAsset hasPrefix:TS_OBF_NS("https://")])) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:bgImage];
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.alpha = bgImage ? MIN(1.0, MAX(0.15, [config geometryNumberForKey:@"backgroundImageOpacity" fallback:1.0])) : 0.0;
        [view addSubview:imageView];
        if (!bgImage) [self loadRemoteImage:bgAsset intoImageView:imageView];
        [NSLayoutConstraint activateConstraints:@[
            [imageView.topAnchor constraintEqualToAnchor:view.topAnchor],
            [imageView.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
            [imageView.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [imageView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
        ]];
        // Dim layer so text remains readable over photo backgrounds.
        UIView *dim = [[UIView alloc] initWithFrame:CGRectZero];
        dim.translatesAutoresizingMaskIntoConstraints = NO;
        dim.backgroundColor = [[config colorForKey:@"background" fallback:UIColor.blackColor] colorWithAlphaComponent:0.45];
        [view addSubview:dim];
        [NSLayoutConstraint activateConstraints:@[
            [dim.topAnchor constraintEqualToAnchor:view.topAnchor],
            [dim.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
            [dim.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [dim.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
        ]];
    }
    return view;
}

+ (UIView *)logoViewWithConfig:(TserverUIConfig *)config {
    id logoAsset = config.assets[@"logo"] ?: config.assets[@"logoUrl"] ?: config.assets[@"icon"];
    UIImage *logo = [self imageFromAssetValue:logoAsset];
    BOOL isRemoteLogo = [logoAsset isKindOfClass:NSString.class] && [(NSString *)logoAsset hasPrefix:TS_OBF_NS("https://")];
    if (!logo && !isRemoteLogo) return nil;
    CGFloat size = MIN(96.0, MAX(28.0, [config geometryNumberForKey:@"logoSize" fallback:52.0]));
    UIImageView *imageView = [[UIImageView alloc] initWithImage:logo];
    if (!logo && isRemoteLogo) [self loadRemoteImage:logoAsset intoImageView:imageView];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.layer.cornerRadius = MIN(18.0, size * 0.22);
    imageView.clipsToBounds = YES;
    [imageView.widthAnchor constraintEqualToConstant:size].active = YES;
    [imageView.heightAnchor constraintEqualToConstant:size].active = YES;
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectZero];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:imageView];
    [NSLayoutConstraint activateConstraints:@[
        [imageView.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor],
        [imageView.topAnchor constraintEqualToAnchor:wrap.topAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor]
    ]];
    return wrap;
}

+ (UIView *)cardViewWithConfig:(TserverUIConfig *)config {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [config colorForKey:@"card" fallback:[UIColor colorWithWhite:0.1 alpha:1.0]];
    card.layer.cornerRadius = [config radius];
    card.layer.masksToBounds = NO;

    // Optional card border from style.borderWidth / style.borderColor (hex).
    id borderWidthValue = config.style[@"borderWidth"];
    CGFloat borderWidth = [borderWidthValue respondsToSelector:@selector(doubleValue)] ? MAX(0.0, [borderWidthValue doubleValue]) : 0.0;
    if (borderWidth > 0.0) {
        card.layer.borderWidth = MIN(8.0, borderWidth);
        UIColor *borderColor = [config colorForKey:@"borderColor" fallback:[[config colorForKey:@"accent" fallback:[self compatPurple]] colorWithAlphaComponent:0.45]];
        // Allow style.borderColor as hex string via colorForKey; if missing use accent@0.45.
        id borderHex = config.style[@"borderColor"];
        if ([borderHex isKindOfClass:NSString.class] && [(NSString *)borderHex length] > 0) {
            borderColor = [config colorForKey:@"borderColor" fallback:borderColor];
        }
        card.layer.borderColor = borderColor.CGColor;
    }

    if ([config shadowEnabled]) {
        card.layer.shadowColor = UIColor.blackColor.CGColor;
        id shadowOpacityValue = config.style[@"shadowOpacity"];
        CGFloat shadowOpacity = [shadowOpacityValue respondsToSelector:@selector(doubleValue)] ? [shadowOpacityValue doubleValue] : 0.25;
        card.layer.shadowOpacity = (float)MIN(1.0, MAX(0.0, shadowOpacity));
        id shadowRadiusValue = config.style[@"shadowRadius"];
        CGFloat shadowRadius = [shadowRadiusValue respondsToSelector:@selector(doubleValue)] ? [shadowRadiusValue doubleValue] : 18.0;
        card.layer.shadowRadius = MIN(40.0, MAX(0.0, shadowRadius));
        card.layer.shadowOffset = CGSizeMake(0, 10);
    }
    return card;
}

+ (UIFont *)fontForConfig:(TserverUIConfig *)config key:(NSString *)key fallback:(UIFont *)fallback {
    CGFloat size = [config typographyNumberForKey:key fallback:fallback.pointSize];
    size = MIN(34.0, MAX(10.0, size));
    UIFont *font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    if ([UIFontMetrics class]) {
        font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:font];
    }
    return font;
}

+ (void)configureMultilineLabel:(UILabel *)label {
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.adjustsFontForContentSizeCategory = YES;
    label.adjustsFontSizeToFitWidth = NO;
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired
                                         forAxis:UILayoutConstraintAxisVertical];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired
                                         forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
}

+ (UILabel *)titleLabel:(NSString *)text config:(TserverUIConfig *)config {
    UILabel *label = [UILabel new];
    label.text = text ?: @"";
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [config colorForKey:@"text" fallback:UIColor.whiteColor];
    label.font = [self fontForConfig:config key:@"titleSize" fallback:[TserverTheme titleFont]];
    label.numberOfLines = 0;
    [self configureMultilineLabel:label];
    return label;
}

+ (UILabel *)subtitleLabel:(NSString *)text config:(TserverUIConfig *)config {
    UILabel *label = [UILabel new];
    label.text = text ?: @"";
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [config colorForKey:@"mutedText" fallback:[UIColor colorWithWhite:0.75 alpha:1.0]];
    label.font = [self fontForConfig:config key:@"subtitleSize" fallback:[TserverTheme subtitleFont]];
    label.numberOfLines = 0;
    [self configureMultilineLabel:label];
    return label;
}

+ (UILabel *)loadingTitleLabel:(NSString *)text config:(TserverUIConfig *)config {
    UILabel *label = [self titleLabel:text config:config];
    label.font = [TserverTheme loadingTitleFont];
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.82;
    return label;
}

+ (UILabel *)loadingSubtitleLabel:(NSString *)text config:(TserverUIConfig *)config {
    UILabel *label = [self subtitleLabel:text config:config];
    label.font = [TserverTheme loadingSubtitleFont];
    return label;
}

+ (UILabel *)errorLabel:(NSString *)text config:(TserverUIConfig *)config {
    UILabel *label = [UILabel new];
    label.text = text ?: @"";
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [config colorForKey:@"danger" fallback:[self compatRed]];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.numberOfLines = 0;
    label.hidden = text.length == 0;
    return label;
}

+ (UIButton *)primaryButton:(NSString *)text config:(TserverUIConfig *)config {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:text ?: @"OK" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [self fontForConfig:config key:@"buttonSize" fallback:[TserverTheme buttonFont]];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.accessibilityLabel = text ?: @"OK";
    button.backgroundColor = [config colorForKey:@"accent" fallback:[UIColor colorWithRed:0.49 green:0.23 blue:0.93 alpha:1.0]];
    button.layer.cornerRadius = MAX(8.0, [config radius] * 0.55);
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    [self addTouchFeedbackToButton:button];
    return button;
}

+ (UIButton *)secondaryButton:(NSString *)text config:(TserverUIConfig *)config {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:text ?: @"OK" forState:UIControlStateNormal];
    [button setTitleColor:[config colorForKey:@"text" fallback:UIColor.whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [self fontForConfig:config key:@"buttonSize" fallback:[TserverTheme buttonFont]];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.accessibilityLabel = text ?: @"OK";
    button.backgroundColor = [[config colorForKey:@"mutedText" fallback:UIColor.lightGrayColor] colorWithAlphaComponent:0.16];
    button.layer.cornerRadius = MAX(8.0, [config radius] * 0.55);
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    [self addTouchFeedbackToButton:button];
    return button;
}

+ (UITextField *)keyTextField:(NSString *)placeholder config:(TserverUIConfig *)config {
    TserverKeyTextField *field = [[TserverKeyTextField alloc] initWithFrame:CGRectZero];
    field.placeholder = placeholder ?: @"TSRV-XXXX-XXXX";
    field.font = [self fontForConfig:config key:@"inputSize" fallback:[TserverTheme inputFont]];
    field.adjustsFontForContentSizeCategory = YES;
    field.accessibilityLabel = @"Mã license";
    field.accessibilityHint = @"Nhập mã key để kích hoạt";
    field.textColor = [config colorForKey:@"text" fallback:UIColor.whiteColor];
    field.backgroundColor = [[config colorForKey:@"background" fallback:UIColor.blackColor] colorWithAlphaComponent:0.26];
    field.layer.cornerRadius = 10;
    field.layer.borderWidth = 1;
    field.layer.borderColor = [[config colorForKey:@"mutedText" fallback:UIColor.grayColor] colorWithAlphaComponent:0.35].CGColor;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.returnKeyType = UIReturnKeyDone;
    NSDictionary *attrs = @{NSForegroundColorAttributeName: [config colorForKey:@"mutedText" fallback:UIColor.grayColor]};
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:field.placeholder attributes:attrs];
    return field;
}

+ (UIView *)spinnerContainerWithConfig:(TserverUIConfig *)config {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.color = [config colorForKey:@"accent" fallback:UIColor.whiteColor];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [spinner.topAnchor constraintEqualToAnchor:container.topAnchor constant:4],
        [spinner.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-4],
        [container.heightAnchor constraintEqualToConstant:38]
    ]];
    return container;
}

/// Font Awesome Free 6 Solid codepoints for common gate icons (fa-*).
/// Prefer registered FA font when present in host app / dylib bundle; else SF Symbols.
+ (NSString *)faGlyphFromCodepoint:(unichar)code {
    return [NSString stringWithCharacters:&code length:1];
}

+ (NSString *)fontAwesomeGlyphForName:(NSString *)iconName {
    NSString *raw = [iconName isKindOfClass:NSString.class] ? iconName.lowercaseString : @"";
    raw = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    raw = [raw stringByReplacingOccurrencesOfString:@"fa-solid" withString:@""];
    raw = [raw stringByReplacingOccurrencesOfString:@"fas " withString:@""];
    raw = [raw stringByReplacingOccurrencesOfString:@" " withString:@"-"];
    while ([raw hasPrefix:@"-"]) raw = [raw substringFromIndex:1];
    if (![raw hasPrefix:@"fa-"] && raw.length > 0) raw = [@"fa-" stringByAppendingString:raw];

    // FA6 free solid unicode (BMP PUA). Keep names in sync with web authUiIcons.ts.
    static NSDictionary<NSString *, NSNumber *> *codeMap;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        codeMap = @{
            @"fa-key": @0xf084,
            @"fa-shield-halved": @0xf3ed,
            @"fa-shield": @0xf132,
            @"fa-circle-check": @0xf058,
            @"fa-check": @0xf00c,
            @"fa-bolt": @0xf0e7,
            @"fa-power-off": @0xf011,
            @"fa-box-archive": @0xf187,
            @"fa-box": @0xf466,
            @"fa-triangle-exclamation": @0xf071,
            @"fa-exclamation": @0xf12a,
            @"fa-clock-rotate-left": @0xf1da,
            @"fa-clock": @0xf017,
            @"fa-screwdriver-wrench": @0xf7d9,
            @"fa-wrench": @0xf0ad,
            @"fa-gear": @0xf013,
            @"fa-arrow-up-from-bracket": @0xf0ee,
            @"fa-arrow-up": @0xf062,
            @"fa-ban": @0xf05e,
            @"fa-mobile-screen-button": @0xf3cd,
            @"fa-mobile": @0xf3cd,
            @"fa-wifi": @0xf1eb,
            @"fa-server": @0xf233,
            @"fa-lock": @0xf023,
            @"fa-unlock": @0xf09c,
            @"fa-user-shield": @0xf505,
            @"fa-fingerprint": @0xf577,
            @"fa-id-card": @0xf2c2,
            @"fa-gamepad": @0xf11b,
            @"fa-crown": @0xf521,
            @"fa-star": @0xf005,
            @"fa-heart": @0xf004,
            @"fa-circle-info": @0xf05a,
            @"fa-circle-xmark": @0xf057,
            @"fa-rotate": @0xf2f1,
            @"fa-spinner": @0xf110,
            @"fa-cloud": @0xf0c2,
            @"fa-download": @0xf019
        };
    });

    NSNumber *code = codeMap[raw];
    if (code) return [self faGlyphFromCodepoint:(unichar)code.unsignedShortValue];

    NSString *fuzzy = nil;
    if ([raw containsString:@"key"]) fuzzy = @"fa-key";
    else if ([raw containsString:@"shield"]) fuzzy = @"fa-shield-halved";
    else if ([raw containsString:@"check"]) fuzzy = @"fa-circle-check";
    else if ([raw containsString:@"power"]) fuzzy = @"fa-power-off";
    else if ([raw containsString:@"box"]) fuzzy = @"fa-box-archive";
    else if ([raw containsString:@"triangle"] || [raw containsString:@"exclamation"]) fuzzy = @"fa-triangle-exclamation";
    else if ([raw containsString:@"clock"]) fuzzy = @"fa-clock-rotate-left";
    else if ([raw containsString:@"bolt"]) fuzzy = @"fa-bolt";
    else if ([raw containsString:@"wrench"] || [raw containsString:@"gear"]) fuzzy = @"fa-screwdriver-wrench";
    else if ([raw containsString:@"arrow"]) fuzzy = @"fa-arrow-up-from-bracket";
    else if ([raw containsString:@"ban"]) fuzzy = @"fa-ban";
    else if ([raw containsString:@"wifi"]) fuzzy = @"fa-wifi";
    else if ([raw containsString:@"server"]) fuzzy = @"fa-server";
    else fuzzy = @"fa-circle-info";
    code = codeMap[fuzzy] ?: @0xf05a;
    return [self faGlyphFromCodepoint:(unichar)code.unsignedShortValue];
}

+ (NSString *)sfSymbolNameForIconName:(NSString *)iconName {
    NSString *raw = [iconName isKindOfClass:NSString.class] ? iconName.lowercaseString : @"";
    if ([raw containsString:@"key"] || [raw containsString:@"lock"]) return @"key.fill";
    if ([raw containsString:@"shield"]) return @"shield.fill";
    if ([raw containsString:@"check"] || [raw containsString:@"valid"]) return @"checkmark.circle.fill";
    if ([raw containsString:@"bolt"] || [raw containsString:@"loading"] || [raw containsString:@"spinner"]) return @"bolt.fill";
    if ([raw containsString:@"power"]) return @"power";
    if ([raw containsString:@"box"] || [raw containsString:@"package"]) return @"shippingbox.fill";
    if ([raw containsString:@"triangle"] || [raw containsString:@"exclamation"] || [raw containsString:@"warn"]) return @"exclamationmark.triangle.fill";
    if ([raw containsString:@"clock"] || [raw containsString:@"rotate"]) return @"clock.arrow.circlepath";
    if ([raw containsString:@"wrench"] || [raw containsString:@"gear"] || [raw containsString:@"maintenance"]) return @"wrench.and.screwdriver.fill";
    if ([raw containsString:@"arrow"] || [raw containsString:@"update"] || [raw containsString:@"download"]) return @"arrow.up.circle.fill";
    if ([raw containsString:@"ban"] || [raw containsString:@"revoke"]) return @"nosign";
    if ([raw containsString:@"mobile"] || [raw containsString:@"device"]) return @"iphone";
    if ([raw containsString:@"wifi"] || [raw containsString:@"network"]) return @"wifi";
    if ([raw containsString:@"server"]) return @"server.rack";
    if ([raw containsString:@"game"]) return @"gamecontroller.fill";
    if ([raw containsString:@"star"]) return @"star.fill";
    if ([raw containsString:@"heart"]) return @"heart.fill";
    if ([raw containsString:@"crown"]) return @"crown.fill";
    if ([raw containsString:@"user"]) return @"person.crop.circle.fill";
    return @"circle.fill";
}

+ (UIFont *)fontAwesomeFontOfSize:(CGFloat)size {
    // Prefer FA font embedded in libAPIClient.a (registered at runtime) or host app.
    Class fa = NSClassFromString(@"TserverFontAwesome");
    typedef UIFont *(*FAFontIMP)(id, SEL, CGFloat);
    SEL sel = NSSelectorFromString(@"solidFontOfSize:");
    if (fa && [fa respondsToSelector:sel]) {
        FAFontIMP imp = (FAFontIMP)[fa methodForSelector:sel];
        if (imp) {
            UIFont *font = imp(fa, sel, size);
            if (font) return font;
        }
    }
    NSArray<NSString *> *candidates = @[
        @"FontAwesome6Free-Solid",
        @"Font Awesome 6 Free",
        @"FontAwesome6FreeSolid",
        @"FontAwesome5Free-Solid",
        @"Font Awesome 5 Free Solid",
        @"FontAwesome"
    ];
    for (NSString *name in candidates) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) return font;
    }
    return nil;
}

+ (UIView *)iconViewForName:(NSString *)iconName config:(TserverUIConfig *)config {
    CGFloat size = MAX(28.0, [config geometryNumberForKey:@"iconSize" fallback:42.0]);
    size = MIN(72.0, size);
    UIColor *accent = [config colorForKey:@"accent" fallback:[self compatBlue]];

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [accent colorWithAlphaComponent:0.16];
    container.layer.cornerRadius = size * 0.5;
    container.layer.borderWidth = 1.0;
    container.layer.borderColor = [accent colorWithAlphaComponent:0.45].CGColor;

    UIView *glyphView = nil;
    CGFloat glyphSize = MAX(14.0, size * 0.48);

    // 1) Prefer Font Awesome glyph when FA font is embedded in libAPIClient.a
    //    (TserverFontAwesome registers CTFont from linked bytes) or host app.
    UIFont *faFont = [self fontAwesomeFontOfSize:glyphSize];
    if (faFont) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textAlignment = NSTextAlignmentCenter;
        label.text = [self fontAwesomeGlyphForName:iconName];
        label.textColor = accent;
        label.font = faFont;
        glyphView = label;
    }

    // 2) SF Symbols fallback via runtime class/selector check.
    // Do NOT use @available here: Clang emits ___isOSVersionAtLeast which the
    // consumer dylib may not link when pulling symbols from a static libAPIClient.a.
    if (!glyphView) {
        Class cfgClass = NSClassFromString(@"UIImageSymbolConfiguration");
        if (cfgClass && [UIImage respondsToSelector:@selector(systemImageNamed:withConfiguration:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
            NSString *symbolName = [self sfSymbolNameForIconName:iconName];
            id cfg = [cfgClass configurationWithPointSize:glyphSize weight:UIImageSymbolWeightBold];
            UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
            if (image) {
                UIImageView *imageView =
                    [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                imageView.translatesAutoresizingMaskIntoConstraints = NO;
                imageView.tintColor = accent;
                imageView.contentMode = UIViewContentModeScaleAspectFit;
                glyphView = imageView;
            }
#pragma clang diagnostic pop
        }
    }

    // 3) Last resort: FA unicode with system font (may show tofu if FA not present — still better than wrong emoji).
    if (!glyphView) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textAlignment = NSTextAlignmentCenter;
        label.text = [self fontAwesomeGlyphForName:iconName];
        label.textColor = accent;
        label.font = [UIFont systemFontOfSize:glyphSize weight:UIFontWeightBold];
        glyphView = label;
    }

    [container addSubview:glyphView];
    [NSLayoutConstraint activateConstraints:@[
        [container.widthAnchor constraintEqualToConstant:size],
        [container.heightAnchor constraintEqualToConstant:size],
        [glyphView.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [glyphView.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [glyphView.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor constant:4.0],
        [glyphView.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-4.0],
        [glyphView.topAnchor constraintGreaterThanOrEqualToAnchor:container.topAnchor constant:4.0],
        [glyphView.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-4.0]
    ]];
    if ([glyphView isKindOfClass:UIImageView.class]) {
        [glyphView.widthAnchor constraintLessThanOrEqualToConstant:glyphSize + 4.0].active = YES;
        [glyphView.heightAnchor constraintLessThanOrEqualToConstant:glyphSize + 4.0].active = YES;
    }
    return container;
}

+ (void)addTouchFeedbackToButton:(UIButton *)button {
    [button addTarget:self action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(touchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
}

+ (void)touchDown:(UIButton *)button {
    button.alpha = 0.78;
    button.transform = CGAffineTransformMakeScale(0.985, 0.985);
}

+ (void)touchUp:(UIButton *)button {
    [UIView animateWithDuration:0.15 animations:^{
        button.alpha = 1.0;
        button.transform = CGAffineTransformIdentity;
    }];
}

@end
