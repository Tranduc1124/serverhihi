#import <Foundation/Foundation.h>
#import <stddef.h>
#import <stdint.h>

// Encrypted in-binary blobs / offset tables (XOR stream, not strong crypto).
// Goal: no plain pointers/offsets/strings sitting in .rodata for easy dump.
//
// Layout of a sealed blob in the binary:
//   u32 magic 'TSB1' | u32 len | u8 key[16] | u8 payload[len]  (payload = plain XOR keystream(key))
// Runtime: TserverSecureBlobOpen copies plaintext to caller buffer then caller must wipe.

#ifdef __cplusplus
extern "C" {
#endif

#define TSERVER_SECURE_BLOB_MAGIC 0x31525354u /* 'TSR1' little-endian display as TSB1-ish */

typedef struct {
  uint32_t magic;
  uint32_t length;
  uint8_t key[16];
  // uint8_t data[length];  // follows immediately
} TserverSecureBlobHeader;

/// Decrypt sealed blob into out (outCap must be >= length). Returns length or -1.
int TserverSecureBlobOpen(const void *sealed, size_t sealedSize, void *out, size_t outCap);

/// Encrypt plain into caller-owned buffer (header+payload). Returns total bytes or -1.
int TserverSecureBlobSeal(const void *plain, size_t plainLen, void *out, size_t outCap);

/// Decode a sealed table of u32 offsets (count = length/4). out must hold count elems.
int TserverSecureBlobOpenU32Table(const void *sealed, size_t sealedSize, uint32_t *out, size_t maxCount);

/// Wipe buffer.
void TserverSecureWipe(void *p, size_t n);

#ifdef __cplusplus
}
#endif
