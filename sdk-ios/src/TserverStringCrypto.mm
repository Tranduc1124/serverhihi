#import "TserverStringCrypto.h"
#import "TserverSecureBlob.h"
#import <string.h>
#import <stdlib.h>

void TserverSecureMemZero(void *ptr, size_t size) {
    if (!ptr || size == 0) return;
    volatile uint8_t *p = (volatile uint8_t *)ptr;
    while (size--) {
        *p++ = 0;
    }
}

NSString *TserverDecodedNSString(const uint8_t *encData, size_t length, uint8_t k1, uint8_t k2) {
    if (!encData || length == 0) return @"";
    char *buf = (char *)malloc(length + 1);
    if (!buf) return @"";
    for (size_t i = 0; i < length; ++i) {
        buf[i] = (char)(encData[i] ^ (uint8_t)(k1 + (uint8_t)(i * k2)));
    }
    buf[length] = '\0';
    NSString *str = [[NSString alloc] initWithBytes:buf length:length encoding:NSUTF8StringEncoding];
    TserverSecureMemZero(buf, length + 1);
    free(buf);
    return str ?: @"";
}

size_t TserverDecodedCString(const uint8_t *encData, size_t length, uint8_t k1, uint8_t k2, char *outBuf, size_t outCap) {
    if (!encData || !outBuf || length == 0 || outCap == 0) return 0;
    size_t copyLen = length < (outCap - 1) ? length : (outCap - 1);
    for (size_t i = 0; i < copyLen; ++i) {
        outBuf[i] = (char)(encData[i] ^ (uint8_t)(k1 + (uint8_t)(i * k2)));
    }
    outBuf[copyLen] = '\0';
    return copyLen;
}
