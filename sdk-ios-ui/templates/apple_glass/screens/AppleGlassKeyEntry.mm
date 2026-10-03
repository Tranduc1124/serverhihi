#import "TserverSimpleUiPack.h"
#import "../AppleGlassPrivate.h"
#import "../../../src/TserverKeyEntryAssist.h"

void TserverAppleGlassBuildKeyEntry(TserverSimpleUiPackBase *pack) {
    NSString *title = [pack screenString:@"title" fallback:@"Kích hoạt bản quyền"];
    NSString *subtitle = [pack screenString:@"subtitle" fallback:@"Nhập license key để mở khóa tính năng."];
    NSString *placeholder = [pack screenString:@"placeholder" fallback:@"TSRV-XXXX-XXXX"];
    NSString *buttonText = [pack screenString:@"buttonText" fallback:@"Kích hoạt"];

    UILabel *titleLabel = [pack label:title size:17 weight:UIFontWeightBold];
    titleLabel.textColor = TAGLabelColor();
    [pack.stack addArrangedSubview:titleLabel];

    UILabel *subtitleLabel = [pack label:subtitle size:13 weight:UIFontWeightRegular];
    subtitleLabel.textColor = TAGSecondaryLabelColor();
    [pack.stack addArrangedSubview:subtitleLabel];

    // Native iOS Inset TextField
    pack.keyField = [UITextField new];
    pack.keyField.translatesAutoresizingMaskIntoConstraints = NO;
    pack.keyField.placeholder = placeholder;
    pack.keyField.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    pack.keyField.textAlignment = NSTextAlignmentCenter;
    pack.keyField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    pack.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
    pack.keyField.spellCheckingType = UITextSpellCheckingTypeNo;
    pack.keyField.clearButtonMode = UITextFieldViewModeWhileEditing;
    pack.keyField.backgroundColor = TAGInputBackgroundColor();
    pack.keyField.textColor = TAGLabelColor();
    pack.keyField.tintColor = TAGSystemBlue();
    pack.keyField.layer.cornerRadius = 10.0;
    pack.keyField.layer.borderWidth = 0.5;
    pack.keyField.layer.borderColor = TAGHairlineColor().CGColor;
    pack.keyField.accessibilityLabel = @"Mã license key";
    [pack.keyField.heightAnchor constraintEqualToConstant:44.0].active = YES;

    NSDictionary *placeholderAttrs = @{
        NSForegroundColorAttributeName: TAGPlaceholderTextColor(),
        NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightRegular]
    };
    pack.keyField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:placeholderAttrs];
    [pack.stack addArrangedSubview:pack.keyField];

    UIButton *paste = TAGActionButton(pack, @"Dán từ clipboard", TAGSecondaryLabelColor(), @selector(pasteKeyFromClipboardTapped));
    paste.layer.cornerRadius = 10.0;
    paste.hidden = YES;
    [TserverKeyEntryAssist bindPasteButton:paste toField:pack.keyField];
    [pack.stack addArrangedSubview:paste];

    UILabel *hint = [pack label:@"" size:12 weight:UIFontWeightMedium];
    hint.textColor = TAGSecondaryLabelColor();
    hint.numberOfLines = 0;
    hint.hidden = YES;
    [TserverKeyEntryAssist bindHintLabel:hint toField:pack.keyField];
    [pack.stack addArrangedSubview:hint];

    // Primary Action Button (Apple Blue)
    UIButton *btn = TAGActionButton(pack, buttonText, TAGSystemBlue(), @selector(submitKeyTapped));
    [pack.stack addArrangedSubview:btn];
}
