#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const TserverStatusValid;
FOUNDATION_EXPORT NSString * const TserverStatusNeedUUID;
FOUNDATION_EXPORT NSString * const TserverStatusNeedKey;
FOUNDATION_EXPORT NSString * const TserverStatusExpired;
FOUNDATION_EXPORT NSString * const TserverStatusRevoked;
FOUNDATION_EXPORT NSString * const TserverStatusInvalidKey;
FOUNDATION_EXPORT NSString * const TserverStatusDeviceMismatch;
FOUNDATION_EXPORT NSString * const TserverStatusDeviceBlocked;
FOUNDATION_EXPORT NSString * const TserverStatusBadSession;
FOUNDATION_EXPORT NSString * const TserverStatusServerError;
FOUNDATION_EXPORT NSString * const TserverStatusNetworkError;
FOUNDATION_EXPORT NSString * const TserverStatusTrialAlreadyUsed;
FOUNDATION_EXPORT NSString * const TserverStatusOfflineGraceValid;
FOUNDATION_EXPORT NSString * const TserverStatusOfflineGraceExpired;
FOUNDATION_EXPORT NSString * const TserverStatusBadResponseSignature;
FOUNDATION_EXPORT NSString * const TserverStatusInvalidApiKey;
FOUNDATION_EXPORT NSString * const TserverStatusInvalidClientApiKey;
// Local-only: the SDK could not access its compiled client key. This is distinct
// from a server-issued INVALID_CLIENT_API_KEY response.
FOUNDATION_EXPORT NSString * const TserverStatusClientKeyUnavailable;
FOUNDATION_EXPORT NSString * const TserverStatusPackageBundleDenied;
FOUNDATION_EXPORT NSString * const TserverStatusBadPackageSession;
FOUNDATION_EXPORT NSString * const TserverStatusUpdateRequired;
FOUNDATION_EXPORT NSString * const TserverStatusMaintenance;
FOUNDATION_EXPORT NSString * const TserverStatusBadClientSignature;
FOUNDATION_EXPORT NSString * const TserverStatusReplayRequest;
FOUNDATION_EXPORT NSString * const TserverStatusRateLimited;
FOUNDATION_EXPORT NSString * const TserverStatusAuthorizationLeaseInvalid;
FOUNDATION_EXPORT NSString * const TserverStatusActivationTimeout;
FOUNDATION_EXPORT NSString * const TserverStatusActivationCancelled;
FOUNDATION_EXPORT NSString * const TserverStatusUnsafeEnvironment;
FOUNDATION_EXPORT NSString * const TserverStatusCallbackFailure;
FOUNDATION_EXPORT NSString * const TserverStatusUIFailure;

FOUNDATION_EXPORT NSString * const TserverStatusTransportSessionError;
FOUNDATION_EXPORT NSString * const TserverSDKBuildIdentifier;
FOUNDATION_EXPORT void TserverAuthDrainPendingCallbackURLs(void);

typedef void (^TserverCompletion)(NSDictionary *result);

@interface TserverAuth : NSObject

/// Package API configuration (preferred).
+ (void)configureWithEndpoint:(NSString *)endpoint
                 packageToken:(NSString *)packageToken
                 returnScheme:(NSString *)returnScheme;

+ (void)configureWithEndpoints:(NSArray<NSString *> *)endpoints
                  packageToken:(NSString *)packageToken
                  returnScheme:(NSString *)returnScheme;

/// Legacy client API — forwards to package configure when kTserverPackageToken is set in config.
+ (void)configureWithEndpoint:(NSString *)endpoint
                      storeId:(NSString *)storeId
                        appId:(NSString *)appId
                 returnScheme:(NSString *)returnScheme;

+ (void)configureWithEndpoint:(NSString *)endpoint
                      storeId:(NSString *)storeId
                        appId:(NSString *)appId
                 returnScheme:(NSString *)returnScheme
                    apiSecret:(NSString *)apiSecret;

+ (void)configureWithEndpoints:(NSArray<NSString *> *)endpoints
                       storeId:(NSString *)storeId
                         appId:(NSString *)appId
                  returnScheme:(NSString *)returnScheme
                     apiSecret:(NSString *)apiSecret;

+ (void)startProfileFlow;

+ (void)startProfileFlowFromViewController:(UIViewController *)viewController;

+ (void)startProfileFlowFromViewController:(UIViewController *)viewController
                               completion:(TserverCompletion)completion;

+ (BOOL)handleCallbackURL:(NSURL *)url
               completion:(TserverCompletion)completion;

+ (BOOL)isAwaitingProfileConfirmation;
+ (void)setAwaitingProfileConfirmation:(BOOL)awaiting;

+ (void)refreshAuthAfterProfileInstallWithCompletion:(TserverCompletion)completion;

+ (void)claimProfileWithSessionToken:(NSString *)sessionToken
                          completion:(TserverCompletion)completion;

+ (void)confirmCurrentDeviceWithCompletion:(TserverCompletion)completion;

+ (void)bootstrapWithCompletion:(TserverCompletion)completion;

+ (void)bootstrapWithSessionToken:(NSString *)sessionToken
                       completion:(TserverCompletion)completion;

+ (void)activateKey:(NSString *)licenseKey
         completion:(TserverCompletion)completion;

/// True while a key activation request is in flight. Foreground/bootstrap UI
/// reconciliation must not overwrite its eventual result.
+ (BOOL)isActivationInFlight;

/// Monotonically increases whenever a new activation starts. Async bootstrap/UI
/// work uses this generation to discard results from before the activation.
+ (NSUInteger)activationGeneration;

+ (void)activateKey:(NSString *)licenseKey
       sessionToken:(NSString *)sessionToken
         completion:(TserverCompletion)completion;

+ (void)verifyWithCompletion:(TserverCompletion)completion;

+ (void)verifyWithSessionToken:(NSString *)sessionToken
                    completion:(TserverCompletion)completion;

+ (NSString *)savedSessionToken;
+ (void)saveSessionToken:(NSString *)sessionToken;
+ (void)clearSession;

+ (NSString *)currentBundleId;
+ (NSString *)configuredReturnScheme;
+ (BOOL)isReturnSchemeRegisteredInHostApp;
+ (NSString *)profileStartURL;

@end
