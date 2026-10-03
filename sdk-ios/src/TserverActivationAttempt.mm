#import "TserverActivationAttempt.h"
#import "TserverAuth.h"
#import "TserverAuthorizationLease.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

NSString * const TserverActivationAttemptDidFinishNotification = @"com.tserver.activation.terminal";
static const NSTimeInterval kTserverActivationActiveTimeout = 35.0;
static dispatch_queue_t gTserverActivationQueue;
static void *gTserverActivationQueueKey = &gTserverActivationQueueKey;
static TserverActivationAttempt *gTserverCurrentActivation;
static NSUInteger gTserverActivationGeneration;
static NSMutableArray<NSDictionary *> *gTserverActivationDiagnostics;

@interface TserverActivationAttempt ()
@property(nonatomic, copy, readwrite) NSString *attemptId;
@property(nonatomic, readwrite) NSUInteger generation;
@property(nonatomic, readwrite, getter=isTerminal) BOOL terminal;
@property(nonatomic, copy) TserverActivationAttemptCompletion completion;
@property(nonatomic, strong) dispatch_source_t watchdog;
@property(nonatomic) NSTimeInterval remainingActiveSeconds;
@property(nonatomic) CFTimeInterval activeSince;
@property(nonatomic) BOOL suspended;
@property(nonatomic, copy) NSString *stage;
@end

@implementation TserverActivationAttempt

+ (void)initialize {
    if (self != TserverActivationAttempt.class) return;
    gTserverActivationQueue = dispatch_queue_create("com.tserver.activation-attempt", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(gTserverActivationQueue,
                                gTserverActivationQueueKey,
                                gTserverActivationQueueKey,
                                NULL);
}

static void TserverActivationSync(dispatch_block_t block) {
    if (dispatch_get_specific(gTserverActivationQueueKey)) {
        block();
    } else {
        dispatch_sync(gTserverActivationQueue, block);
    }
}

static NSString *TserverActivationIdentifier(void) {
    NSString *compact = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    return compact.length >= 12 ? [compact substringToIndex:12].lowercaseString : compact.lowercaseString;
}

static NSString *TserverString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

- (void)installLifecycleObservers {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(applicationWillSuspend:)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(applicationWillSuspend:)
                   name:UIApplicationDidEnterBackgroundNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(applicationDidResume:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
}

- (void)removeLifecycleObservers {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)cancelWatchdogLocked {
    if (!self.watchdog) return;
    dispatch_source_cancel(self.watchdog);
    self.watchdog = nil;
}

- (void)armWatchdogLocked {
    [self cancelWatchdogLocked];
    if (self.terminal || self.suspended) return;
    if (self.remainingActiveSeconds <= 0) {
        dispatch_async(gTserverActivationQueue, ^{
            [self finishWithResult:@{
                @"ok": @NO,
                @"status": TserverStatusActivationTimeout,
                @"message": @"Không nhận được kết quả kích hoạt. Vui lòng thử lại."
            } stage:@"timeout" errorCode:@"active_timeout"];
        });
        return;
    }

    self.activeSince = CACurrentMediaTime();
    self.watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gTserverActivationQueue);
    dispatch_source_set_timer(self.watchdog,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.remainingActiveSeconds * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              (uint64_t)(0.05 * NSEC_PER_SEC));
    __weak TserverActivationAttempt *weakSelf = self;
    dispatch_source_set_event_handler(self.watchdog, ^{
        TserverActivationAttempt *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.terminal || strongSelf.suspended) return;
        strongSelf.remainingActiveSeconds = 0;
        [strongSelf finishWithResult:@{
            @"ok": @NO,
            @"status": TserverStatusActivationTimeout,
            @"message": @"Không nhận được kết quả kích hoạt. Vui lòng thử lại."
        } stage:@"timeout" errorCode:@"active_timeout"];
    });
    dispatch_resume(self.watchdog);
}

