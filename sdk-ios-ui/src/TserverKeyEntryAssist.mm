#import "TserverKeyEntryAssist.h"
#import <objc/runtime.h>

/// Keys used to attach observers/state without subclassing anyone's views.
static const void *TserverKeyEntryPasteButtonKey = &TserverKeyEntryPasteButtonKey;
static const void *TserverKeyEntryPasteCandidateKey = &TserverKeyEntryPasteCandidateKey;
static const void *TserverKeyEntryHintLabelKey = &TserverKeyEntryHintLabelKey;
static const void *TserverKeyEntryFieldTokenKey = &TserverKeyEntryFieldTokenKey;

@implementation TserverKeyEntryAssist

#pragma mark - Text helpers

+ (NSString *)cleanedKeyText:(NSString *)text {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSMutableString *cleaned = [text mutableCopy];
    // People paste from chat apps, mails and terminals, so quotes, backticks and
    // stray whitespace are common. Strip only those, never the key body itself:
    // the prefix is configurable per plan/package and must survive untouched.
    NSArray<NSString *> *wrappers = @[@"\"", @"'", @"`", @"“", @"”", @"‘", @"’", @"[", @"]", @"(", @")"];
    for (NSString *wrapper in wrappers) {
        [cleaned replaceOccurrencesOfString:wrapper
                                 withString:@""
                                    options:NSLiteralSearch
                                      range:NSMakeRange(0, cleaned.length)];
    }
    NSCharacterSet *noise = [NSCharacterSet characterSetWithCharactersInString:
        @" \t\r\n\u00A0\u200B\u200C\u200D\uFEFF"];
    NSArray<NSString *> *parts = [cleaned componentsSeparatedByCharactersInSet:noise];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [kept addObject:part];
    }
    return [kept componentsJoinedByString:@""];
}

+ (NSString *)trimmed:(NSString *)text {
    if (![text isKindOfClass:NSString.class]) return @"";
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (BOOL)looksLikeLicenseKey:(NSString *)text {
    NSString *value = [self trimmed:[self cleanedKeyText:text]];
    if (value.length < 8 || value.length > 128) return NO;
    // Prefix is operator defined, so only require the shape:
    // prefix, then one or more hyphen separated groups.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
    if ([value rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return NO;
    if (![value containsString:@"-"]) return NO;
    if ([[value componentsSeparatedByString:@"-"] count] < 2) return NO;
    if ([value hasPrefix:@"-"] || [value hasSuffix:@"-"] || [value containsString:@"--"]) return NO;
    return YES;
}

+ (NSString *)validationHintForKeyText:(NSString *)text {
    NSString *value = [self trimmed:[self cleanedKeyText:text]];
    if (value.length == 0) return nil;
    if ([self looksLikeLicenseKey:value]) return nil;
    if (value.length < 8) return @"Key còn quá ngắn";
    if (![value containsString:@"-"]) return @"Key cần dạng PREFIX-XXXX-XXXX";
    if ([value containsString:@"--"]) return @"Key có dấu - bị thừa";
    if ([value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"].invertedSet].location != NSNotFound) {
        return @"Key chứa ký tự lạ";
    }
    return @"Key có thể chưa đúng định dạng";
}

#pragma mark - Clipboard

+ (NSString *)clipboardCandidate {
    NSString *raw = UIPasteboard.generalPasteboard.string;
    if (raw.length == 0) return nil;
    // A clipboard often holds an entire line, not just the key. Try the raw
    // value first, then the first whitespace separated token on the line.
    if ([self looksLikeLicenseKey:raw]) return [self cleanedKeyText:raw];
    for (NSString *line in [raw componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        for (NSString *token in [line componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
            if ([self looksLikeLicenseKey:token]) return [self cleanedKeyText:token];
        }
    }
    return nil;
}

+ (void)refreshPasteButton:(UIButton *)button {
    UITextField *field = objc_getAssociatedObject(button, TserverKeyEntryPasteButtonKey);
    if (!field) return;
    NSString *candidate = [self clipboardCandidate];
    objc_setAssociatedObject(button, TserverKeyEntryPasteCandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    button.hidden = (candidate.length == 0);
    button.userInteractionEnabled = (candidate.length > 0);
    button.accessibilityHint = candidate.length > 0
        ? @"Điền license key đang được copy"
        : nil;
}

+ (void)pasteTapped:(UIButton *)sender {
    NSString *candidate = objc_getAssociatedObject(sender, TserverKeyEntryPasteCandidateKey);
    if (![candidate isKindOfClass:NSString.class] || candidate.length == 0) {
        [self refreshPasteButton:sender];
        return;
    }
    UITextField *field = objc_getAssociatedObject(sender, TserverKeyEntryPasteButtonKey);
    if (!field) return;
    field.text = candidate;
    [field sendActionsForControlEvents:UIControlEventEditingChanged];
    if (@available(iOS 13.0, *)) {
        [field setNeedsFocusUpdate];
    }
    [self refreshHintForField:field];
    // Keep focus in the field so the user can correct a typo instead of
    // re-opening the keyboard from scratch.
    [field becomeFirstResponder];
}

+ (id)pasteObserver {
    static id observer = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIPasteboardChangedNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            [TserverKeyEntryAssist refreshAllPasteButtons];
        }];
    });
    return observer;
}

+ (void)refreshAllPasteButtons {
    for (NSValue *value in [self trackedPasteButtons]) {
        UIButton *button = value.nonretainedObjectValue;
        if (button) [self refreshPasteButton:button];
    }
}

+ (NSSet<NSValue *> *)trackedPasteButtons {
    // The set is tiny (one button per key entry surface), so a simple global
    // registry is cheaper and safer than walking the view hierarchy.
    static NSMutableSet *registry = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ registry = [NSMutableSet set]; });
    return registry;
}

+ (void)trackPasteButton:(UIButton *)button {
    NSMutableSet *registry = (NSMutableSet *)[self trackedPasteButtons];
    @synchronized (registry) {
        [registry addObject:[NSValue valueWithNonretainedObject:button]];
    }
    [self refreshPasteButton:button];
}

+ (void)bindPasteButton:(UIButton *)button toField:(UITextField *)field {
    if (!button || !field) return;
    objc_setAssociatedObject(button, TserverKeyEntryPasteButtonKey, field, OBJC_ASSOCIATION_ASSIGN);
    [button removeTarget:nil action:@selector(pasteTapped:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(pasteTapped:) forControlEvents:UIControlEventTouchUpInside];
    button.hidden = YES;
    [self trackPasteButton:button];
    (void)self.pasteObserver;
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        [TserverKeyEntryAssist refreshPasteButton:button];
    }];
}

