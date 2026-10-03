#import "TserverNativeTemplateRenderer.h"
#import "TserverSimpleUiPack.h"
#import "TserverTemplateRegistry.h"

@implementation TserverNativeTemplateRenderer

+ (void)decorateCard:(UIView *)card
        contentStack:(UIStackView *)stack
          background:(UIView *)background
              config:(NSDictionary *)config
              status:(NSString *)status {
    // Built-in legacy templates continue through the generic GateView. New UI packs
    // are instantiated directly by GateView through TserverSimpleUiPackCreateForRenderer.
    // This hook deliberately contains no template-name switch or auth behavior.
    (void)card;
    (void)stack;
    (void)background;
    (void)config;
    (void)status;
}

@end
