#import <Foundation/Foundation.h>

// Server-driven security policy (from signed package responses).
// Applied after bootstrap/activate; defaults are fail-closed for hook/log.

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void TserverSecurityPolicyApplyFromResponse(NSDictionary * _Nullable response);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyHookKillEnabled(void);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyLogKillEnabled(void);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyForceUpdate(void);
FOUNDATION_EXPORT NSInteger TserverSecurityPolicyMinSdkBuild(void);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyRequireTransportSession(void);
FOUNDATION_EXPORT NSInteger TserverSecurityPolicyMinTransportVersion(void);
FOUNDATION_EXPORT NSArray<NSString *> *TserverSecurityPolicyTlsSpkiPins(void);
FOUNDATION_EXPORT NSArray<NSString *> *TserverSecurityPolicyAcceptedClientIdentityKids(void);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyAllowWithoutKey(void);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyHideScreenCapture(void);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyProtectScreenContent(void);
FOUNDATION_EXPORT BOOL TserverSecurityPolicyRequireLatestSdk(void);
FOUNDATION_EXPORT NSString * _Nullable TserverSecurityPolicyForceUpdateUrl(void);
FOUNDATION_EXPORT NSDictionary * _Nullable TserverSecurityPolicyCurrent(void);
FOUNDATION_EXPORT NSDictionary * _Nullable TserverSecurityPolicyPackageSettings(void);

NS_ASSUME_NONNULL_END
