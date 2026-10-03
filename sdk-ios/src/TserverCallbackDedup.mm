#import "TserverCallbackDedup.h"
#import <CommonCrypto/CommonDigest.h>

static NSMutableDictionary<NSString *, NSNumber *> *gTserverRecentCallbackDigests = nil;
static NSMutableSet<NSString *> *gTserverReservedCallbackDigests = nil;
static const NSTimeInterval kTserverCallbackDedupSeconds = 5.0;

static NSString *TserverCallbackDigest(NSURL *url) {
    NSData *data = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    static const char hex[] = "0123456789abcdef";
    char compact[25] = {0};
    for (NSUInteger index = 0; index < 12; index++) {
        compact[index * 2] = hex[(digest[index] >> 4) & 0x0f];
        compact[index * 2 + 1] = hex[digest[index] & 0x0f];
    }
    return [NSString stringWithUTF8String:compact];
}

static void TserverPruneCallbackDigests(NSTimeInterval now) {
    for (NSString *key in [gTserverRecentCallbackDigests allKeys]) {
        if (now - [gTserverRecentCallbackDigests[key] doubleValue] > kTserverCallbackDedupSeconds) {
            [gTserverRecentCallbackDigests removeObjectForKey:key];
        }
    }
}

BOOL TserverCallbackURLShouldProcess(NSURL *url) {
    if (!url) return NO;
    @synchronized(NSProcessInfo.processInfo) {
        gTserverRecentCallbackDigests = gTserverRecentCallbackDigests ?: [NSMutableDictionary dictionary];
        gTserverReservedCallbackDigests = gTserverReservedCallbackDigests ?: [NSMutableSet set];
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        TserverPruneCallbackDigests(now);
        NSString *key = TserverCallbackDigest(url);
        if (key.length == 0 || [gTserverReservedCallbackDigests containsObject:key]) return NO;
        NSNumber *seenAt = gTserverRecentCallbackDigests[key];
        if (seenAt && now - seenAt.doubleValue <= kTserverCallbackDedupSeconds) return NO;
        [gTserverReservedCallbackDigests addObject:key];
        return YES;
    }
}

void TserverCallbackURLCommit(NSURL *url, BOOL accepted) {
    if (!url) return;
    @synchronized(NSProcessInfo.processInfo) {
        gTserverRecentCallbackDigests = gTserverRecentCallbackDigests ?: [NSMutableDictionary dictionary];
        gTserverReservedCallbackDigests = gTserverReservedCallbackDigests ?: [NSMutableSet set];
        NSString *key = TserverCallbackDigest(url);
        if (key.length == 0) return;
        [gTserverReservedCallbackDigests removeObject:key];
        if (accepted) gTserverRecentCallbackDigests[key] = @(NSDate.date.timeIntervalSince1970);
    }
}