#pragma mark - Live hint

+ (void)refreshHintForField:(UITextField *)field {
    UILabel *label = objc_getAssociatedObject(field, TserverKeyEntryHintLabelKey);
    if (!label) return;
    NSString *hint = [self validationHintForKeyText:field.text];
    label.text = hint;
    label.hidden = (hint.length == 0);
}

+ (void)revealValidationHintForField:(UITextField *)field {
    if (!field) return;
    UILabel *label = objc_getAssociatedObject(field, TserverKeyEntryHintLabelKey);
    NSString *hint = [self validationHintForKeyText:field.text];
    if (label) {
        label.text = hint ?: @"Key chưa đúng định dạng";
        label.hidden = NO;
        return;
    }
    // No hint label on this surface: at least clear a half-typed key so the
    // submit action is obviously a no-op.
    field.text = @"";
}

+ (void)bindHintLabel:(UILabel *)label toField:(UITextField *)field {
    if (!field) return;
    if (label) {
        objc_setAssociatedObject(field, TserverKeyEntryHintLabelKey, label, OBJC_ASSOCIATION_ASSIGN);
        label.hidden = YES;
        [field addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    }
    [self refreshHintForField:field];
}

+ (void)fieldChanged:(UITextField *)field {
    [self refreshHintForField:field];
    for (NSValue *value in [self trackedPasteButtons]) {
        UIButton *button = value.nonretainedObjectValue;
        // Hide the paste affordance once the field already has content so the
        // user is not offered a conflicting suggestion.
        if (!button) continue;
        UITextField *bound = objc_getAssociatedObject(button, TserverKeyEntryPasteButtonKey);
        if (bound == field && [self trimmed:field.text].length > 0) {
            button.hidden = YES;
            continue;
        }
        [self refreshPasteButton:button];
    }
}

@end
