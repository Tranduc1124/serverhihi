#import <Foundation/Foundation.h>

// Internal runtime secret accessors (gated by TserverSecurity).
FOUNDATION_EXPORT NSString *TserverRuntimeBaseURL(void);
FOUNDATION_EXPORT NSString *TserverRuntimeClientApiKey(void);
