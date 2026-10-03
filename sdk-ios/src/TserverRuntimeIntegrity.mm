#import "TserverRuntimeIntegrity.h"
#import "TserverSecurity.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>

static const uint32_t kTserverIntegrityCodeSignatureFlag = (1u << 11);
static const uint32_t kTserverIntegrityExecutableChangedFlag = (1u << 12);
static const uint32_t kTserverIntegrityKnownFlagMask = 0x1FFFu;

static dispatch_once_t gTserverIntegrityOnce;
static dispatch_queue_t gTserverIntegrityQueue;
static NSData *gTserverIntegrityBaselineDigest;
static NSString *gTserverIntegrityCodeSignature;
static NSString *gTserverIntegrityExecutableStatus;
static NSTimeInterval gTserverIntegrityLastDigestAt = 0;

static NSString * const kTserverIntegrityKeychainService = @"com.tserver.runtime-integrity";
static NSString * const kTserverIntegrityDeviceSaltAccount = @"device-salt-v1";

static NSString *TserverIntegrityExecutablePath(void) {
    NSString *path = [NSBundle.mainBundle executablePath];
    if (path.length > 0) return path;
    const char *image = _dyld_get_image_name(0);
    return image && image[0] ? [NSString stringWithUTF8String:image] : @"";
}

static NSString *TserverIntegrityDeviceSalt(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kTserverIntegrityKeychainService,
        (__bridge id)kSecAttrAccount: kTserverIntegrityDeviceSaltAccount,
        (__bridge id)kSecReturnData: @YES
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecSuccess && result) {
        NSData *data = CFBridgingRelease(result);
        NSString *salt = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (salt.length >= 32) return salt;
    }

    uint8_t bytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
        arc4random_buf(bytes, sizeof(bytes));
    }
    NSMutableString *salt = [NSMutableString stringWithCapacity:sizeof(bytes) * 2];
    for (size_t index = 0; index < sizeof(bytes); index++) {
        [salt appendFormat:@"%02x", bytes[index]];
    }
    NSData *saltData = [salt dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *item = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kTserverIntegrityKeychainService,
        (__bridge id)kSecAttrAccount: kTserverIntegrityDeviceSaltAccount,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        (__bridge id)kSecValueData: saltData
    };
    OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (addStatus == errSecDuplicateItem) {
        NSDictionary *updateQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kTserverIntegrityKeychainService,
            (__bridge id)kSecAttrAccount: kTserverIntegrityDeviceSaltAccount
        };
        (void)SecItemUpdate((__bridge CFDictionaryRef)updateQuery,
                            (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: saltData});
    }
    return salt;
}

