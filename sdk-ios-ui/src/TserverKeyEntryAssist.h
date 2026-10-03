#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared smart-entry helpers for every license key input surface.
///
/// Deliberately does NOT invent a key format. The prefix is chosen per plan or
/// per member package, so the SDK only removes what people accidentally paste
/// (surrounding quotes, backticks, spaces, newlines) and then validates the
/// shape. The key body is never rewritten while the user types.
@interface TserverKeyEntryAssist : NSObject

/// Trim quotes/backticks and collapse whitespace, preserving the key itself.
+ (NSString *)cleanedKeyText:(nullable NSString *)text;

/// True when the text can plausibly be a license key (prefix + hyphen groups).
+ (BOOL)looksLikeLicenseKey:(nullable NSString *)text;

/// Short live hint such as "PREFIX-XXXX-XXXX" or nil when the text is valid.
+ (nullable NSString *)validationHintForKeyText:(nullable NSString *)text;

/// Show `button` only while the clipboard holds something key-like, and fill the
/// field from the clipboard when tapped.
+ (void)bindPasteButton:(UIButton *)button toField:(UITextField *)field;

/// Keep a hint label in sync with the field (nil label disables the behaviour).
+ (void)bindHintLabel:(nullable UILabel *)label toField:(UITextField *)field;

/// Force the bound hint label to show the current validation message. Used when
/// the user submits an unusable key, so no new label is created per attempt.
+ (void)revealValidationHintForField:(nullable UITextField *)field;

@end

NS_ASSUME_NONNULL_END
