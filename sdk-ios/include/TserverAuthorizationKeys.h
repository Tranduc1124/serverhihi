#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

size_t TserverAuthorizationPublicKeyCount(void);
const char *TserverAuthorizationPublicKeyId(size_t index);
int TserverAuthorizationPublicKeyCopy(size_t index, uint8_t *out, size_t outCap);
int TserverAuthorizationPublicKeyringReady(void);

#ifdef __cplusplus
}
#endif
