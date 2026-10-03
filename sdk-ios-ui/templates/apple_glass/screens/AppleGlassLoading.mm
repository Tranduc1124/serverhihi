#import "TserverSimpleUiPack.h"
#import "../AppleGlassPrivate.h"

void TserverAppleGlassBuildLoading(TserverSimpleUiPackBase *pack) {
    NSString *title = [pack screenString:@"title" fallback:@"Đang kiểm tra"];
    NSString *subtitle = [pack screenString:@"subtitle" fallback:@"Vui lòng chờ trong giây lát…"];

    UILabel *titleLabel = [pack label:title size:17 weight:UIFontWeightBold];
    titleLabel.textColor = TAGLabelColor();
    [pack.stack addArrangedSubview:titleLabel];

    UILabel *subtitleLabel = [pack label:subtitle size:13 weight:UIFontWeightRegular];
    subtitleLabel.textColor = TAGSecondaryLabelColor();
    [pack.stack addArrangedSubview:subtitleLabel];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    UIActivityIndicatorView *indicator = nil;
    if (TAGIsIOS13OrLater()) {
        indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        indicator.color = TAGSystemBlue();
    } else {
        indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    }
#pragma clang diagnostic pop
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    [indicator startAnimating];

    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:indicator];
    [NSLayoutConstraint activateConstraints:@[
        [indicator.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [indicator.topAnchor constraintEqualToAnchor:box.topAnchor constant:12.0],
        [indicator.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8.0],
        [box.heightAnchor constraintEqualToConstant:56.0]
    ]];
    [pack.stack addArrangedSubview:box];
}
