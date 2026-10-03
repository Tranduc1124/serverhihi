#import "TserverSimpleUiPack.h"
#import "TserverGateUI.h"
#import "../CyberTerminalPrivate.h"

void TserverCyberTerminalBuildResult(TserverSimpleUiPackBase *pack) {
    BOOL compact = [pack isCompactLandscape];
    BOOL valid = [pack.context.status hasPrefix:@"VALID"] || [pack.context.status isEqualToString:@"OFFLINE_GRACE_VALID"];
    BOOL loading = [pack.context.status isEqualToString:@"LOADING"];
    BOOL updateRequired = [pack.context.status isEqualToString:@"UPDATE_REQUIRED"];
    NSString *updateUrl = [pack.context.result[@"updateUrl"] isKindOfClass:NSString.class] ? pack.context.result[@"updateUrl"] : nil;
    NSString *fallbackTitle = loading ? @"Dang kiem tra" : (valid ? @"Key hop le" : (updateRequired ? @"Can cap nhat" : @"Khong the tiep tuc"));
    NSString *message = [pack.context.result[@"message"] isKindOfClass:NSString.class] ? pack.context.result[@"message"] : nil;
    NSString *title = [pack screenString:@"title" fallback:fallbackTitle];
    // Prefer live server message (custom maintenance / error text) over pack screen defaults.
    NSString *subtitle = (message.length > 0)
        ? message
        : [pack screenString:@"subtitle" fallback:(valid ? @"Session verified" : (updateRequired ? @"Vui long cap nhat de tiep tuc." : @"Input or network failure"))];
    NSString *buttonText = [pack screenString:@"buttonText" fallback:(valid ? @"Tiep tuc" : (updateRequired ? @"Cap nhat" : @"Thu lai"))];
    NSString *tapHint = [pack screenString:@"tapHint" fallback:@"Cham de tiep tuc"];
    // A missing URL scheme is a build defect, not an auth outcome: name it, and
    // replace whatever retry/change-key copy the pack picked with a Close.
    BOOL fatalConfigError = TserverGateResultIsFatalConfigError(pack.context.result);
    if (fatalConfigError) {
        title = [pack screenString:@"title" fallback:@" Cau hinh app chua dung"];
        buttonText = [pack screenString:@"closeButtonText" fallback:TserverGateFatalConfigCloseButtonTitle()];
    }

    UIColor *tone = valid ? [pack successColor] : (loading ? [pack accentColor] : [pack dangerColor]);
    TCTAppendLine(pack, valid ? @"> AUTH_OK" : (loading ? @"> AUTH_RUNNING" : (updateRequired ? @"> UPDATE_REQUIRED" : @"> AUTH_FAIL")), tone);
    if (compact) {
        TCTAppendLine(pack, [NSString stringWithFormat:@"> %@", title], tone);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> %@", subtitle], [pack mutedTextColor]);
    } else {
        TCTAppendLine(pack, [NSString stringWithFormat:@"> code = %@", pack.context.status ?: @"UNKNOWN"], [pack mutedTextColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> msg  = %@", title], tone);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> info = %@", subtitle], [pack mutedTextColor]);
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

    [inner addArrangedSubview:TCTLine(pack, valid ? @"> session_verified = true" : @"> session_verified = false", tone, compact ? 10 : 11)];
    if (!compact) {
        [inner addArrangedSubview:TCTLine(pack, [NSString stringWithFormat:@"> summary: %@", subtitle], [pack mutedTextColor], 11)];
    }

    TserverUiContinueMode mode = [pack resolvedContinueMode];
    if (valid) {
        // Report what was authorized before asking the user to continue.
        NSDictionary *licenseInfo = TserverGateLicenseInfoFromResult(pack.context.result);
        if (licenseInfo.count > 0) {
            [inner addArrangedSubview:TCTLine(pack, @"> license_granted = true", tone, compact ? 10 : 11)];
            [inner addArrangedSubview:TserverGateLicenseInfoView(licenseInfo,
                                                                 [pack textColor],
                                                                 [pack mutedTextColor],
                                                                 [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold])];
        }
        if (mode == TserverUiContinueModeButton) {
            UIButton *button = [pack button:buttonText action:@selector(continueFromOverlay)];
            button.titleLabel.font = TCTFont(compact ? 13 : 14);
            button.layer.cornerRadius = 10;
            [inner addArrangedSubview:button];
        } else {
            [inner addArrangedSubview:TCTLine(pack, [NSString stringWithFormat:@"> %@", tapHint], [pack mutedTextColor], compact ? 10 : 11)];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:pack action:@selector(continueFromOverlay)];
            [pack.root addGestureRecognizer:tap];
        }
    } else if (updateRequired) {
        UIButton *button = [pack button:buttonText action:@selector(openUpdateTapped:)];
        if (updateUrl.length > 0) button.accessibilityValue = updateUrl;
        button.titleLabel.font = TCTFont(compact ? 13 : 14);
        button.layer.cornerRadius = 10;
        [inner addArrangedSubview:button];
    } else if (fatalConfigError) {
        // Single Close button that quits. No retry, no key entry: this app can
        // never complete Device Verify, so any other action is a dead end.
        UIButton *button = [pack button:buttonText action:@selector(closeAndTerminateTapped)];
        button.titleLabel.font = TCTFont(compact ? 13 : 14);
        button.layer.cornerRadius = 10;
        [inner addArrangedSubview:button];
    } else if (!loading) {
        SEL action = (pack.context.showNeedKey || !pack.context.retry) ? @selector(changeKeyTapped) : @selector(retryTapped);
        NSString *fallbackActionTitle = pack.context.showNeedKey ? @"Doi key khac" : @"Thu lai";
        NSString *actionTitle = (buttonText.length > 0 && ![buttonText isEqualToString:@"Thu lai"]) ? buttonText : fallbackActionTitle;
        UIButton *button = [pack button:actionTitle action:action];
        button.titleLabel.font = TCTFont(compact ? 13 : 14);
        button.layer.cornerRadius = 10;
        [inner addArrangedSubview:button];

        [inner addArrangedSubview:TCTLine(pack, @"> Cham man hinh de doi key", [pack mutedTextColor], compact ? 10 : 11)];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:pack action:action];
        [pack.root addGestureRecognizer:tap];
    }

    [pack.stack addArrangedSubview:panel];
}
