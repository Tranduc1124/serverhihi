#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TserverActivationAttemptCompletion)(NSDictionary *result);
FOUNDATION_EXPORT NSString * const TserverActivationAttemptDidFinishNotification;

/// Owns one key activation from preflight through an immutable terminal result.
/// All ownership changes are serialized; every begun attempt delivers exactly one
/// completion, including attempts superseded by a newer key submission.
@interface TserverActivationAttempt : NSObject

@property(nonatomic, copy, readonly) NSString *attemptId;
@property(nonatomic, readonly) NSUInteger generation;
@property(nonatomic, readonly, getter=isTerminal) BOOL terminal;

+ (instancetype)beginWithCompletion:(nullable TserverActivationAttemptCompletion)completion;

+ (BOOL)isActivationInFlight;
+ (NSUInteger)currentGeneration;
+ (nullable NSString *)currentAttemptId;

- (BOOL)isCurrent;
- (void)updateStage:(NSString *)stage;

/// Returns YES only for the first terminal result accepted for this attempt.
- (BOOL)finishWithResult:(nullable NSDictionary *)result
                   stage:(nullable NSString *)stage
               errorCode:(nullable NSString *)errorCode;

/// Fail the live attempt when a verified security transition denies sensitive work.
+ (void)finishCurrentAsUnsafeWithMessage:(nullable NSString *)message;

/// Publishes a non-activation terminal SDK event (startup, callback, or UI).
+ (void)publishTerminalResult:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
