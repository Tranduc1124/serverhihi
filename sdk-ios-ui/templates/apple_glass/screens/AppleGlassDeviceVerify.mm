#import "TserverSimpleUiPack.h"
#import "../AppleGlassPrivate.h"

void TserverAppleGlassBuildDeviceVerify(TserverSimpleUiPackBase *pack) {
    NSString *title = [pack screenString:@"title" fallback:@"Xác minh thiết bị"];
    NSString *subtitle = [pack screenString:@"subtitle" fallback:@"Cài hồ sơ để xác nhận UUID máy an toàn."];
    NSString *buttonText = [pack screenString:@"buttonText" fallback:@"Cài hồ sơ UUID"];

    UILabel *titleLabel = [pack label:title size:17 weight:UIFontWeightBold];
    titleLabel.textColor = TAGLabelColor();
    [pack.stack addArrangedSubview:titleLabel];

    UILabel *subtitleLabel = [pack label:subtitle size:13 weight:UIFontWeightRegular];
    subtitleLabel.textColor = TAGSecondaryLabelColor();
    [pack.stack addArrangedSubview:subtitleLabel];

    // Inset Grouped Steps Container
    UIView *grouped = TAGGroupedContainer();
    UIStackView *inner = [UIStackView new];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    inner.axis = UILayoutConstraintAxisVertical;
    inner.spacing = 8.0;
    [grouped addSubview:inner];

    [NSLayoutConstraint activateConstraints:@[
        [inner.topAnchor constraintEqualToAnchor:grouped.topAnchor constant:12.0],
        [inner.bottomAnchor constraintEqualToAnchor:grouped.bottomAnchor constant:-12.0],
        [inner.leadingAnchor constraintEqualToAnchor:grouped.leadingAnchor constant:14.0],
        [inner.trailingAnchor constraintEqualToAnchor:grouped.trailingAnchor constant:-14.0]
    ]];

    NSArray<NSString *> *steps = @[
        @"1. Bấm Cài hồ sơ để mở Safari",
        @"2. Chọn Cho phép khi iOS hỏi tải về",
        @"3. Vào Cài đặt > Đã tải về > Cài đặt"
    ];
    for (NSString *step in steps) {
        UILabel *stepLabel = [UILabel new];
        stepLabel.translatesAutoresizingMaskIntoConstraints = NO;
        stepLabel.text = step;
        stepLabel.textColor = TAGSecondaryLabelColor();
        stepLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        stepLabel.numberOfLines = 0;
        [inner addArrangedSubview:stepLabel];
    }
    [pack.stack addArrangedSubview:grouped];

    // Primary Action Button (Apple Blue)
    UIButton *btn = TAGActionButton(pack, buttonText, TAGSystemBlue(), @selector(uuidTapped));
    [pack.stack addArrangedSubview:btn];
}
