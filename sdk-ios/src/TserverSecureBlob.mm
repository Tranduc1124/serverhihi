#import "TserverSecureBlob.h"
#import <string.h>
#import <stdlib.h>

// Lightweight XOR stream from 16-byte key (not AES — anti-dump / anti-strings only).

static void TserverKeystream(const uint8_t key[16], uint8_t *out, size_t len) {
  // xorshift-ish expansion of key material
  uint32_t s0 = (uint32_t)key[0] | ((uint32_t)key[1] << 8) | ((uint32_t)key[2] << 16) | ((uint32_t)key[3] << 24);
  uint32_t s1 = (uint32_t)key[4] | ((uint32_t)key[5] << 8) | ((uint32_t)key[6] << 16) | ((uint32_t)key[7] << 24);
  uint32_t s2 = (uint32_t)key[8] | ((uint32_t)key[9] << 8) | ((uint32_t)key[10] << 16) | ((uint32_t)key[11] << 24);
  uint32_t s3 = (uint32_t)key[12] | ((uint32_t)key[13] << 8) | ((uint32_t)key[14] << 16) | ((uint32_t)key[15] << 24);
  if ((s0 | s1 | s2 | s3) == 0) {
    s0 = 0xA5A5A5A5u;
    s1 = 0x3C6EF372u;
    s2 = 0x1F83D9ABu;
    s3 = 0x9E3779B9u;
  }
  for (size_t i = 0; i < len; i++) {
    uint32_t t = s0 ^ (s0 << 11);
    s0 = s1;
    s1 = s2;
    s2 = s3;
    s3 = s3 ^ (s3 >> 19) ^ t ^ (t >> 8);
    out[i] = (uint8_t)(s3 & 0xFF);
  }
}

void TserverSecureWipe(void *p, size_t n) {
  if (!p || n == 0) return;
  volatile uint8_t *v = (volatile uint8_t *)p;
  for (size_t i = 0; i < n; i++) v[i] = 0;
}

int TserverSecureBlobOpen(const void *sealed, size_t sealedSize, void *out, size_t outCap) {
  if (!sealed || !out || sealedSize < sizeof(TserverSecureBlobHeader)) return -1;
  const TserverSecureBlobHeader *h = (const TserverSecureBlobHeader *)sealed;
  if (h->magic != TSERVER_SECURE_BLOB_MAGIC) return -1;
  if (h->length == 0 || h->length > 4 * 1024 * 1024) return -1;
  if (sealedSize < sizeof(TserverSecureBlobHeader) + h->length) return -1;
  if (outCap < h->length) return -1;
  const uint8_t *enc = (const uint8_t *)(h + 1);
  uint8_t *ks = (uint8_t *)malloc(h->length);
  if (!ks) return -1;
  TserverKeystream(h->key, ks, h->length);
  uint8_t *dst = (uint8_t *)out;
  for (uint32_t i = 0; i < h->length; i++) {
    dst[i] = (uint8_t)(enc[i] ^ ks[i]);
  }
  TserverSecureWipe(ks, h->length);
  free(ks);
  return (int)h->length;
}

int TserverSecureBlobSeal(const void *plain, size_t plainLen, void *out, size_t outCap) {
  if (!plain || !out || plainLen == 0 || plainLen > 4 * 1024 * 1024) return -1;
  size_t total = sizeof(TserverSecureBlobHeader) + plainLen;
  if (outCap < total) return -1;
  TserverSecureBlobHeader *h = (TserverSecureBlobHeader *)out;
  h->magic = TSERVER_SECURE_BLOB_MAGIC;
  h->length = (uint32_t)plainLen;
  // Random-ish key from stack noise + plain mix (build-time tools should set real key;
  // runtime seal is mainly for tests / dynamic tables).
  for (int i = 0; i < 16; i++) {
    h->key[i] = (uint8_t)(((uintptr_t)plain >> (i % 8)) ^ (plainLen * 131u + (unsigned)i * 17u));
  }
  uint8_t *ks = (uint8_t *)malloc(plainLen);
  if (!ks) return -1;
  TserverKeystream(h->key, ks, plainLen);
  const uint8_t *src = (const uint8_t *)plain;
  uint8_t *enc = (uint8_t *)(h + 1);
  for (size_t i = 0; i < plainLen; i++) {
    enc[i] = (uint8_t)(src[i] ^ ks[i]);
  }
  TserverSecureWipe(ks, plainLen);
  free(ks);
  return (int)total;
}

int TserverSecureBlobOpenU32Table(const void *sealed, size_t sealedSize, uint32_t *out, size_t maxCount) {
  if (!out || maxCount == 0) return -1;
  size_t cap = maxCount * sizeof(uint32_t);
  uint8_t *tmp = (uint8_t *)malloc(cap);
  if (!tmp) return -1;
  int n = TserverSecureBlobOpen(sealed, sealedSize, tmp, cap);
  if (n < 0 || (n % 4) != 0) {
    TserverSecureWipe(tmp, cap);
    free(tmp);
    return -1;
  }
  size_t count = (size_t)n / 4;
  if (count > maxCount) count = maxCount;
  memcpy(out, tmp, count * 4);
  TserverSecureWipe(tmp, cap);
  free(tmp);
  return (int)count;
}
