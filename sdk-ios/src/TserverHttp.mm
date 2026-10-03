#import <Foundation/Foundation.h>
#import "TserverPinning.h"
#import "TserverClientIdentity.h"
#import "TserverSecurity.h"
#import "TserverTransportSession.h"
#import "TserverSealedConstants.h"
#import "TserverStringCrypto.h"
#import "APIClient.h"

@interface TserverCrypto : NSObject
+ (NSString *)jsonStringForObject:(id)object;
+ (NSString *)randomNonce;
+ (NSNumber *)currentTimestamp;
+ (NSDictionary *)encryptTransportPayloadV3:(id)payload
                                     rawKey:(NSData *)rawKey
                                  sessionId:(NSString *)sessionId
                                  direction:(NSString *)direction
                                     method:(NSString *)method
                                       path:(NSString *)path
                                      nonce:(NSString *)nonce
                                 statusCode:(NSInteger)statusCode;
+ (NSDictionary *)decryptTransportEnvelopeV3:(NSDictionary *)envelope
                                      rawKey:(NSData *)rawKey
                                   sessionId:(NSString *)sessionId
                                   direction:(NSString *)direction
                                      method:(NSString *)method
                                        path:(NSString *)path
                                       nonce:(NSString *)nonce
                                  statusCode:(NSInteger)statusCode;
+ (BOOL)isTransportEnvelope:(id)value;
+ (BOOL)isTransportEnvelopeV3:(id)value;
+ (NSDictionary *)clientIdentityHeadersForMethod:(NSString *)method
                                            path:(NSString *)path
                                            body:(NSDictionary *)body
                                       timestamp:(NSString *)timestamp
                                           nonce:(NSString *)nonce;
@end

@interface TserverHttp : NSObject
+ (void)get:(NSString *)url
    headers:(NSDictionary *)headers
 completion:(void (^)(NSDictionary *result, NSError *error))completion;

+ (void)post:(NSString *)url
        body:(NSDictionary *)body
     headers:(NSDictionary *)headers
  completion:(void (^)(NSDictionary *result, NSError *error))completion;

+ (void)requestWithFailover:(NSArray<NSString *> *)urls
                       body:(NSDictionary *)body
                    headers:(NSDictionary *)headers
                 completion:(void (^)(NSDictionary *result, NSError *error, NSString *workingURL))completion;
@end

@implementation TserverHttp

+ (BOOL)isAllowedProductionURL:(NSURL *)url {
    if (!url || url.user.length > 0 || url.password.length > 0 || url.fragment.length > 0 || url.query.length > 2048) return NO;
    if (![url.scheme.lowercaseString isEqualToString:TS_OBF_NS("https")]) return NO;
    if (url.port && url.port.integerValue != 443) return NO;
    const char *sealedHost = TserverSealedStringAt(kTserverSealedStr_ApiHost);
    NSString *productionHost = sealedHost && sealedHost[0]
        ? [[NSString stringWithUTF8String:sealedHost] lowercaseString]
        : @"";
    return productionHost.length > 0 && [url.host.lowercaseString isEqualToString:productionHost];
}

+ (void)get:(NSString *)url
    headers:(NSDictionary *)headers
 completion:(void (^)(NSDictionary *result, NSError *error))completion {
    NSMutableURLRequest *request = [self requestWithURL:url method:TS_OBF_NS("GET") headers:headers body:nil errorHandler:completion];
    if (!request) return;
    [self runRequest:request completion:completion];
}