- (void)applicationWillSuspend:(NSNotification *)notification {
    (void)notification;
    dispatch_async(gTserverActivationQueue, ^{
        if (self.terminal || self.suspended || gTserverCurrentActivation != self) return;
        CFTimeInterval elapsed = MAX(0, CACurrentMediaTime() - self.activeSince);
        self.remainingActiveSeconds = MAX(0, self.remainingActiveSeconds - elapsed);
        self.suspended = YES;
        [self cancelWatchdogLocked];
    });
}

- (void)applicationDidResume:(NSNotification *)notification {
    (void)notification;
    dispatch_async(gTserverActivationQueue, ^{
        if (self.terminal || !self.suspended || gTserverCurrentActivation != self) return;
        self.suspended = NO;
        [self armWatchdogLocked];
    });
}

+ (instancetype)beginWithCompletion:(TserverActivationAttemptCompletion)completion {
    __block TserverActivationAttempt *attempt;
    __block TserverActivationAttempt *superseded;
    BOOL initiallySuspended = UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    TserverActivationSync(^{
        superseded = gTserverCurrentActivation;
        if (superseded && !superseded.terminal) {
            [superseded finishWithResult:@{
                @"ok": @NO,
                @"status": TserverStatusActivationCancelled,
                @"message": @"Activation was superseded by a newer attempt."
            } stage:@"cancelled" errorCode:@"superseded"];
        }
        attempt = [TserverActivationAttempt new];
        attempt.attemptId = TserverActivationIdentifier();
        attempt.generation = ++gTserverActivationGeneration;
        attempt.completion = [completion copy];
        attempt.remainingActiveSeconds = kTserverActivationActiveTimeout;
        attempt.stage = @"preflight";
        attempt.suspended = initiallySuspended;
        gTserverCurrentActivation = attempt;
        [attempt armWatchdogLocked];
    });
    [attempt installLifecycleObservers];
    return attempt;
}

+ (BOOL)isActivationInFlight {
    __block BOOL active;
    TserverActivationSync(^{ active = gTserverCurrentActivation != nil && !gTserverCurrentActivation.terminal; });
    return active;
}

+ (NSUInteger)currentGeneration {
    __block NSUInteger generation;
    TserverActivationSync(^{ generation = gTserverActivationGeneration; });
    return generation;
}

+ (NSString *)currentAttemptId {
    __block NSString *attemptId;
    TserverActivationSync(^{ attemptId = [gTserverCurrentActivation.attemptId copy]; });
    return attemptId;
}

- (BOOL)isCurrent {
    __block BOOL current;
    TserverActivationSync(^{ current = gTserverCurrentActivation == self && !self.terminal; });
    return current;
}

- (void)updateStage:(NSString *)stage {
    if (stage.length == 0) return;
    dispatch_async(gTserverActivationQueue, ^{
        if (self.terminal) return;
        self.stage = [stage copy];
    });
}

