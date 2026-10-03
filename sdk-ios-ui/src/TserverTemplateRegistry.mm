#import "TserverTemplateRegistry.h"
#import "TserverTemplateCatalog.gen.mm"

@implementation TserverTemplateDescriptor
@end

static NSDictionary *TserverDeepMerge(NSDictionary *base, NSDictionary *override) {
    NSMutableDictionary *out = [base mutableCopy] ?: [NSMutableDictionary dictionary];
    [override enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || value == nil || value == NSNull.null) return;
        id current = out[key];
        if ([current isKindOfClass:NSDictionary.class] && [value isKindOfClass:NSDictionary.class]) {
            out[key] = TserverDeepMerge(current, value);
        } else {
            out[key] = value;
        }
    }];
    return [out copy];
}

TserverTemplateDescriptor *TserverDescriptor(NSString *templateId,
                                            NSString *rendererId,
                                            NSInteger revision,
                                            NSString *fallbackTemplateId,
                                            NSDictionary *defaults,
                                            NSArray<NSString *> *overrides) {
    TserverTemplateDescriptor *descriptor = [TserverTemplateDescriptor new];
    descriptor.templateId = templateId;
    descriptor.rendererId = rendererId;
    descriptor.revision = revision;
    descriptor.fallbackTemplateId = [fallbackTemplateId copy] ?: @"";
    descriptor.defaultConfig = defaults;
    descriptor.supportedOverrides = overrides;
    return descriptor;
}

@implementation TserverTemplateRegistry

+ (NSArray<TserverTemplateDescriptor *> *)allDescriptors {
    static NSArray<TserverTemplateDescriptor *> *descriptors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        descriptors = _TserverGeneratedDescriptors();
    });
    return descriptors;
}

+ (TserverTemplateDescriptor *)descriptorForTemplateName:(NSString *)templateName {
    for (TserverTemplateDescriptor *descriptor in self.allDescriptors) {
        if ([descriptor.templateId isEqualToString:templateName]) return descriptor;
    }
    return nil;
}

+ (TserverTemplateDescriptor *)defaultTemplateDescriptor {
    NSString *templateId = _TserverGeneratedDefaultTemplateId();
    return templateId.length > 0 ? [self descriptorForTemplateName:templateId] : self.allDescriptors.firstObject;
}

+ (NSString *)defaultTemplateId {
    return self.defaultTemplateDescriptor.templateId;
}

+ (TserverTemplateDescriptor *)descriptorForRendererId:(NSString *)rendererId {
    for (TserverTemplateDescriptor *descriptor in self.allDescriptors) {
        if ([descriptor.rendererId isEqualToString:rendererId]) return descriptor;
    }
    return nil;
}

+ (NSDictionary *)resolvedConfigByApplyingNativePackToConfig:(NSDictionary *)config {
    NSDictionary *safe = [config isKindOfClass:NSDictionary.class] ? config : @{};
    NSString *templateName = [safe[@"templateName"] isKindOfClass:NSString.class] ? safe[@"templateName"] : @"";
    TserverTemplateDescriptor *descriptor = [self descriptorForTemplateName:templateName];
    NSMutableSet<NSString *> *visited = [NSMutableSet set];
    while (descriptor && descriptor.rendererId.length > 0 && !_TserverResolvedClassForRendererId(descriptor.rendererId)) {
        if ([visited containsObject:descriptor.templateId]) {
            descriptor = nil;
            break;
        }
        [visited addObject:descriptor.templateId];
        descriptor = descriptor.fallbackTemplateId.length > 0
            ? [self descriptorForTemplateName:descriptor.fallbackTemplateId]
            : nil;
    }
    if (!descriptor) descriptor = self.defaultTemplateDescriptor;
    if (!descriptor) return safe;
    NSMutableDictionary *pack = [descriptor.defaultConfig mutableCopy];
    NSMutableDictionary *overrides = [safe mutableCopy];
    NSDictionary *renderer = [safe[@"renderer"] isKindOfClass:NSDictionary.class] ? safe[@"renderer"] : @{};
    NSString *rendererId = [renderer[@"id"] isKindOfClass:NSString.class] ? renderer[@"id"] : @"";
    if (rendererId.length > 0 && ![rendererId isEqualToString:descriptor.rendererId]) {
        [overrides removeObjectForKey:@"renderer"];
    }
    NSDictionary *merged = TserverDeepMerge(pack, overrides);
    NSMutableDictionary *out = [merged mutableCopy];
    out[@"templateName"] = descriptor.templateId;
    out[@"renderer"] = @{ @"id": descriptor.rendererId, @"revision": @(descriptor.revision) };
    out[@"schemaVersion"] = @2;
    return out;
}

+ (NSString *)templateFingerprintForConfig:(NSDictionary *)config {
    NSDictionary *resolved = [self resolvedConfigByApplyingNativePackToConfig:config];
    NSDictionary *renderer = [resolved[@"renderer"] isKindOfClass:NSDictionary.class] ? resolved[@"renderer"] : @{};
    NSDictionary *style = [resolved[@"style"] isKindOfClass:NSDictionary.class] ? resolved[@"style"] : @{};
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@",
            resolved[@"templateName"] ?: @"default", renderer[@"id"] ?: @"generic", renderer[@"revision"] ?: @0,
            style[@"accent"] ?: @"", style[@"background"] ?: @"", style[@"card"] ?: @""];
}

+ (void)impactForAction:(NSString *)action config:(NSDictionary *)config {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    NSDictionary *motion = [config[@"motion"] isKindOfClass:NSDictionary.class] ? config[@"motion"] : @{};
    NSString *style = [motion[@"haptic"] isKindOfClass:NSString.class] ? motion[@"haptic"] : @"light";
    UIImpactFeedbackStyle feedback = UIImpactFeedbackStyleLight;
    if ([style isEqualToString:@"medium"]) feedback = UIImpactFeedbackStyleMedium;
    // Keep iOS 12 compatibility; rigid feedback is iOS 13+.
    if ([style isEqualToString:@"rigid"]) feedback = UIImpactFeedbackStyleMedium;
    if ([action isEqualToString:@"success"] || [action isEqualToString:@"error"]) {
        UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
        [generator prepare];
        [generator notificationOccurred:[action isEqualToString:@"success"] ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
        return;
    }
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:feedback];
    [generator prepare];
    [generator impactOccurred];
}

+ (BOOL)reduceMotionEnabled {
    return UIAccessibilityIsReduceMotionEnabled();
}

@end