+ (void)post:(NSString *)url
        body:(NSDictionary *)body
     headers:(NSDictionary *)headers
  completion:(void (^)(NSDictionary *result, NSError *error))completion {
    // Package APIs (except handshake): ensure ECDH session first so body crypto is dynamic.
    BOOL needsSession = [self shouldEncryptTransportForURL:url] && ![TserverTransportSession isHandshakeURL:url];
    if (needsSession && ![TserverTransportSession hasUsableSession]) {
        NSURL *u = [NSURL URLWithString:url ?: @""];
        NSString *base = @"";
        if (u.scheme.length && u.host.length) {
            base = [NSString stringWithFormat:TS_OBF_NS("%@://%@"), u.scheme, u.host];
            if (u.port) base = [base stringByAppendingFormat:@":%@", u.port];
        }
        if (base.length == 0) {
            const char *sealedHost = TserverSealedStringAt(kTserverSealedStr_ApiHost);
            const char *scheme = TserverSealedStringAt(kTserverSealedStr_HttpsScheme);
            if (sealedHost && sealedHost[0] && scheme && scheme[0]) {
                base = [@(scheme) stringByAppendingString:[NSString stringWithUTF8String:sealedHost]];
            }
        }
        [TserverTransportSession ensureSessionWithBaseURL:base completion:^(BOOL ok) {
            if (!ok) {
                NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                     code:-1063
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Transport session required"}];
                [self complete:completion result:nil error:error];
                return;
            }
            NSMutableURLRequest *request = [self requestWithURL:url method:@"POST" headers:headers body:body errorHandler:completion];
            if (!request) return;
            [self runRequest:request completion:completion];
        }];
        return;
    }
    NSMutableURLRequest *request = [self requestWithURL:url method:TS_OBF_NS("POST") headers:headers body:body errorHandler:completion];
    if (!request) return;
    [self runRequest:request completion:completion];
}

+ (void)requestWithFailover:(NSArray<NSString *> *)urls
                       body:(NSDictionary *)body
                    headers:(NSDictionary *)headers
                 completion:(void (^)(NSDictionary *result, NSError *error, NSString *workingURL))completion {
    [self requestWithFailover:urls body:body headers:headers index:0 completion:completion];
}

+ (void)requestWithFailover:(NSArray<NSString *> *)urls
                       body:(NSDictionary *)body
                    headers:(NSDictionary *)headers
                      index:(NSUInteger)index
                 completion:(void (^)(NSDictionary *result, NSError *error, NSString *workingURL))completion {
    if (index >= urls.count) {
        NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                             code:-1009
                                         userInfo:@{NSLocalizedDescriptionKey: @"All endpoints failed"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, error, nil);
        });
        return;
    }
    NSString *url = urls[index];
    NSTimeInterval startedAt = [NSDate date].timeIntervalSince1970;
    [self post:url body:body headers:headers completion:^(NSDictionary *result, NSError *error) {
        NSTimeInterval latency = ([NSDate date].timeIntervalSince1970) - startedAt;
        if (error) {
            TserverDiagnosticsPostNetwork(NO, latency);
            if ([self isFatalTrustFailure:error]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(nil, error, nil);
                });
                return;
            }
            [self requestWithFailover:urls body:body headers:headers index:index + 1 completion:completion];
            return;
        }
        TserverDiagnosticsPostNetwork(YES, latency);
        completion(result, nil, url);
    }];
}

+ (BOOL)isFatalTrustFailure:(NSError *)error {
    if (!error) return NO;
    // TLS / certificate failures must abort the failover chain instead of
    // silently falling through to the next URL — falling through masked MITM /
    // pinning failures on the primary endpoint.
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        NSInteger code = error.code;
        if (code == NSURLErrorSecureConnectionFailed ||
            code == NSURLErrorServerCertificateHasBadDate ||
            code == NSURLErrorServerCertificateHasUnknownRoot ||
            code == NSURLErrorServerCertificateNotYetValid ||
            code == NSURLErrorServerCertificateUntrusted ||
            (code >= -1300 && code <= -1200)) {
            return YES;
        }
    }
    if ([error.domain isEqualToString:@"com.tserver.http"]) {
        // -1200 = TLS pin evidence missing; -1061/-1062 = transport envelope
        // verification failed. Retrying a fresh URL would mask tampering.
        if (error.code == -1200 || error.code == -1061 || error.code == -1062) return YES;
    }
    return NO;
}

