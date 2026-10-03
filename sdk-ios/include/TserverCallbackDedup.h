#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Reserves a privacy-safe digest for callback processing. The caller must commit
/// success/failure after the configured auth handler accepts or rejects the URL.
BOOL TserverCallbackURLShouldProcess(NSURL *url);
void TserverCallbackURLCommit(NSURL *url, BOOL accepted);

#ifdef __cplusplus
}
#endif
