#import "TserverSimpleUiPack.h"
#import "../CyberTerminalPrivate.h"
#import "../../../src/TserverKeyEntryAssist.h"

void TserverCyberTerminalBuildKeyEntry(TserverSimpleUiPackBase *pack) {
    BOOL compact = [pack isCompactLandscape];
    NSString *title = [pack screenString:@"title" fallback:@"Nhap key"];
    NSString *subtitle = [pack screenString:@"subtitle" fallback:@"Nhap key de tiep tuc"];
    NSString *placeholder = [pack screenString:@"placeholder" fallback:@"TSRV-XXXX-XXXX"];
    NSString *buttonText = [pack screenString:@"buttonText" fallback:@"Kich hoat"];

    if (compact) {
        TCTAppendLine(pack, @"> open /dev/license", [pack accentColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> %@", title], [pack mutedTextColor]);
    } else {
        TCTAppendLine(pack, @"> open /dev/license", [pack accentColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> prompt \"%@\"", title], [pack mutedTextColor]);
        TCTAppendLine(pack, [NSString stringWithFormat:@"> hint \"%@\"", subtitle], [pack mutedTextColor]);
        TCTAppendLine(pack, @"> waiting_for_input...", [pack accentColor]);
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

    [inner addArrangedSubview:TCTLine(pack, @"> echo $LICENSE_KEY", [pack accentColor], compact ? 10 : 11)];

    pack.keyField = [UITextField new];
    pack.keyField.placeholder = placeholder;
    pack.keyField.font = TCTFont(compact ? 13 : 14);
    pack.keyField.textAlignment = NSTextAlignmentLeft;
    pack.keyField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    pack.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    pack.keyField.backgroundColor = [[pack cardColor] colorWithAlphaComponent:0.55];
    pack.keyField.textColor = [pack textColor];
    pack.keyField.layer.cornerRadius = 10;
    pack.keyField.layer.borderWidth = 1;
    pack.keyField.layer.borderColor = [[pack accentColor] colorWithAlphaComponent:0.55].CGColor;
    pack.keyField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    pack.keyField.leftViewMode = UITextFieldViewModeAlways;
    pack.keyField.accessibilityLabel = @"Ma license";
    [pack.keyField.heightAnchor constraintEqualToConstant:(compact ? 44 : 48)].active = YES;
    [inner addArrangedSubview:pack.keyField];

    UIButton *paste = [pack button:@"Dán từ clipboard" action:@selector(pasteKeyFromClipboardTapped)];
    paste.titleLabel.font = TCTFont(compact ? 12 : 13);
    paste.backgroundColor = [[pack accentColor] colorWithAlphaComponent:0.20];
    [paste setTitleColor:[pack textColor] forState:UIControlStateNormal];
    paste.layer.cornerRadius = 10;
    paste.hidden = YES;
    [TserverKeyEntryAssist bindPasteButton:paste toField:pack.keyField];
    [inner addArrangedSubview:paste];

    UILabel *hint = TCTLine(pack, @"", [pack mutedTextColor], compact ? 10 : 11);
    hint.hidden = YES;
    [TserverKeyEntryAssist bindHintLabel:hint toField:pack.keyField];
    [inner addArrangedSubview:hint];

    UIButton *button = [pack button:buttonText action:@selector(submitKeyTapped)];
    button.titleLabel.font = TCTFont(compact ? 13 : 14);
    button.layer.cornerRadius = 10;
    [inner addArrangedSubview:button];

    [pack.stack addArrangedSubview:panel];
}