- (BOOL)finishWithResult:(NSDictionary *)result
                   stage:(NSString *)stage
               errorCode:(NSString *)errorCode {
    __block BOOL accepted = NO;
    __block NSDictionary *terminalResult;
    __block TserverActivationAttemptCompletion completion;
    TserverActivationSync(^{
        if (self.terminal) return;
        self.terminal = YES;
        accepted = YES;
        [self cancelWatchdogLocked];
        if (gTserverCurrentActivation == self) gTserverCurrentActivation = nil;

        NSDictionary *safe = [result isKindOfClass:NSDictionary.class] ? result : @{};
        NSMutableDictionary *output = [safe mutableCopy];
        NSString *status = TserverString(output[@"status"]);
        if (status.length == 0) status = TserverStatusServerError;
        NSString *resolvedErrorCode = errorCode ?: @"";
        if ([status isEqualToString:TserverStatusNeedKey]) {
            status = TserverStatusServerError;
            output[@"message"] = @"Server không trả về kết quả kích hoạt hợp lệ.";
            if (resolvedErrorCode.length == 0) resolvedErrorCode = @"activation_returned_need_key";
        } else if ([status isEqualToString:TserverStatusNeedUUID]) {
            status = TserverStatusBadSession;
            output[@"message"] = @"Profile session không hợp lệ cho lần kích hoạt này.";
            if (resolvedErrorCode.length == 0) resolvedErrorCode = @"profile_session_required";
        }
        if ([status isEqualToString:TserverStatusValid] && !TserverAuthorizationLeaseAllowsCapability(@"paid")) {
            status = TserverStatusAuthorizationLeaseInvalid;
            output[@"message"] = @"Authorization lease does not grant paid capability";
            resolvedErrorCode = @"lease_capability_missing";
        }
        output[@"status"] = status;
        output[@"ok"] = @([status isEqualToString:TserverStatusValid]);
        output[@"terminal"] = @YES;
        output[@"attemptId"] = self.attemptId ?: @"";
        output[@"sdkBuild"] = TserverSDKBuildIdentifier ?: @"";
        NSString *requestId = TserverString(output[@"requestId"]);
        if (requestId.length > 0) {
            output[@"diagnosticId"] = requestId.length > 12 ? [requestId substringToIndex:12] : requestId;
        } else {
            output[@"diagnosticId"] = self.attemptId ?: @"";
        }
        output[@"stage"] = stage.length > 0 ? stage : (self.stage ?: @"terminal");
        output[@"errorCode"] = resolvedErrorCode.length > 0 ? resolvedErrorCode : [status lowercaseString];
        terminalResult = [output copy];
        gTserverActivationDiagnostics = gTserverActivationDiagnostics ?: [NSMutableArray array];
        [gTserverActivationDiagnostics addObject:@{
            @"attemptId": self.attemptId ?: @"",
            @"sdkBuild": TserverSDKBuildIdentifier ?: @"",
            @"stage": output[@"stage"] ?: @"terminal",
            @"status": output[@"status"] ?: TserverStatusServerError,
            @"errorCode": output[@"errorCode"] ?: @"unknown",
            @"httpStatus": output[@"httpStatus"] ?: @0,
            @"diagnosticId": output[@"diagnosticId"] ?: @""
        }];
        if (gTserverActivationDiagnostics.count > 24) [gTserverActivationDiagnostics removeObjectAtIndex:0];
        completion = [self.completion copy];
        self.completion = nil;
    });

    if (accepted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self removeLifecycleObservers];
            if (completion) completion(terminalResult);
            [NSNotificationCenter.defaultCenter postNotificationName:TserverActivationAttemptDidFinishNotification
                                                               object:nil
                                                             userInfo:@{ @"result": terminalResult ?: @{} }];
        });
    }
    return accepted;
}

+ (void)finishCurrentAsUnsafeWithMessage:(NSString *)message {
    __block TserverActivationAttempt *attempt;
    TserverActivationSync(^{ attempt = gTserverCurrentActivation; });
    [attempt finishWithResult:@{
        @"ok": @NO,
        @"status": TserverStatusUnsafeEnvironment,
        @"message": message.length > 0 ? message : @"Môi trường chạy không an toàn."
    } stage:@"security" errorCode:@"unsafe_environment"];
}

+ (void)publishTerminalResult:(NSDictionary *)result {
    NSDictionary *safe = [result isKindOfClass:NSDictionary.class] ? result : @{};
    NSMutableDictionary *output = [safe mutableCopy];
    output[@"terminal"] = @YES;
    if (![output[@"ok"] respondsToSelector:@selector(boolValue)]) output[@"ok"] = @NO;
    if (![output[@"status"] isKindOfClass:NSString.class]) output[@"status"] = TserverStatusServerError;
    if (![output[@"stage"] isKindOfClass:NSString.class]) output[@"stage"] = @"sdk";
    if (![output[@"errorCode"] isKindOfClass:NSString.class]) output[@"errorCode"] = @"sdk_terminal";
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:TserverActivationAttemptDidFinishNotification
                                                           object:nil
                                                         userInfo:@{ @"result": [output copy] }];
    });
}

@end
