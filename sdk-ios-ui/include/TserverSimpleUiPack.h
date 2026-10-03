#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TserverUiContinueMode) {
    TserverUiContinueModeButton,
    TserverUiContinueModeOverlayTap
};

/// One-file native UI pack contract. The SDK owns authorization/network/session state;
/// the pack owns all visible layout, assets, motion and presentation interactions.
@interface TserverSimpleUiContext : NSObject
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy) NSDictionary *result;
@property(nonatomic, copy) NSDictionary *config;
@property(nonatomic, assign) BOOL blocksGameTouches;
@property(nonatomic, assign) TserverUiContinueMode continueMode;
@property(nonatomic, copy, nullable) dispatch_block_t startUuid;
@property(nonatomic, copy, nullable) void (^submitKey)(NSString *key);
@property(nonatomic, copy, nullable) dispatch_block_t retry;
@property(nonatomic, copy, nullable) dispatch_block_t continueAuth;
@property(nonatomic, copy, nullable) dispatch_block_t showNeedKey;
@property(nonatomic, copy, nullable) dispatch_block_t noticeClose;
@property(nonatomic, copy, nullable) dispatch_block_t noticeSnooze;
@end

/// Implement exactly one of these objects in each `templates/<id>/<Pack>.mm`.
/// Keep code in section order: background → hero → key → UUID → result → HUD → interactions.
@protocol TserverSimpleUiPack <NSObject>
- (UIView *)makeViewWithContext:(TserverSimpleUiContext *)context;
- (void)renderContext:(TserverSimpleUiContext *)context;
@end

/// Factory convention: class name must be `TserverPack_<manifest.rendererId>`.
/// Example rendererId `battle_pass` -> `@interface TserverPack_battle_pass`.
id<TserverSimpleUiPack> _Nullable TserverSimpleUiPackCreateForRenderer(NSString *rendererId);

/// Call once from host app/tweak when linking `libAPIClient.a` without `-ObjC`.
/// Keeps native pack Objective-C classes from being dead-stripped.
FOUNDATION_EXPORT void TserverForceLoadNativeUiPacks(void);

@interface TserverSimpleUiPackBase : NSObject <TserverSimpleUiPack>
@property(nonatomic, strong, readonly) UIView *root;
@property(nonatomic, strong, readonly) UIView *content;
@property(nonatomic, strong, readonly) UIStackView *stack;
@property(nonatomic, strong, nullable) UITextField *keyField;
@property(nonatomic, strong, nullable) TserverSimpleUiContext *context;
- (UIView *)makeViewWithContext:(TserverSimpleUiContext *)context;
- (void)renderContext:(TserverSimpleUiContext *)context;

/// Packs must call one shell installer from `makeViewWithContext:` (or rely on default card shell).
- (void)installCenteredCardShell;   // floating card (Cyber Terminal)
- (void)installFullscreenShell;     // edge-to-edge HUD (Battle Pass)

/// True when package orientation is landscape/ngang OR the screen is currently wider than tall.
/// Packs should use this to drop decorative command spam on short landscape screens.
- (BOOL)isCompactLandscape;

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight;
- (UIButton *)button:(NSString *)title action:(SEL)action;

/// Config helpers — packs should prefer these over hardcoded copy/colors.
- (NSString *)screenNameForStatus:(NSString *)status;
- (NSDictionary *)currentScreenConfig;
- (NSString *)screenString:(NSString *)key fallback:(NSString *)fallback;
- (UIColor *)styleColor:(NSString *)key fallback:(UIColor *)fallback;
- (UIColor *)accentColor;
- (UIColor *)textColor;
- (UIColor *)mutedTextColor;
- (UIColor *)cardColor;
- (UIColor *)dangerColor;
- (UIColor *)successColor;
- (TserverUiContinueMode)resolvedContinueMode;

- (void)buildDefaultKeyArea;
- (void)buildDefaultUuidArea;
- (void)buildDefaultResultArea;
- (void)buildDefaultNoticeArea;

// --- ONE-FILE PACK SECTIONS ---
- (void)buildBackground;      // solid, gradient, background/hero image
- (void)buildHero;            // logo, character/banner, HUD/radar decorative content
- (void)buildKeyArea;         // key field + submit control
- (void)buildUuidArea;        // UUID/profile instructions + start action
- (void)buildResultArea;      // valid/revoked/error copy and continue UI
- (void)buildNoticeArea;      // package announcement (status NOTICE), themed like the pack
- (void)buildHud;             // optional popup/progress/game notification
- (void)playEnterMotion;      // visual entrance only, honors Reduce Motion
- (void)playStatusMotion;     // status transition only, honors Reduce Motion
- (void)playHaptic:(NSString *)event; // tap | success | error
- (void)continueFromOverlay;  // never passes a touch to the game
- (void)openUpdateTapped:(UIButton *)sender; // UPDATE_REQUIRED → open updateUrl
- (void)changeKeyTapped;      // EXPIRED / REVOKED / error → switch to key entry
- (void)closeAndTerminateTapped; // fatal config error (no URL scheme) → quit
@end

NS_ASSUME_NONNULL_END
