#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

void TserverGlassCardApply(UIView *card, UIStackView *stack, UIView *background, NSDictionary *config, NSString *status, BOOL reduceMotion);
void TserverGameLoaderHudApply(UIView *card, UIStackView *stack, UIView *background, NSDictionary *config, NSString *status, BOOL reduceMotion);
void TserverFullscreenHeroApply(UIView *card, UIStackView *stack, UIView *background, NSDictionary *config, NSString *status, BOOL reduceMotion);
void TserverSplitLandscapeApply(UIView *card, UIStackView *stack, UIView *background, NSDictionary *config, NSString *status, BOOL reduceMotion);

NS_ASSUME_NONNULL_END