+ (NSMutableDictionary *)signedHeadersMerging:(NSDictionary *)headers
                                       method:(NSString *)method
                                          url:(NSString *)url
                                         body:(NSDictionary *)body
                                    timestamp:(NSString *)timestamp
                                        nonce:(NSString *)nonce {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if ([headers isKindOfClass:NSDictionary.class]) {
        [out addEntriesFromDictionary:headers];
    }

    // Do NOT put CLIENT_API_KEY on the wire for package APIs.
    // Transport v3 proves possession via ECDSA client identity (kid+sig).
    const char *hClient = TserverSealedStringAt(kTserverSealedStr_XClientApiKey);
    if (hClient && hClient[0]) [out removeObjectForKey:@(hClient)];
    [out removeObjectForKey:TS_OBF_NS("x-tserver-api-key")];
    [out removeObjectForKey:TS_OBF_NS("x-app-api-key")];
    [out removeObjectForKey:TS_OBF_NS("X-Client-Api-Key")];
    [out removeObjectForKey:TS_OBF_NS("X-Tserver-Api-Key")];
    // Hard-cut: never send legacy shared-key HMAC.
    const char *hLegacySig = TserverSealedStringAt(kTserverSealedStr_XTsSignature);
    if (hLegacySig && hLegacySig[0]) [out removeObjectForKey:@(hLegacySig)];
    [out removeObjectForKey:TS_OBF_NS("x-ts-signature")];

    NSString *path = @"/";
    NSURL *u = [NSURL URLWithString:url ?: @""];
    if (u.path.length > 0) path = u.path;
    NSString *ts = timestamp ?: @"";
    NSString *requestNonce = nonce ?: @"";
    NSDictionary *identity = [TserverCrypto clientIdentityHeadersForMethod:(method ?: @"POST")
                                                                      path:path
                                                                      body:body ?: @{}
                                                                 timestamp:ts
                                                                     nonce:requestNonce];
    if ([identity isKindOfClass:NSDictionary.class]) {
        [out addEntriesFromDictionary:identity];
    }
    return out;
}

+ (BOOL)shouldEncryptTransportForURL:(NSString *)url {
    // Package public APIs only — member/admin portal traffic stays plain JSON over TLS.
    NSString *path = [NSURL URLWithString:url ?: @""].path.lowercaseString ?: @"";
    const char *pToken = TserverSealedStringAt(kTserverSealedStr_TokenApi);
    const char *pPkg = TserverSealedStringAt(kTserverSealedStr_V1Package);
    if (pToken && pToken[0] && [path hasPrefix:@(pToken)]) return YES;
    if (pPkg && pPkg[0] && [path hasPrefix:@(pPkg)]) return YES;
    return NO;
}

