#import "TserverSimpleUiPack.h"
#import "../CyberTerminalPrivate.h"

void TserverCyberTerminalBuildDeviceVerify(TserverSimpleUiPackBase *pack) {
    BOOL compact = [pack isCompactLandscape];
    NSString *title = [pack screenString:@"title" fallback:@"Xac minh thiet bi"];
    NSString *subtitle = [pack screenString:@"subtitle" fallback:@"Can UUID/profile de tiep tuc"];
    NSString *buttonText = [pack screenString:@"buttonText" fallback:@"Lay UUID"];

    if (compact) {
        TCTAppendLine(pack, @"> require uuid_profile", [pack accentColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> %@", title], [pack mutedTextColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> %@", subtitle], [pack mutedTextColor]);
    } else {
        TCTAppendLine(pack, @"> detect device_identity", [pack accentColor]);
        TCTAppendLine(pack, @"> require uuid_profile", [pack accentColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> task: %@", title], [pack mutedTextColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> detail: %@", subtitle], [pack mutedTextColor]);
    }

    UIView *panel = [UIView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.34];
    panel.layer.cornerRadius = compact ? 10 : 12;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [[pack accentColor] colorWithAlphaComponent:0.35].CGColor;

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

    if (compact) {
        [inner addArrangedSubview:TCTLine(pack, @"> open safari → install profile", [pack mutedTextColor], 10)];
    } else {
        [inner addArrangedSubview:TCTLine(pack, @"> pipeline:", [pack accentColor], 11)];
        [inner addArrangedSubview:TCTLine(pack, @"  1) open safari verify page", [pack mutedTextColor], 11)];
        [inner addArrangedSubview:TCTLine(pack, @"  2) allow + install profile", [pack mutedTextColor], 11)];
        [inner addArrangedSubview:TCTLine(pack, @"  3) sync uuid -> app", [pack mutedTextColor], 11)];
    }

    UIButton *button = [pack button:buttonText action:@selector(uuidTapped)];
    button.titleLabel.font = TCTFont(compact ? 13 : 14);
    button.layer.cornerRadius = 10;
    [inner addArrangedSubview:button];

    [pack.stack addArrangedSubview:panel];
}
