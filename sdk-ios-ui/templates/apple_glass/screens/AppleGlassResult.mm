#import "TserverSimpleUiPack.h"
#import "TserverGateUI.h"
#import "../AppleGlassPrivate.h"

void TserverAppleGlassBuildResult(TserverSimpleUiPackBase *pack) {
    BOOL valid = [pack.context.status hasPrefix:@"VALID"] || [pack.context.status isEqualToString:@"OFFLINE_GRACE_VALID"];
    BOOL updateRequired = [pack.context.status isEqualToString:@"UPDATE_REQUIRED"];
    NSString *updateUrl = [pack.context.result[@"updateUrl"] isKindOfClass:NSString.class] ? pack.context.result[@"updateUrl"] : nil;
    NSString *message = [pack.context.result[@"message"] isKindOfClass:NSString.class] ? pack.context.result[@"message"] : nil;

    NSString *fallbackTitle = valid ? @"Đã kích hoạt" : (updateRequired ? @"Yêu cầu cập nhật" : @"Không thể kích hoạt");
    NSString *title = [pack screenString:@"title" fallback:fallbackTitle];
    NSString *subtitle = (message.length > 0)
        ? message
        : [pack screenString:@"subtitle" fallback:(valid ? @"Bản quyền hợp lệ." : @"Vui lòng thử lại sau.")];
    NSString *buttonText = [pack screenString:@"buttonText" fallback:(valid ? @"Tiếp tục" : (updateRequired ? @"Cập nhật" : @"Thử lại"))];
    // A missing URL scheme is a build defect, not an auth outcome: name it, and
    // replace whatever retry/change-key copy the pack picked with a Close.
    BOOL fatalConfigError = TserverGateResultIsFatalConfigError(pack.context.result);
    if (fatalConfigError) {
        title = [pack screenString:@"title" fallback:@"Cấu hình app chưa đúng"];
        buttonText = [pack screenString:@"closeButtonText" fallback:TserverGateFatalConfigCloseButtonTitle()];
    }

    // Color tone
    UIColor *tone = nil;
    if (valid) {
        tone = TAGSystemGreen();
    } else if (updateRequired) {
        tone = TAGSystemBlue();
    } else {
        tone = TAGSystemRed();
    }

    UILabel *titleLabel = [pack label:title size:17 weight:UIFontWeightBold];
    titleLabel.textColor = tone;
    [pack.stack addArrangedSubview:titleLabel];

    UILabel *subtitleLabel = [pack label:subtitle size:13 weight:UIFontWeightRegular];
    subtitleLabel.textColor = TAGSecondaryLabelColor();
    [pack.stack addArrangedSubview:subtitleLabel];

    if (valid) {
        // Inset Grouped Info Box
        NSDictionary *license = [pack.context.result[@"license"] isKindOfClass:NSDictionary.class] ? pack.context.result[@"license"] : nil;
        if (license) {
            UIView *grouped = TAGGroupedContainer();
            UIStackView *inner = [UIStackView new];
            inner.translatesAutoresizingMaskIntoConstraints = NO;
            inner.axis = UILayoutConstraintAxisVertical;
            inner.spacing = 8.0;
            [grouped addSubview:inner];

            [NSLayoutConstraint activateConstraints:@[
                [inner.topAnchor constraintEqualToAnchor:grouped.topAnchor constant:10.0],
                [inner.bottomAnchor constraintEqualToAnchor:grouped.bottomAnchor constant:-10.0],
                [inner.leadingAnchor constraintEqualToAnchor:grouped.leadingAnchor constant:12.0],
                [inner.trailingAnchor constraintEqualToAnchor:grouped.trailingAnchor constant:-12.0]
            ]];

            NSString *maskedKey = [license[@"maskedKey"] isKindOfClass:NSString.class] ? license[@"maskedKey"] : nil;
            if (!maskedKey) maskedKey = [license[@"licenseKey"] isKindOfClass:NSString.class] ? license[@"licenseKey"] : @"••••••••";
            [inner addArrangedSubview:TAGInfoRow(@"License Key", maskedKey, TAGLabelColor(), TAGSecondaryLabelColor())];

            NSNumber *remaining = [license[@"remainingSeconds"] respondsToSelector:@selector(integerValue)] ? license[@"remainingSeconds"] : nil;
            if (remaining) {
                NSInteger sec = [remaining integerValue];
                NSInteger days = sec / 86400;
                NSInteger hours = (sec % 86400) / 3600;
                NSString *timeStr = [NSString stringWithFormat:@"%ld ngày %ld giờ", (long)days, (long)hours];
                if (days <= 0) timeStr = [NSString stringWithFormat:@"%ld giờ", (long)hours];
                [inner addArrangedSubview:TAGInfoRow(@"Thời hạn", timeStr, TAGLabelColor(), TAGSecondaryLabelColor())];
            }

            [pack.stack addArrangedSubview:grouped];
        }

        // Report what was authorized before asking the user to continue.
        NSDictionary *licenseInfo = TserverGateLicenseInfoFromResult(pack.context.result);
        if (licenseInfo.count > 0) {
            [pack.stack addArrangedSubview:TserverGateLicenseInfoView(licenseInfo,
                                                                      TAGLabelColor(),
                                                                      TAGSecondaryLabelColor(),
                                                                      [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold])];
        }

        TserverUiContinueMode mode = [pack resolvedContinueMode];
        if (mode == TserverUiContinueModeButton) {
            UIButton *btn = TAGActionButton(pack, buttonText, tone, @selector(continueFromOverlay));
            [pack.stack addArrangedSubview:btn];
        } else {
            UILabel *hint = [pack label:[pack screenString:@"tapHint" fallback:@"Chạm để tiếp tục"] size:12 weight:UIFontWeightMedium];
            hint.textColor = TAGSecondaryLabelColor();
            [pack.stack addArrangedSubview:hint];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:pack action:@selector(continueFromOverlay)];
            [pack.root addGestureRecognizer:tap];
        }
    } else if (updateRequired) {
        UIButton *btn = TAGActionButton(pack, buttonText, tone, @selector(openUpdateTapped:));
        if (updateUrl.length > 0) btn.accessibilityValue = updateUrl;
        [pack.stack addArrangedSubview:btn];
    } else if (fatalConfigError) {
        // Single Close button that quits. No retry, no key entry: this app can
        // never complete Device Verify, so any other action is a dead end.
        UIButton *btn = TAGActionButton(pack, buttonText, tone, @selector(closeAndTerminateTapped));
        [pack.stack addArrangedSubview:btn];
    } else {
        SEL action = (pack.context.showNeedKey || !pack.context.retry) ? @selector(changeKeyTapped) : @selector(retryTapped);
        NSString *fallbackActionTitle = pack.context.showNeedKey ? @"Đổi key khác" : @"Thử lại";
        NSString *actionTitle = (buttonText.length > 0 && ![buttonText isEqualToString:@"Thử lại"]) ? buttonText : fallbackActionTitle;
        UIButton *btn = TAGActionButton(pack, actionTitle, tone, action);
        [pack.stack addArrangedSubview:btn];

        UILabel *hint = [pack label:[pack screenString:@"tapHint" fallback:@"Chạm vào màn hình để đổi key"] size:12 weight:UIFontWeightMedium];
        hint.textColor = TAGSecondaryLabelColor();
        [pack.stack addArrangedSubview:hint];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:pack action:action];
        [pack.root addGestureRecognizer:tap];
    }
}