+ (NSMutableURLRequest *)requestWithURL:(NSString *)url
                                 method:(NSString *)method
                                headers:(NSDictionary *)headers
                                   body:(NSDictionary *)body
                           errorHandler:(void (^)(NSDictionary *result, NSError *error))completion {
    NSURL *requestURL = [NSURL URLWithString:url ?: @""];
    if (![self isAllowedProductionURL:requestURL]) {
        NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                             code:-1000
                                         userInfo:@{NSLocalizedDescriptionKey: @"Production HTTPS endpoint required"}];
        [self complete:completion result:nil error:error];
        return nil;
    }

    NSDictionary *wireBody = body;
    BOOL useTransportEnc = [method isEqualToString:TS_OBF_NS("POST")] && [self shouldEncryptTransportForURL:url];
    BOOL isHandshake = [TserverTransportSession isHandshakeURL:url];
    // Transport v3: handshake stays plaintext; package bodies use AES-GCM session crypto.
    NSData *sessionKey = isHandshake ? nil : [TserverTransportSession sessionKey];
    NSString *sessionId = isHandshake ? nil : [TserverTransportSession sessionId];
    NSInteger transportVersion = isHandshake ? 0 : [TserverTransportSession transportVersion];
    NSString *timestamp = [[TserverCrypto currentTimestamp] stringValue];
    NSString *nonce = [TserverCrypto randomNonce] ?: @"";
    NSString *requestPath = requestURL.path.length > 0 ? requestURL.path : @"/";
    if (timestamp.length == 0 || nonce.length < 16) {
        NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                             code:-1072
                                         userInfo:@{NSLocalizedDescriptionKey: @"Request freshness material unavailable"}];
        [self complete:completion result:nil error:error];
        return nil;
    }
    BOOL expectEnc = NO;
    if (useTransportEnc && !isHandshake) {
        NSDictionary *sealed = nil;
        if (transportVersion == 3 && sessionKey.length == 32 && sessionId.length > 0) {
            sealed = [TserverCrypto encryptTransportPayloadV3:body ?: @{}
                                                       rawKey:sessionKey
                                                    sessionId:sessionId
                                                    direction:TS_OBF_NS("c2s")
                                                       method:method
                                                         path:requestPath
                                                        nonce:nonce
                                                   statusCode:0];
        }
        if (sealed.count > 0) {
            wireBody = sealed;
            expectEnc = YES;
        } else {
            NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                 code:-1060
                                             userInfo:@{NSLocalizedDescriptionKey: @"Transport v3 encrypt failed"}];
            [self complete:completion result:nil error:error];
            return nil;
        }
    }

    NSMutableDictionary *mergedHeaders = [headers isKindOfClass:NSDictionary.class]
        ? [headers mutableCopy]
        : [NSMutableDictionary dictionary];
    if (expectEnc) {
        const char *hEnc = TserverSealedStringAt(kTserverSealedStr_XTsEnc);
        const char *hSid = TserverSealedStringAt(kTserverSealedStr_XTsSid);
        if (!(hEnc && hEnc[0])) {
            NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                 code:-1071
                                             userInfo:@{NSLocalizedDescriptionKey: @"Sealed transport header unavailable"}];
            [self complete:completion result:nil error:error];
            return nil;
        }
        mergedHeaders[@(hEnc)] = @"3";
        if (!(hSid && hSid[0] && sessionId.length > 0)) {
            NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                 code:-1063
                                             userInfo:@{NSLocalizedDescriptionKey: @"Transport v3 session missing"}];
            [self complete:completion result:nil error:error];
            return nil;
        }
        mergedHeaders[@(hSid)] = sessionId;
    }
    NSDictionary *finalHeaders = [self signedHeadersMerging:mergedHeaders
                                                       method:method
                                                          url:url
                                                         body:wireBody
                                                    timestamp:timestamp
                                                        nonce:nonce];
    NSString *kidHdr = finalHeaders[TS_OBF_NS("x-ts-client-kid")];
    NSString *sigHdr = finalHeaders[TS_OBF_NS("x-ts-client-sig")];
    if (![kidHdr isKindOfClass:NSString.class] || kidHdr.length == 0 ||
        ![sigHdr isKindOfClass:NSString.class] || sigHdr.length == 0) {
        NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                             code:-1073
                                         userInfo:@{NSLocalizedDescriptionKey: @"Client identity attestation unavailable"}];
        [self complete:completion result:nil error:error];
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    request.HTTPMethod = method;
    request.timeoutInterval = 8.0;
    const char *jsonType = TserverSealedStringAt(kTserverSealedStr_ApplicationJson);
    if (!(jsonType && jsonType[0])) {
        NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                             code:-1070
                                         userInfo:@{NSLocalizedDescriptionKey: @"Sealed content-type unavailable"}];
        [self complete:completion result:nil error:error];
        return nil;
    }
    NSString *acceptType = @(jsonType);
    [request setValue:acceptType forHTTPHeaderField:TS_OBF_NS("Accept")];

    [finalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *headerName = [key isKindOfClass:NSString.class] ? key : [key description];
        NSString *headerValue = [obj isKindOfClass:NSString.class] ? obj : [obj description];
        if (headerName.length > 0 && headerValue.length > 0) {
            [request setValue:headerValue forHTTPHeaderField:headerName];
        }
    }];

    if ([method isEqualToString:TS_OBF_NS("POST")]) {
        NSString *json = [TserverCrypto jsonStringForObject:wireBody ?: @{}];
        request.HTTPBody = [json dataUsingEncoding:NSUTF8StringEncoding];
        [request setValue:acceptType forHTTPHeaderField:TS_OBF_NS("Content-Type")];
    }
    // Response decrypt path reads x-ts-enc from the outgoing request snapshot.
    if (expectEnc) {
        const char *hEnc = TserverSealedStringAt(kTserverSealedStr_XTsEnc);
        if (!(hEnc && hEnc[0])) {
            NSError *error = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                 code:-1071
                                             userInfo:@{NSLocalizedDescriptionKey: @"Sealed transport header unavailable"}];
            [self complete:completion result:nil error:error];
            return nil;
        }
        [request setValue:@"3" forHTTPHeaderField:@(hEnc)];
    }
    return request;
}

