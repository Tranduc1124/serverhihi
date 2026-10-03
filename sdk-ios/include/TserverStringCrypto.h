#pragma once
#import <Foundation/Foundation.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Giải mã mảng byte đã mã hóa với key thành NSString (an toàn bộ nhớ, auto-wipe)
FOUNDATION_EXPORT NSString *TserverDecodedNSString(const uint8_t *encData, size_t length, uint8_t k1, uint8_t k2);

/// Giải mã mảng byte đã mã hóa thành C-string vào buffer đích
FOUNDATION_EXPORT size_t TserverDecodedCString(const uint8_t *encData, size_t length, uint8_t k1, uint8_t k2, char *outBuf, size_t outCap);

/// Xóa sạch dữ liệu nhạy cảm trong bộ nhớ
FOUNDATION_EXPORT void TserverSecureMemZero(void *ptr, size_t size);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus

namespace TserverCryptoInternal {

template <size_t N, uint8_t K1, uint8_t K2>
struct ObfuscatedString {
    uint8_t data[N];

    constexpr ObfuscatedString(const char (&str)[N]) : data{} {
        for (size_t i = 0; i < N; ++i) {
            data[i] = static_cast<uint8_t>(str[i] ^ static_cast<uint8_t>(K1 + static_cast<uint8_t>(i * K2)));
        }
    }

    inline void decrypt(char *out) const {
        for (size_t i = 0; i < N; ++i) {
            out[i] = static_cast<char>(data[i] ^ static_cast<uint8_t>(K1 + static_cast<uint8_t>(i * K2)));
        }
    }

    inline size_t length() const {
        return N > 0 ? N - 1 : 0;
    }
};

} // namespace TserverCryptoInternal

template <size_t N, uint8_t K1, uint8_t K2>
static inline NSString *TserverMakeObfuscatedNSString(const TserverCryptoInternal::ObfuscatedString<N, K1, K2> &obf) {
    char buf[N];
    obf.decrypt(buf);
    NSString *res = [[NSString alloc] initWithBytes:buf length:(N > 0 ? N - 1 : 0) encoding:NSUTF8StringEncoding];
    TserverSecureMemZero(buf, N);
    return res;
}

template <size_t N, uint8_t K1, uint8_t K2>
static inline const char *TserverMakeObfuscatedCString(const TserverCryptoInternal::ObfuscatedString<N, K1, K2> &obf) {
    static __thread char tl_slots[8][512];
    static __thread size_t tl_cursor = 0;
    char *slot = tl_slots[tl_cursor % 8];
    tl_cursor++;

    char temp[N];
    obf.decrypt(temp);
    size_t copyLen = N < 512 ? N : 511;
    memcpy(slot, temp, copyLen);
    slot[copyLen > 0 ? copyLen - 1 : 0] = '\0';
    TserverSecureMemZero(temp, N);
    return slot;
}

#define TS_KEY_A ((uint8_t)((__LINE__ * 179 + 89) & 0xFF))
#define TS_KEY_B ((uint8_t)((((__LINE__ ^ 0x5C) * 37 + 23) | 1) & 0xFF))

/// Macro mã hóa chuỗi NSString tại compile-time, giải mã an toàn tại runtime
#define TS_OBF_NS(literal) \
    ([]() -> NSString* { \
        constexpr static const TserverCryptoInternal::ObfuscatedString<sizeof(literal), TS_KEY_A, TS_KEY_B> _enc(literal); \
        return TserverMakeObfuscatedNSString(_enc); \
    })()

/// Macro mã hóa C-string tại compile-time, giải mã an toàn vào thread-local buffer
#define TS_OBF_STR(literal) \
    ([]() -> const char* { \
        constexpr static const TserverCryptoInternal::ObfuscatedString<sizeof(literal), TS_KEY_A, TS_KEY_B> _enc(literal); \
        return TserverMakeObfuscatedCString(_enc); \
    })()

/// Macro tạo NSURL từ chuỗi mã hóa tại compile-time
#define TS_OBF_URL(literal) [NSURL URLWithString:TS_OBF_NS(literal)]

#endif // __cplusplus
