#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presentation-only native pack extension. It decorates a safe shared auth content
/// stack; it has no access to transport, session, lease, package token, or callbacks.
@protocol TserverNativeTemplateRendering <NSObject>
+ (void)decorateCard:(UIView *)card
        contentStack:(UIStackView *)stack
          background:(UIView *)background
              config:(NSDictionary *)config
              status:(NSString *)status;
@end

@interface TserverNativeTemplateRenderer : NSObject
+ (void)decorateCard:(UIView *)card
        contentStack:(UIStackView *)stack
          background:(UIView *)background
              config:(NSDictionary *)config
              status:(NSString *)status;
@end

NS_ASSUME_NONNULL_END
