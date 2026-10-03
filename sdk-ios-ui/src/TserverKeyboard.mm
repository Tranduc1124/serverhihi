#import <UIKit/UIKit.h>

@interface TserverKeyboard : NSObject
+ (void)installDismissGestureOnView:(UIView *)view;
@end

@implementation TserverKeyboard

+ (void)installDismissGestureOnView:(UIView *)view {
    if (!view) return;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard:)];
    tap.cancelsTouchesInView = NO;
    [view addGestureRecognizer:tap];
}

+ (void)dismissKeyboard:(UITapGestureRecognizer *)recognizer {
    [recognizer.view endEditing:YES];
}

@end