static NSString *TserverIntegrityDeviceBinding(void) {
    NSString *idfv = [UIDevice.currentDevice identifierForVendor].UUIDString;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *salt = TserverIntegrityDeviceSalt();
    if (idfv.length == 0 || bundle.length == 0 || salt.length < 32) return @"";
    NSString *material = [NSString stringWithFormat:@"%@|%@|%@", salt, bundle.lowercaseString, idfv];
    NSData *data = [material dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *value = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (size_t index = 0; index < sizeof(digest); index++) {
        [value appendFormat:@"%02x", digest[index]];
    }
    return value;
}

static BOOL TserverIntegrityPathIsInsideBundle(NSString *path) {
    NSString *bundlePath = [NSBundle.mainBundle bundlePath];
    if (path.length == 0 || bundlePath.length == 0) return NO;
    NSString *normalizedBundle = [bundlePath stringByStandardizingPath];
    NSString *normalizedPath = [path stringByStandardizingPath];
    if (![normalizedPath hasPrefix:[normalizedBundle stringByAppendingString:@"/"]]) return NO;
    return YES;
}

static NSString *TserverIntegrityCheckCodeSignature(NSString *path) {
    if (!TserverIntegrityPathIsInsideBundle(path)) return @"invalid";
    NSURL *url = [NSURL fileURLWithPath:path];
    if (!url) return @"unknown";

    // SecStaticCode APIs are not exposed by every iOS SDK. Resolve them
    // dynamically so the release remains buildable on iOS while gaining code
    // signature validation on platforms that provide the symbols.
    typedef CFTypeRef (*TserverCreateStaticCodeFn)(CFURLRef, CFOptionFlags, CFErrorRef *);
    typedef OSStatus (*TserverCheckStaticCodeFn)(CFTypeRef, CFOptionFlags, CFTypeRef, CFErrorRef *);
    TserverCreateStaticCodeFn createFn = (TserverCreateStaticCodeFn)dlsym(RTLD_DEFAULT, "SecStaticCodeCreateWithPath");
    TserverCheckStaticCodeFn checkFn = (TserverCheckStaticCodeFn)dlsym(RTLD_DEFAULT, "SecStaticCodeCheckValidity");
    if (!createFn || !checkFn) return @"unknown";

    CFErrorRef createError = NULL;
    CFTypeRef code = createFn((__bridge CFURLRef)url, 0, &createError);
    if (createError) CFRelease(createError);
    if (!code) return @"unknown";

    CFErrorRef validationError = NULL;
    OSStatus validationStatus = checkFn(code, 0, NULL, &validationError);
    if (validationError) CFRelease(validationError);
    CFRelease(code);
    return validationStatus == errSecSuccess ? @"valid" : @"invalid";
}

static NSData *TserverIntegrityDigestExecutable(NSString *path) {
    if (path.length == 0) return nil;
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return nil;

    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    uint8_t buffer[16384];
    for (;;) {
        ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count < 0) {
            close(fd);
            return nil;
        }
        if (count == 0) break;
        CC_SHA256_Update(&ctx, buffer, (CC_LONG)count);
    }
    close(fd);

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static void TserverIntegrityInitializeLocked(void) {
    NSString *path = TserverIntegrityExecutablePath();
    gTserverIntegrityCodeSignature = [TserverIntegrityCheckCodeSignature(path) copy];
    gTserverIntegrityBaselineDigest = TserverIntegrityDigestExecutable(path);
    gTserverIntegrityExecutableStatus = gTserverIntegrityBaselineDigest ? @"stable" : @"unknown";
    gTserverIntegrityLastDigestAt = [NSDate date].timeIntervalSince1970;
}

void TserverRuntimeIntegrityInitialize(void) {
    dispatch_once(&gTserverIntegrityOnce, ^{
        gTserverIntegrityQueue = dispatch_queue_create("com.tserver.runtime-integrity", DISPATCH_QUEUE_SERIAL);
        TserverIntegrityInitializeLocked();
    });
}

NSString *TserverRuntimeIntegrityCodeSignatureStatus(void) {
    __block NSString *status = nil;
    TserverRuntimeIntegrityInitialize();
    dispatch_sync(gTserverIntegrityQueue, ^{
        status = [gTserverIntegrityCodeSignature copy] ?: @"unknown";
    });
    return status;
}

NSString *TserverRuntimeIntegrityExecutableStatus(void) {
    TserverRuntimeIntegrityInitialize();
    __block NSString *status = @"unknown";
    dispatch_sync(gTserverIntegrityQueue, ^{
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (gTserverIntegrityLastDigestAt > 0 && now - gTserverIntegrityLastDigestAt < 5.0) {
            status = [gTserverIntegrityExecutableStatus copy] ?: @"unknown";
            return;
        }
        gTserverIntegrityLastDigestAt = now;
        NSData *current = TserverIntegrityDigestExecutable(TserverIntegrityExecutablePath());
        if (!current || !gTserverIntegrityBaselineDigest) {
            gTserverIntegrityExecutableStatus = @"unknown";
        } else {
            gTserverIntegrityExecutableStatus = [current isEqualToData:gTserverIntegrityBaselineDigest] ? @"stable" : @"changed";
        }
        status = [gTserverIntegrityExecutableStatus copy] ?: @"unknown";
    });
    return status;
}

NSUInteger TserverRuntimeIntegrityFlags(void) {
    uint32_t flags = (uint32_t)TserverSecurityRuntimeRiskFlags();
    if ([TserverRuntimeIntegrityCodeSignatureStatus() isEqualToString:@"invalid"]) {
        flags |= kTserverIntegrityCodeSignatureFlag;
    }
    if ([TserverRuntimeIntegrityExecutableStatus() isEqualToString:@"changed"]) {
        flags |= kTserverIntegrityExecutableChangedFlag;
    }
    return flags & kTserverIntegrityKnownFlagMask;
}

NSDictionary *TserverRuntimeIntegrityContext(void) {
    NSMutableDictionary *context = [@{
        @"v": @1,
        @"flags": @(TserverRuntimeIntegrityFlags()),
        @"codeSignature": TserverRuntimeIntegrityCodeSignatureStatus(),
        @"executable": TserverRuntimeIntegrityExecutableStatus()
    } mutableCopy];
    NSString *deviceBinding = TserverIntegrityDeviceBinding();
    if (deviceBinding.length > 0) context[@"deviceBinding"] = deviceBinding;
    return [context copy];
}
