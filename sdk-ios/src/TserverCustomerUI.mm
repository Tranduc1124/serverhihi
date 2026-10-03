#import "TserverCustomerUI.h"
#import <UIKit/UIKit.h>

static NSDictionary *TserverCustomerDefaultAuthUiConfig(void) {
    return @{
        @"version": @1,
        @"sourceOverridesServer": @NO,
        @"authTheme": @"glass_dark",
        @"layout": @"floating",
        @"flow": @{
            @"minimumLoadingMs": @550,
            @"validAction": @"auto"
        },
        @"geometry": @{
            @"horizontalInset": @18,
            @"maxCardWidth": @480,
            @"minCardWidth": @320,
            @"minCardHeight": @0,
            @"xOffset": @0,
            @"yOffset": @0,
            @"overlayOpacity": @0.96,
            @"cardOpacity": @1.0,
            @"iconSize": @38,
            @"position": @"center"
        },
        @"animation": @{
            @"type": @"scale",
            @"durationMs": @220,
            @"delayMs": @0,
            @"distance": @22
        },
        @"typography": @{
            @"fontFamily": @"System",
            @"titleSize": @22,
            @"subtitleSize": @14,
            @"buttonSize": @16,
            @"inputSize": @16
        },
        @"icons": @{
            @"loading": @"fa-bolt",
            @"needKey": @"fa-key",
            @"needUuid": @"fa-shield-halved",
            @"valid": @"fa-circle-check"
        }
    };
}

static NSDictionary *TserverCustomerMergeConfig(NSDictionary *base, NSDictionary *override) {
    if (![override isKindOfClass:NSDictionary.class]) return base ?: @{};
    NSMutableDictionary *merged = [base mutableCopy] ?: [NSMutableDictionary dictionary];
    [override enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || object == nil || object == NSNull.null) return;
        id existing = merged[key];
        if ([existing isKindOfClass:NSDictionary.class] && [object isKindOfClass:NSDictionary.class]) {
            merged[key] = TserverCustomerMergeConfig(existing, object);
        } else {
            merged[key] = object;
        }
    }];
    return [merged copy];
}

static NSArray<NSString *> *TserverCustomerCurrentSourceKeys(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *bundleId = bundle.bundleIdentifier ?: @"";
    NSString *displayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"";
    NSString *bundleName = [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"";
    NSString *executable = [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] ?: @"";
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in @[bundleId, displayName, bundleName, executable]) {
        NSString *trimmed = [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0 && ![keys containsObject:trimmed]) [keys addObject:trimmed];
    }
    return [keys copy];
}

static NSDictionary *TserverCustomerSelectSourceConfig(NSDictionary *raw) {
    if (![raw[@"sources"] isKindOfClass:NSDictionary.class]) return raw ?: @{};
    NSDictionary *sources = raw[@"sources"];
    NSDictionary *aliases = [raw[@"sourceAliases"] isKindOfClass:NSDictionary.class] ? raw[@"sourceAliases"] : @{};
    NSDictionary *defaultConfig = [sources[@"default"] isKindOfClass:NSDictionary.class] ? sources[@"default"] : @{};
    NSDictionary *selected = nil;

    for (NSString *key in TserverCustomerCurrentSourceKeys()) {
        id direct = sources[key];
        if ([direct isKindOfClass:NSDictionary.class]) {
            selected = direct;
            break;
        }
        id alias = aliases[key];
        if ([alias isKindOfClass:NSString.class] && [sources[alias] isKindOfClass:NSDictionary.class]) {
            selected = sources[alias];
            break;
        }
    }

    NSMutableDictionary *rootOptions = [raw mutableCopy];
    [rootOptions removeObjectForKey:@"sources"];
    [rootOptions removeObjectForKey:@"sourceAliases"];
    NSDictionary *withRootOptions = TserverCustomerMergeConfig(defaultConfig, rootOptions);
    return selected ? TserverCustomerMergeConfig(withRootOptions, selected) : withRootOptions;
}

NSDictionary *TserverCustomerAuthUiConfig(void) {
    static NSDictionary *config;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *rawConfig = @{
            @"version": @2,
            @"sourceAliases": @{
                // Add aliases like: @"com.example.game": @"lienquan"
            },
            @"sources": @{
                @"default": TserverCustomerDefaultAuthUiConfig(),
                // Add more source profiles here, keyed by Bundle ID, app name, or an alias.
                // Example:
                // @"com.garena.game.kgvn": @{
                //     @"authTheme": @"neon_dark",
                //     @"flow": @{ @"validAction": @"auto" }
                // }
            }
        };
        config = TserverCustomerSelectSourceConfig(rawConfig);
    });
    return config;
}
