#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Native renderer metadata is compiled into the SDK. Server configuration may select
/// a renderer ID, but it can never provide a class name, selector, or executable code.
@interface TserverTemplateDescriptor : NSObject
@property(nonatomic, copy) NSString *templateId;
@property(nonatomic, copy) NSString *rendererId;
@property(nonatomic, assign) NSInteger revision;
@property(nonatomic, copy) NSString *fallbackTemplateId;
@property(nonatomic, copy) NSArray<NSString *> *supportedOverrides;
@property(nonatomic, copy) NSDictionary *defaultConfig;
@end

FOUNDATION_EXPORT TserverTemplateDescriptor *TserverDescriptor(NSString *templateId,
                                                              NSString *rendererId,
                                                              NSInteger revision,
                                                              NSString * _Nullable fallbackTemplateId,
                                                              NSDictionary *defaults,
                                                              NSArray<NSString *> *overrides);

@interface TserverTemplateRegistry : NSObject
+ (nullable TserverTemplateDescriptor *)descriptorForTemplateName:(NSString *)templateName;
+ (nullable TserverTemplateDescriptor *)descriptorForRendererId:(NSString *)rendererId;
+ (NSArray<TserverTemplateDescriptor *> *)allDescriptors;
+ (nullable TserverTemplateDescriptor *)defaultTemplateDescriptor;
+ (nullable NSString *)defaultTemplateId;
+ (NSDictionary *)resolvedConfigByApplyingNativePackToConfig:(NSDictionary *)config;
+ (NSString *)templateFingerprintForConfig:(NSDictionary *)config;
+ (void)impactForAction:(NSString *)action config:(NSDictionary *)config;
+ (BOOL)reduceMotionEnabled;
@end

/// Motion and haptic feedback are deliberately presentation-only. They never alter
/// authorization state or emit network/auth actions.
@interface TserverTemplateFeedback : NSObject
+ (void)impactForAction:(NSString *)action config:(NSDictionary *)config;
+ (BOOL)reduceMotionEnabled;
@end

NS_ASSUME_NONNULL_END