+ (void)runRequest:(NSURLRequest *)request
        completion:(void (^)(NSDictionary *result, NSError *error))completion {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 8.0;
    config.timeoutIntervalForResource = 8.0;
    // Do not use system HTTP proxy / URLSession cache for package traffic.
    config.connectionProxyDictionary = @{};
    config.URLCache = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    config.URLCredentialStorage = nil;
    config.HTTPMaximumConnectionsPerHost = 2;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:[TserverPinning shared]
                                                     delegateQueue:nil];
    const char *hEncCheck = TserverSealedStringAt(kTserverSealedStr_XTsEnc);
    const char *hSidCheck = TserverSealedStringAt(kTserverSealedStr_XTsSid);
    const char *hNonceCheck = TserverSealedStringAt(kTserverSealedStr_XTsNonce);
    NSString *transportHeader = (hEncCheck && hEncCheck[0]) ? [request valueForHTTPHeaderField:@(hEncCheck)] : @"";
    NSInteger expectedTransportVersion = transportHeader.integerValue;
    BOOL expectEnc = expectedTransportVersion == 3;
    NSString *requestSessionId = (hSidCheck && hSidCheck[0]) ? [request valueForHTTPHeaderField:@(hSidCheck)] : @"";
    NSString *requestNonce = (hNonceCheck && hNonceCheck[0]) ? [request valueForHTTPHeaderField:@(hNonceCheck)] : @"";
    NSString *requestMethod = request.HTTPMethod.uppercaseString ?: @"POST";
    NSString *requestPath = request.URL.path.length > 0 ? request.URL.path : @"/";
    NSData *requestSessionKey = nil;
    if (expectedTransportVersion == 3 &&
        requestSessionId.length > 0 &&
        [requestSessionId isEqualToString:[TserverTransportSession sessionId]] &&
        [TserverTransportSession transportVersion] == 3) {
        requestSessionKey = [TserverTransportSession sessionKey];
    }
    if (expectedTransportVersion == 3 && (requestSessionKey.length != 32 || requestNonce.length < 16)) {
        NSError *contextError = [NSError errorWithDomain:@"com.tserver.http"
                                                     code:-1063
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Transport v3 request snapshot invalid"}];
        [self complete:completion result:nil error:contextError];
        [session finishTasksAndInvalidate];
        return;
    }
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error) {
            NSMutableDictionary *info = [error.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
            if (http.statusCode > 0) info[@"httpStatus"] = @(http.statusCode);
            NSError *annotatedError = [NSError errorWithDomain:error.domain code:error.code userInfo:info];
            [self complete:completion result:nil error:annotatedError];
            [session finishTasksAndInvalidate];
            return;
        }

        NSURL *responseURL = http.URL;
        BOOL responseContextValid = [self isAllowedProductionURL:responseURL] &&
            [responseURL.host caseInsensitiveCompare:request.URL.host ?: @""] == NSOrderedSame &&
            TserverPinningConsumeValidatedSession(session, request.URL.host ?: @"");
        if (!responseContextValid) {
            NSError *trustError = [NSError errorWithDomain:@"com.tserver.http"
                                                      code:-1200
                                                  userInfo:@{NSLocalizedDescriptionKey: @"TLS pin evidence missing"}];
            [self complete:completion result:nil error:trustError];
            [session finishTasksAndInvalidate];
            return;
        }
        if (data.length > 1024 * 1024) {
            NSError *sizeError = [NSError errorWithDomain:@"com.tserver.http"
                                                     code:-1103
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Response exceeds size limit"}];
            [self complete:completion result:nil error:sizeError];
            [session finishTasksAndInvalidate];
            return;
        }

        NSDictionary *json = nil;
        if (data.length > 0) {
            id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([value isKindOfClass:NSDictionary.class]) {
                json = (NSDictionary *)value;
            }
        }

        if (json) {
            if ([TserverCrypto isTransportEnvelope:json] || [TserverCrypto isTransportEnvelopeV3:json]) {
                NSDictionary *opened = nil;
                if (expectedTransportVersion == 3) {
                    __block NSString *responseSessionId = @"";
                    __block NSString *responseTransportVersion = @"";
                    [http.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
                        NSString *name = [key description];
                        if ([name caseInsensitiveCompare:TS_OBF_NS("x-ts-sid")] == NSOrderedSame) responseSessionId = [value description];
                        if ([name caseInsensitiveCompare:TS_OBF_NS("x-ts-enc")] == NSOrderedSame) responseTransportVersion = [value description];
                    }];
                    BOOL responseSessionMatches = [responseSessionId isEqualToString:requestSessionId] &&
                        [responseTransportVersion integerValue] == 3 && [TserverCrypto isTransportEnvelopeV3:json];
                    if (responseSessionMatches) {
                        opened = [TserverCrypto decryptTransportEnvelopeV3:json
                                                                    rawKey:requestSessionKey
                                                                 sessionId:requestSessionId
                                                                 direction:TS_OBF_NS("s2c")
                                                                    method:requestMethod
                                                                      path:requestPath
                                                                     nonce:requestNonce
                                                                statusCode:http.statusCode];
                    }
                }
                if (![opened isKindOfClass:NSDictionary.class]) {
                    NSError *decryptError = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                                code:-1061
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Transport v3 response verification failed"}];
                    [self complete:completion result:nil error:decryptError];
                    [session finishTasksAndInvalidate];
                    return;
                }
                json = opened;
            } else if (expectEnc) {
                NSString *status = [json[@"status"] isKindOfClass:NSString.class] ? json[@"status"] : @"";
                id okValue = json[@"ok"];
                BOOL explicitFailure = [okValue respondsToSelector:@selector(boolValue)] && ![okValue boolValue];
                NSSet<NSString *> *allowedPlainErrors = [NSSet setWithArray:@[
                    @"INVALID_CLIENT_API_KEY", @"BAD_CLIENT_SIGNATURE", @"REPLAY_REQUEST",
                    @"CLIENT_IDENTITY_REQUIRED", @"RATE_LIMITED", @"TRANSPORT_SESSION_REQUIRED",
                    @"BAD_TRANSPORT_CRYPTO", @"VALIDATION_ERROR", @"SERVER_ERROR"
                ]];
                BOOL allowedError = http.statusCode >= 400 && explicitFailure && [allowedPlainErrors containsObject:status];
                if (!allowedError) {
                    NSError *decryptError = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                                code:-1062
                                                            userInfo:@{NSLocalizedDescriptionKey: @"Expected Transport v3 encrypted response"}];
                    [self complete:completion result:nil error:decryptError];
                    [session finishTasksAndInvalidate];
                    return;
                }
            }
            NSMutableDictionary *annotated = [json mutableCopy];
            __block NSString *requestId = nil;
            [http.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
                if ([[key description] caseInsensitiveCompare:TS_OBF_NS("x-request-id")] == NSOrderedSame) {
                    requestId = [value description];
                    *stop = YES;
                }
            }];
            // The server signs the decrypted JSON before this HTTP layer sees it.
            // Keep local transport annotations in a reserved container so they do
            // not alter the HMAC payload in TserverCrypto.
            NSMutableDictionary *meta = [NSMutableDictionary dictionary];
            if (requestId.length > 0) meta[@"requestId"] = requestId;
            if (http.statusCode > 0) meta[@"httpStatus"] = @(http.statusCode);
            if (meta.count > 0) annotated[@"_tserverClientResponseMeta"] = [meta copy];
            [self complete:completion result:[annotated copy] error:nil];
            [session finishTasksAndInvalidate];
            return;
        }

        NSInteger statusCode = http ? http.statusCode : 0;
        NSString *message = statusCode >= 400
            ? [NSString stringWithFormat:@"HTTP %ld returned non-JSON response", (long)statusCode]
            : @"Response was not valid JSON";
        NSError *parseError = [NSError errorWithDomain:TS_OBF_NS("com.tserver.http")
                                                  code:statusCode >= 400 ? statusCode : -1001
                                              userInfo:@{NSLocalizedDescriptionKey: message}];
        [self complete:completion result:nil error:parseError];
        [session finishTasksAndInvalidate];
    }];
    [task resume];
}

+ (void)complete:(void (^)(NSDictionary *result, NSError *error))completion
          result:(NSDictionary *)result
           error:(NSError *)error {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(result, error);
    });
}

@end
