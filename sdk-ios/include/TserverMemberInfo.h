#import <Foundation/Foundation.h>

/// Optional helper for customer-made "key info" pages.
/// Prebuilt .a: call configureWithMemberApiKey:packageId: from your tweak/source.
/// Source build: you may also set kTserverMemberApiKey + kTserverMemberPackageId before building the .a.
/// Then render placeholders into any custom label/view you own.
typedef void (^TserverMemberInfoCompletion)(NSDictionary *result);
typedef void (^TserverMemberInfoTemplateCompletion)(NSString *text, NSDictionary *result);

@interface TserverMemberInfo : NSObject

/// Preferred when using a prebuilt .a: call this from your tweak/source before calling other methods.
+ (void)configureWithMemberApiKey:(NSString *)memberApiKey packageId:(NSString *)packageId;

+ (BOOL)isConfigured;
+ (NSString *)configuredPackageId;

/// GET /v1/member-api/packages, filtered by kTserverMemberPackageId.
+ (void)loadPackageInfoWithCompletion:(TserverMemberInfoCompletion)completion;

/// GET /v1/member-api/online, filtered by kTserverMemberPackageId.
+ (void)loadOnlineWithCompletion:(TserverMemberInfoCompletion)completion;

/// GET /v1/member-api/keys?packageId=...&includeRaw=false&limit=500.
+ (void)listKeysWithCompletion:(TserverMemberInfoCompletion)completion;

/// POST /v1/member-api/keys/remaining for a user-entered license key.
+ (void)checkKey:(NSString *)licenseKey completion:(TserverMemberInfoCompletion)completion;

/// Loads package + online + either checkKey: (when licenseKey is non-empty) or listKeys.
+ (void)loadInfoForKey:(NSString *)licenseKey completion:(TserverMemberInfoCompletion)completion;

/// Replace placeholders like %tserver_key%, %tserver_key_remaining%, %tserver_online% using a loaded result.
+ (NSString *)renderTemplate:(NSString *)templateText withInfo:(NSDictionary *)info;

/// Convenience: loadInfoForKey then renderTemplate.
+ (void)renderTemplate:(NSString *)templateText
            licenseKey:(NSString *)licenseKey
            completion:(TserverMemberInfoTemplateCompletion)completion;

/// Convert seconds to Vietnamese text. Lifetime/unactivated keys are handled.
+ (NSString *)formatRemainingSeconds:(NSNumber *)seconds
                          isLifetime:(BOOL)isLifetime
                   startsOnActivation:(BOOL)startsOnActivation;

@end
