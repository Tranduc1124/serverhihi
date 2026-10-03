#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presentation-only popup overlay shared by native packs and the legacy GateView.
/// It never owns auth actions and never accepts touches.
@interface TserverPopupRenderer : NSObject

- (instancetype)initWithHostView:(UIView *)hostView
                          config:(NSDictionary *)config
                    presentation:(NSString *)presentation;
- (void)presentForStatus:(NSString *)status
              screenName:(NSString *)screenName
                 message:(NSString *)message;
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
