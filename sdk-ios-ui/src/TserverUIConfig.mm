#import <UIKit/UIKit.h>
#import "TserverCustomerUI.h"

@interface TserverTheme : NSObject
+ (UIColor *)colorFromHex:(NSString *)hex fallback:(UIColor *)fallback;
@end

@interface TserverUIConfig : NSObject
@property(nonatomic, strong) NSString *theme;
@property(nonatomic, strong) NSString *layout;
@property(nonatomic, strong) NSString *templateName;
@property(nonatomic, strong) NSDictionary *rawConfig;
@property(nonatomic, strong) NSDictionary *style;
@property(nonatomic, strong) NSDictionary *screens;
@property(nonatomic, strong) NSDictionary *assets;
@property(nonatomic, strong) NSDictionary *flow;
@property(nonatomic, strong) NSDictionary *geometry;
@property(nonatomic, strong) NSDictionary *animation;
@property(nonatomic, strong) NSDictionary *typography;
@property(nonatomic, strong) NSDictionary *icons;
@property(nonatomic, strong) NSDictionary *popup;
@property(nonatomic, strong) NSDictionary *uiTemplates;
/// portrait | landscape — if landscape, gate UI locks to horizontal card layout.
@property(nonatomic, strong) NSString *orientation;
+ (instancetype)configFromDictionary:(NSDictionary *)dict;
+ (instancetype)defaultConfig;
- (NSDictionary *)screenConfig:(NSString *)screenName;
- (UIColor *)colorForKey:(NSString *)key fallback:(UIColor *)fallback;
- (CGFloat)radius;
- (BOOL)blurEnabled;
- (BOOL)shadowEnabled;
- (BOOL)isLandscapeOrientation;
- (CGFloat)geometryNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
- (NSString *)geometryStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (CGFloat)typographyNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
- (NSString *)typographyStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (NSString *)flowStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (CGFloat)flowNumberForKey:(NSString *)key fallback:(CGFloat)fallback;
- (NSString *)animationType;
- (NSTimeInterval)animationDuration;
- (NSTimeInterval)animationDelay;
- (CGFloat)animationDistance;
- (CGFloat)animationSpringDamping;
- (CGFloat)animationSpringVelocity;
- (NSString *)iconNameForStatus:(NSString *)status;
- (NSDictionary *)popupConfigForScreen:(NSString *)screenName;
@end

@implementation TserverUIConfig

+ (NSDictionary *)builtInConfig {
    return @{
        @"version": @1,
        @"authTheme": @"glass_dark",
        @"layout": @"floating",
        @"style": @{
            @"accent": @"#7c3aed",
            @"background": @"#101014",
            @"card": @"#18181f",
            @"text": @"#ffffff",
            @"mutedText": @"#a1a1aa",
            @"danger": @"#ef4444",
            @"success": @"#22c55e",
            @"radius": @18,
            @"blur": @YES,
            @"shadow": @YES
        },
        @"flow": @{
            // validAction: button | anywhere
            // button   = hiện nút Tiếp tục
            // anywhere = không nút, chạm đâu trên UI cũng tiếp tục
            @"minimumLoadingMs": @550,
            @"validAction": @"button"
        },
        @"geometry": @{
            @"horizontalInset": @18,
            @"maxCardWidth": @480,
            @"minCardWidth": @320,
            @"minCardHeight": @0,
            @"xOffset": @0,
            @"yOffset": @0,
            @"overlayOpacity": @0.96,
            @"cardOpacity": @1.0,
            @"iconSize": @38,
            @"position": @"center"
        },
        @"animation": @{
            @"type": @"scale",
            @"durationMs": @220,
            @"delayMs": @0,
            @"distance": @22
        },
        @"typography": @{
            @"fontFamily": @"System",
            @"titleSize": @22,
            @"subtitleSize": @14,
            @"buttonSize": @16,
            @"inputSize": @16
        },
        @"icons": @{
            @"loading": @"fa-bolt",
            @"needKey": @"fa-key",
            @"needUuid": @"fa-shield-halved",
            @"valid": @"fa-circle-check",
            @"updateRequired": @"fa-arrow-up-from-bracket",
            @"maintenance": @"fa-screwdriver-wrench",
            @"appDisabled": @"fa-power-off",
            @"storeDisabled": @"fa-power-off",
            @"packageDisabled": @"fa-box-archive",
            @"packageMaintenance": @"fa-screwdriver-wrench",
            @"packageBundleDenied": @"fa-triangle-exclamation",
            @"badPackageSession": @"fa-clock-rotate-left",
            @"invalidApiKey": @"fa-key",
            @"invalidClientApiKey": @"fa-shield-halved"
        },
        @"templateName": @"default",
        @"uiTemplates": @{
            @"default": @{
                @"authTheme": @"glass_dark",
                @"layout": @"floating",
                @"style": @{
                    @"accent": @"#7c3aed",
                    @"background": @"#101014",
                    @"card": @"#18181f",
                    @"text": @"#ffffff",
                    @"mutedText": @"#a1a1aa",
                    @"danger": @"#ef4444",
                    @"success": @"#22c55e",
                    @"radius": @18,
                    @"blur": @YES,
                    @"shadow": @YES
                },
                @"popup": @{ @"enabled": @NO }
            },
            @"velvet_glass": @{
                @"authTheme": @"glass_dark",
                @"layout": @"floating",
                @"orientation": @"landscape",
                @"style": @{
                    @"accent": @"#a78bfa",
                    @"background": @"#07080f",
                    @"card": @"#12141f",
                    @"text": @"#f8f7ff",
                    @"mutedText": @"#9ca3c7",
                    @"danger": @"#fb7185",
                    @"success": @"#34d399",
                    @"radius": @20,
                    @"blur": @YES,
                    @"shadow": @YES,
                    @"borderWidth": @1,
                    @"borderColor": @"#a78bfa",
                    @"shadowOpacity": @0.42,
                    @"shadowRadius": @32
                },
                @"geometry": @{
                    @"position": @"center",
                    @"horizontalInset": @28,
                    @"maxCardWidth": @520,
                    @"minCardWidth": @320,
                    @"overlayOpacity": @0.88,
                    @"cardOpacity": @0.94,
                    @"iconSize": @44
                },
                @"typography": @{
                    @"titleSize": @22,
                    @"subtitleSize": @13,
                    @"buttonSize": @16,
                    @"inputSize": @15,
                    @"badgeSize": @10,
                    @"footerSize": @11
                },
                @"animation": @{
                    @"type": @"spring",
                    @"durationMs": @380,
                    @"delayMs": @30,
                    @"distance": @22
                },
                @"icons": @{
                    @"loading": @"fa-bolt",
                    @"needKey": @"fa-key",
                    @"needUuid": @"fa-shield-halved",
                    @"valid": @"fa-circle-check",
                    @"updateRequired": @"fa-arrow-up-from-bracket",
                    @"maintenance": @"fa-screwdriver-wrench",
                    @"appDisabled": @"fa-power-off",
                    @"storeDisabled": @"fa-power-off",
                    @"packageDisabled": @"fa-box-archive",
                    @"packageMaintenance": @"fa-screwdriver-wrench",
                    @"packageBundleDenied": @"fa-triangle-exclamation",
                    @"badPackageSession": @"fa-clock-rotate-left",
                    @"invalidApiKey": @"fa-key",
                    @"invalidClientApiKey": @"fa-shield-halved"
                },
                @"popup": @{
                    @"enabled": @YES,
                    @"template": @"compact_toast",
                    @"position": @"topTrailing",
                    @"width": @240,
                    @"opacity": @0.94,
                    @"radius": @18,
                    @"durationMs": @1800,
                    @"progressFrom": @1,
                    @"progressTo": @100,
                    @"animateProgress": @YES,
                    @"completeTitle": @"Hoan tat",
                    @"completeSubtitle": @"Menu san sang",
                    @"collapseOnComplete": @YES,
                    @"showProgress": @YES,
                    @"showSteps": @NO,
                    @"title": @"Dang xu ly…",
                    @"subtitle": @"Vui long doi",
                    @"instances": @[@{
                        @"enabled": @YES,
                        @"template": @"compact_toast",
                        @"position": @"topTrailing",
                        @"width": @240,
                        @"opacity": @0.94,
                        @"radius": @18,
                        @"showProgress": @YES,
                        @"showSteps": @NO,
                        @"title": @"Dang xu ly…",
                        @"subtitle": @"Vui long doi"
                    }],
                    @"screens": @{
                        @"loading": @{
                            @"enabled": @YES,
                            @"template": @"compact_toast",
                            @"position": @"topTrailing",
                            @"width": @248,
                            @"title": @"Dang tai key…",
                            @"subtitle": @"Kiem tra license",
                            @"showProgress": @YES,
                            @"showSteps": @NO,
                            @"animateProgress": @YES,
                            @"progressFrom": @8,
                            @"progressTo": @72,
                            @"durationMs": @2200,
                            @"completeTitle": @"Da tai key",
                            @"completeSubtitle": @"Dang xac thuc…",
                            @"collapseOnComplete": @NO
                        },
                        @"needKey": @{
                            @"enabled": @YES,
                            @"template": @"compact_toast",
                            @"position": @"topTrailing",
                            @"width": @248,
                            @"title": @"Cho nhap key",
                            @"subtitle": @"Nhap TSRV-… de kich hoat",
                            @"showProgress": @YES,
                            @"showSteps": @NO,
                            @"animateProgress": @NO,
                            @"progress": @36,
                            @"progressTo": @36,
                            @"collapseOnComplete": @NO
                        },
                        @"needUuid": @{
                            @"enabled": @YES,
                            @"template": @"compact_toast",
                            @"position": @"topTrailing",
                            @"width": @248,
                            @"title": @"Dang lay UUID…",
                            @"subtitle": @"Cai ho so xac minh",
                            @"showProgress": @YES,
                            @"showSteps": @NO,
                            @"animateProgress": @YES,
                            @"progressFrom": @12,
                            @"progressTo": @58,
                            @"durationMs": @2000,
                            @"collapseOnComplete": @NO
                        },
                        @"valid": @{
                            @"enabled": @YES,
                            @"template": @"compact_toast",
                            @"position": @"topTrailing",
                            @"width": @248,
                            @"title": @"Key hop le",
                            @"subtitle": @"San sang vao menu",
                            @"showProgress": @YES,
                            @"showSteps": @NO,
                            @"animateProgress": @YES,
                            @"progressFrom": @70,
                            @"progressTo": @100,
                            @"durationMs": @900,
                            @"completeTitle": @"Hoan tat",
                            @"completeSubtitle": @"Menu san sang",
                            @"collapseOnComplete": @YES,
                            @"collapseDelayMs": @650
                        },
                        @"networkError": @{
                            @"enabled": @YES,
                            @"template": @"compact_toast",
                            @"position": @"topTrailing",
                            @"title": @"Loi mang",
                            @"subtitle": @"Loi mang. Vui long thu lai sau.",
                            @"showProgress": @NO,
                            @"showSteps": @NO,
                            @"collapseOnComplete": @NO
                        }
                    }
                }
            },
            @"clean_light": @{
                @"authTheme": @"clean_light",
                @"layout": @"centered",
                @"style": @{
                    @"accent": @"#2563EB", @"background": @"#EAF0F6", @"card": @"#FFFFFF",
                    @"text": @"#172033", @"mutedText": @"#667085", @"danger": @"#C63C4B",
                    @"success": @"#11845B", @"radius": @14, @"blur": @NO, @"shadow": @YES
                },
                @"popup": @{ @"enabled": @NO }
            },
            @"neon_dark": @{
                @"authTheme": @"neon_dark",
                @"layout": @"floating",
                @"style": @{
                    @"accent": @"#14B8A6", @"background": @"#07131A", @"card": @"#10232C",
                    @"text": @"#E6FEFA", @"mutedText": @"#94B9B4", @"danger": @"#FB7185",
                    @"success": @"#34D399", @"radius": @12, @"blur": @NO, @"shadow": @YES
                },
                @"popup": @{ @"enabled": @NO }
            },
            @"compact_dark": @{
                @"authTheme": @"compact_dark",
                @"layout": @"bottom_sheet",
                @"style": @{
                    @"accent": @"#E2654B", @"background": @"#16181D", @"card": @"#23262D",
                    @"text": @"#F8F9FB", @"mutedText": @"#B3B7C2", @"danger": @"#E06C75",
                    @"success": @"#74B976", @"radius": @9, @"blur": @NO, @"shadow": @NO
                },
                @"geometry": @{
                    @"horizontalInset": @12,
                    @"maxCardWidth": @420,
                    @"position": @"bottom"
                },
                @"popup": @{ @"enabled": @NO }
            },
            @"floating_card": @{
                @"authTheme": @"floating_card",
                @"layout": @"floating",
                @"style": @{
                    @"accent": @"#D58A28", @"background": @"#101B2A", @"card": @"#1C2B3B",
                    @"text": @"#F7FAFC", @"mutedText": @"#AFBBC8", @"danger": @"#D95252",
                    @"success": @"#4DAE81", @"radius": @18, @"blur": @YES, @"shadow": @YES
                },
                @"popup": @{ @"enabled": @NO }
            },
            @"minimal": @{
                @"layout": @"centered",
                @"popup": @{ @"enabled": @NO }
            },
            @"game_loader": @{
                @"layout": @"floating",
                @"popup": @{
                    @"enabled": @YES,
                    @"template": @"resource_panel",
                    @"position": @"topTrailing",
                    @"width": @264,
                    @"opacity": @0.84,
                    @"radius": @24,
                    @"selectedTemplates": @[@"resource_panel"],
                    @"durationMs": @1800,
                    @"progressFrom": @1,
                    @"progressTo": @100,
                    @"animateProgress": @YES,
                    @"completeTitle": @"Hoan tat",
                    @"completeSubtitle": @"Menu san sang",
                    @"collapseOnComplete": @YES,
                    @"collapseDelayMs": @650,
                    @"collapseDurationMs": @260,
                    @"showProgress": @YES,
                    @"showSteps": @YES,
                    @"title": @"Dang xu ly...",
                    @"subtitle": @"Vui long doi...",
                    @"progress": @100,
                    @"steps": @[@"Data nut bam", @"Data thong bao", @"Data lien ket", @"Skin giao dien"],
                    @"instances": @[@{
                        @"enabled": @YES,
                        @"template": @"resource_panel",
                        @"position": @"topTrailing",
                        @"width": @264,
                        @"opacity": @0.84,
                        @"radius": @24,
                        @"showProgress": @YES,
                        @"showSteps": @YES,
                        @"title": @"Dang xu ly...",
                        @"subtitle": @"Vui long doi...",
                        @"steps": @[@"Data nut bam", @"Data thong bao", @"Data lien ket", @"Skin giao dien"]
                    }],
                    @"screens": @{
                        @"loading": @{
                            @"title": @"Dang tai xac thuc...",
                            @"subtitle": @"Dang kiem tra key va thiet bi",
                            @"progress": @88
                        },
                        @"needUuid": @{
                            @"title": @"Dang lay UUID...",
                            @"subtitle": @"Mo ho so cau hinh de xac minh may",
                            @"progress": @32,
                            @"steps": @[@"Tao phien xac minh", @"Tai ho so UUID", @"Cho cai dat ho so", @"Dong bo thiet bi"]
                        },
                        @"needKey": @{
                            @"title": @"Dang cho nhap key...",
                            @"subtitle": @"Nhap key de kich hoat menu",
                            @"progress": @64
                        },
                        @"valid": @{
                            @"title": @"Da xac thuc thanh cong",
                            @"subtitle": @"Menu san sang",
                            @"progress": @100,
                            @"showSteps": @NO
                        },
                        @"networkError": @{
                            @"title": @"Loi mang",
                            @"subtitle": @"Loi mang. Vui long thu lai sau.",
                            @"progress": @0,
                            @"showSteps": @NO
                        },
                        @"serverError": @{
                            @"title": @"Loi server",
                            @"subtitle": @"Server phan hoi khong hop le",
                            @"progress": @0,
                            @"showSteps": @NO
                        }
                    }
                }
            },
            @"corner_toast": @{
                @"popup": @{
                    @"enabled": @YES,
                    @"template": @"compact_toast",
                    @"selectedTemplates": @[@"compact_toast"],
                    @"position": @"topTrailing",
                    @"width": @232,
                    @"opacity": @0.9,
                    @"radius": @22,
                    @"durationMs": @1400,
                    @"progressFrom": @1,
                    @"progressTo": @100,
                    @"animateProgress": @YES,
                    @"completeTitle": @"Xong",
                    @"completeSubtitle": @"",
                    @"collapseOnComplete": @YES,
                    @"showProgress": @YES,
                    @"showSteps": @NO,
                    @"title": @"Dang xu ly...",
                    @"subtitle": @"",
                    @"instances": @[@{
                        @"enabled": @YES,
                        @"template": @"compact_toast",
                        @"position": @"topTrailing",
                        @"width": @232,
                        @"opacity": @0.9,
                        @"radius": @22,
                        @"showProgress": @YES,
                        @"showSteps": @NO,
                        @"title": @"Dang xu ly...",
                        @"subtitle": @""
                    }]
                }
            }
        },
        @"screens": @{
            @"loading": @{
                @"title": @"Dang kiem tra key",
                @"subtitle": @"Vui long doi trong giay lat..."
            },
            @"needUuid": @{
                @"title": @"Xac minh thiet bi",
                @"subtitle": @"Lien ket may nay voi license bang Device Verify an toan.",
                @"buttonText": @"Lay UUID",
                @"secondaryText": @"Chi can cai ho so xac minh de doc ma may. Khong VPN, khong MDM.",
                @"badgeText": @"DEVICE VERIFY",
                @"profileTitle": @"Xac minh thiet bi an toan",
                @"profileSubtitle": @"Ho so chi doc ma dinh danh thiet bi. Khong cai VPN / MDM / chung chi root.",
                @"profileSteps": @[@"Bam Lay UUID de mo trang cai ho so", @"Chon Cho phep khi iOS hoi tai ho so", @"Vao Cai dat > Ho so da tai > Cai dat", @"Quay lai app de dong bo UUID tu dong"],
                @"profileButtonText": @"Cai ho so thiet bi",
                @"profileAllowButtonText": @"Cho phep tai ho so",
                @"openSettingsHint": @"Neu iOS khong mo cai dat, vao Cai dat > Chung > VPN & Quan ly thiet bi.",
                @"securityNote": @"Ho so chi dung de xac minh thiet bi cho license. Khong doc du lieu ca nhan.",
                @"copyLinkText": @"Copy link xac minh"
            },
            @"needKey": @{
                @"title": @"Nhap key",
                @"subtitle": @"Nhap license key de kich hoat.",
                @"placeholder": @"TSRV-XXXX-XXXX",
                @"buttonText": @"Kich hoat"
            },
            @"valid": @{
                @"title": @"Key hop le",
                @"subtitle": @"Xac nhan de vao menu.",
                // continueMode: button | anywhere
                @"continueMode": @"button",
                @"buttonText": @"Tiep tuc",
                @"tapHint": @"Chạm vào màn hình để tiếp tục"
            },
            @"expired": @{
                @"title": @"Key da het han",
                @"subtitle": @"Vui long nhap key moi de tiep tuc.",
                @"buttonText": @"Nhap key moi"
            },
            @"revoked": @{
                @"title": @"Ban da bi ban key",
                @"subtitle": @"Key nay da bi ban / thu hoi. Lien he nguoi ban de duoc ho tro.",
                @"buttonText": @"Nhap key khac"
            },
            @"deviceBlocked": @{
                @"title": @"Thiet bi bi ban",
                @"subtitle": @"Thiet bi nay da bi ban tren he thong.",
                @"buttonText": @"OK"
            },
            @"deviceMismatch": @{
                @"title": @"Sai thiet bi",
                @"subtitle": @"Key nay da duoc lien ket voi thiet bi khac.",
                @"buttonText": @"Nhap key khac"
            },
            @"networkError": @{
                @"title": @"Loi mang",
                @"subtitle": @"Loi mang. Vui long thu lai sau.",
                @"buttonText": @"Thu lai"
            },
            @"serverError": @{
                @"title": @"Loi server",
                @"subtitle": @"May chu dang ban. Vui long thu lai sau.",
                @"buttonText": @"Thu lai"
            },
            @"updateRequired": @{
                @"title": @"Can cap nhat",
                @"subtitle": @"Vui long cap nhat app de tiep tuc.",
                @"buttonText": @"Cap nhat"
            },
            @"maintenance": @{
                @"title": @"Server dang bao tri",
                @"subtitle": @"He thong dang bao tri/update, vui long quay lai sau.",
                @"buttonText": @"OK"
            },
            @"appDisabled": @{
                @"title": @"Server dang tat",
                @"subtitle": @"Server key dang tam tat. Vui long thu lai sau.",
                @"buttonText": @"OK"
            },
            @"storeDisabled": @{
                @"title": @"He thong dang tat",
                @"subtitle": @"Store/server hien dang tam tat.",
                @"buttonText": @"OK"
            },
            @"packageDisabled": @{
                @"title": @"Package dang tat",
                @"subtitle": @"Package nay da bi tat boi chu package.",
                @"buttonText": @"OK"
            },
            @"packageMaintenance": @{
                @"title": @"Package dang bao tri",
                @"subtitle": @"Package nay dang bao tri/update, vui long thu lai sau.",
                @"buttonText": @"OK"
            },
            @"packageBundleDenied": @{
                @"title": @"Sai ung dung",
                @"subtitle": @"Package nay khong duoc phep chay tren app hien tai.",
                @"buttonText": @"OK"
            },
            @"badPackageSession": @{
                @"title": @"Phien package het han",
                @"subtitle": @"Vui long mo lai app de lay phien package moi.",
                @"buttonText": @"Thu lai"
            },
            @"invalidApiKey": @{
                @"title": @"Package token khong hop le",
                @"subtitle": @"Kiem tra token pkg_... trong ban dylib vua build.",
                @"buttonText": @"OK"
            },
            @"invalidClientApiKey": @{
                @"title": @"Client auth khong khop",
                @"subtitle": @"Dylib dang chay chua khop CLIENT_API_KEY tren server. Kiem tra Artifact MATCH truoc khi phat hanh.",
                @"buttonText": @"OK"
            }
        },
        @"assets": @{},
        @"profile": @{
            @"title": @"Device Verify",
            @"subtitle": @"Ho so chi doc ma dinh danh thiet bi cho license. Khong cai VPN, CA, root certificate hay MDM.",
            @"installTitle": @"Cai ho so xac minh",
            @"installSubtitle": @"Dung Safari/Chrome hien tai. Sau khi cho phep tai ho so, vao Cai dat > Ho so da tai > Cai dat.",
            @"allowTitle": @"Cho phep tai ho so",
            @"allowSubtitle": @"Nhan nut ben duoi tren trinh duyet hien tai. iOS se hien hop thoai Cho phep.",
            @"completeText": @"UUID da nhan. Dang mo app...",
            @"installButtonText": @"Cai ho so thiet bi",
            @"allowButtonText": @"Cho phep tai ho so",
            @"returnButtonText": @"Quay lai app",
            @"copyLinkText": @"Copy link xac minh",
            @"openSettingsHint": @"Neu iOS khong mo cai dat, vao Cai dat > Chung > VPN & Quan ly thiet bi.",
            @"steps": @[@"Bam Lay UUID / Cai ho so tren trinh duyet hien tai.", @"Chon Cho phep khi iOS hoi tai ho so.", @"Vao Cai dat > Ho so da tai > Cai dat.", @"Quay lai app de dong bo UUID tu dong."]
        }
    };
}

+ (NSDictionary *)themeStylePreset:(NSString *)theme {
    NSString *name = [theme isKindOfClass:NSString.class] ? theme : @"glass_dark";
    if ([name isEqualToString:@"clean_light"]) {
        return @{
            @"accent": @"#2563EB", @"background": @"#EAF0F6", @"card": @"#FFFFFF",
            @"text": @"#172033", @"mutedText": @"#667085", @"danger": @"#C63C4B",
            @"success": @"#11845B", @"radius": @14, @"blur": @NO, @"shadow": @YES
        };
    }
    if ([name isEqualToString:@"neon_dark"]) {
        return @{
            @"accent": @"#14B8A6", @"background": @"#07131A", @"card": @"#10232C",
            @"text": @"#E6FEFA", @"mutedText": @"#94B9B4", @"danger": @"#FB7185",
            @"success": @"#34D399", @"radius": @12, @"blur": @NO, @"shadow": @YES
        };
    }
    if ([name isEqualToString:@"compact_dark"]) {
        return @{
            @"accent": @"#E2654B", @"background": @"#16181D", @"card": @"#23262D",
            @"text": @"#F8F9FB", @"mutedText": @"#B3B7C2", @"danger": @"#E06C75",
            @"success": @"#74B976", @"radius": @9, @"blur": @NO, @"shadow": @NO
        };
    }
    if ([name isEqualToString:@"floating_card"]) {
        return @{
            @"accent": @"#D58A28", @"background": @"#101B2A", @"card": @"#1C2B3B",
            @"text": @"#F7FAFC", @"mutedText": @"#AFBBC8", @"danger": @"#D95252",
            @"success": @"#4DAE81", @"radius": @18, @"blur": @YES, @"shadow": @YES
        };
    }
    return @{
        @"accent": @"#7c3aed", @"background": @"#101014", @"card": @"#18181f",
        @"text": @"#ffffff", @"mutedText": @"#a1a1aa", @"danger": @"#ef4444",
        @"success": @"#22c55e", @"radius": @18, @"blur": @YES, @"shadow": @YES
    };
}

+ (NSDictionary *)mergedDictionary:(NSDictionary *)base override:(id)overrideValue {
    if (![overrideValue isKindOfClass:NSDictionary.class]) return base ?: @{};
    NSMutableDictionary *merged = [base mutableCopy] ?: [NSMutableDictionary dictionary];
    [(NSDictionary *)overrideValue enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
        if (![key isKindOfClass:NSString.class] || object == nil || object == NSNull.null) return;
        id existing = merged[key];
        if ([existing isKindOfClass:NSDictionary.class] && [object isKindOfClass:NSDictionary.class]) {
            merged[key] = [self mergedDictionary:existing override:object];
        } else {
            merged[key] = object;
        }
    }];
    return [merged copy];
}

+ (instancetype)defaultConfig {
    return [self configFromDictionary:@{}];
}

+ (instancetype)configFromDictionary:(NSDictionary *)dict {
    NSDictionary *server = [dict isKindOfClass:NSDictionary.class] ? dict : @{};
    NSDictionary *customer = [TserverCustomerAuthUiConfig() isKindOfClass:NSDictionary.class]
        ? TserverCustomerAuthUiConfig()
        : @{};
    BOOL customerOverridesServer = [customer[@"sourceOverridesServer"] respondsToSelector:@selector(boolValue)] &&
        [customer[@"sourceOverridesServer"] boolValue];

    NSDictionary *overrides = customerOverridesServer
        ? [self mergedDictionary:server override:customer]
        : [self mergedDictionary:customer override:server];
    NSString *templateName = [overrides[@"templateName"] isKindOfClass:NSString.class]
        ? overrides[@"templateName"]
        : @"default";
    NSDictionary *templateSource = [self mergedDictionary:[self builtInConfig] override:overrides];
    NSDictionary *templateLibrary = [templateSource[@"uiTemplates"] isKindOfClass:NSDictionary.class]
        ? templateSource[@"uiTemplates"]
        : @{};
    NSDictionary *templateConfig = [templateLibrary[templateName] isKindOfClass:NSDictionary.class]
        ? templateLibrary[templateName]
        : @{};
    NSString *theme = [templateConfig[@"authTheme"] isKindOfClass:NSString.class]
        ? templateConfig[@"authTheme"]
        : ([overrides[@"authTheme"] isKindOfClass:NSString.class] ? overrides[@"authTheme"] : @"glass_dark");
    NSDictionary *withTheme = [self mergedDictionary:[self builtInConfig]
                                             override:@{ @"style": [self themeStylePreset:theme] }];
    NSDictionary *resolved = [self mergedDictionary:[self mergedDictionary:withTheme override:templateConfig]
                                           override:overrides];

    TserverUIConfig *config = [TserverUIConfig new];
    config.rawConfig = resolved;
    config.templateName = [resolved[@"templateName"] isKindOfClass:NSString.class] ? resolved[@"templateName"] : @"default";
    config.theme = [resolved[@"authTheme"] isKindOfClass:NSString.class] ? resolved[@"authTheme"] : @"glass_dark";
    config.layout = [resolved[@"layout"] isKindOfClass:NSString.class] ? resolved[@"layout"] : @"floating";
    config.orientation = [resolved[@"orientation"] isKindOfClass:NSString.class] ? resolved[@"orientation"] : @"portrait";
    config.style = [resolved[@"style"] isKindOfClass:NSDictionary.class] ? resolved[@"style"] : @{};
    config.screens = [resolved[@"screens"] isKindOfClass:NSDictionary.class] ? resolved[@"screens"] : @{};
    config.assets = [resolved[@"assets"] isKindOfClass:NSDictionary.class] ? resolved[@"assets"] : @{};
    config.flow = [resolved[@"flow"] isKindOfClass:NSDictionary.class] ? resolved[@"flow"] : @{};
    config.geometry = [resolved[@"geometry"] isKindOfClass:NSDictionary.class] ? resolved[@"geometry"] : @{};
    config.animation = [resolved[@"animation"] isKindOfClass:NSDictionary.class] ? resolved[@"animation"] : @{};
    config.typography = [resolved[@"typography"] isKindOfClass:NSDictionary.class] ? resolved[@"typography"] : @{};
    config.icons = [resolved[@"icons"] isKindOfClass:NSDictionary.class] ? resolved[@"icons"] : @{};
    config.popup = [resolved[@"popup"] isKindOfClass:NSDictionary.class] ? resolved[@"popup"] : @{};
    config.uiTemplates = [resolved[@"uiTemplates"] isKindOfClass:NSDictionary.class] ? resolved[@"uiTemplates"] : @{};
    return config;
}

- (BOOL)isLandscapeOrientation {
    NSString *value = [self.orientation isKindOfClass:NSString.class] ? self.orientation.lowercaseString : @"portrait";
    return [value isEqualToString:@"landscape"] || [value isEqualToString:@"horizontal"] || [value isEqualToString:@"ngang"];
}

- (NSDictionary *)screenConfig:(NSString *)screenName {
    id value = self.screens[screenName ?: @""];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

- (UIColor *)colorForKey:(NSString *)key fallback:(UIColor *)fallback {
    id value = self.style[key ?: @""];
    return [TserverTheme colorFromHex:[value isKindOfClass:NSString.class] ? value : nil fallback:fallback];
}

- (CGFloat)radius {
    id value = self.style[@"radius"];
    return [value respondsToSelector:@selector(doubleValue)] ? MAX(0.0, [value doubleValue]) : 16.0;
}

- (BOOL)blurEnabled {
    id value = self.style[@"blur"];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
}

- (BOOL)shadowEnabled {
    id value = self.style[@"shadow"];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : YES;
}

- (CGFloat)geometryNumberForKey:(NSString *)key fallback:(CGFloat)fallback {
    id value = self.geometry[key ?: @""];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

- (NSString *)geometryStringForKey:(NSString *)key fallback:(NSString *)fallback {
    id value = self.geometry[key ?: @""];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : fallback;
}

- (CGFloat)typographyNumberForKey:(NSString *)key fallback:(CGFloat)fallback {
    id value = self.typography[key ?: @""];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

- (NSString *)typographyStringForKey:(NSString *)key fallback:(NSString *)fallback {
    id value = self.typography[key ?: @""];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : fallback;
}

- (NSString *)flowStringForKey:(NSString *)key fallback:(NSString *)fallback {
    id value = self.flow[key ?: @""];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : fallback;
}

- (CGFloat)flowNumberForKey:(NSString *)key fallback:(CGFloat)fallback {
    id value = self.flow[key ?: @""];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

- (NSString *)animationType {
    id value = self.animation[@"type"];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : @"scale";
}

- (NSTimeInterval)animationDuration {
    id value = self.animation[@"durationMs"];
    CGFloat milliseconds = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 220.0;
    return MIN(2.5, MAX(0.0, milliseconds / 1000.0));
}

- (NSTimeInterval)animationDelay {
    id value = self.animation[@"delayMs"];
    CGFloat milliseconds = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
    return MIN(2.5, MAX(0.0, milliseconds / 1000.0));
}

- (CGFloat)animationDistance {
    id value = self.animation[@"distance"];
    CGFloat distance = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 22.0;
    return MIN(180.0, MAX(0.0, distance));
}

- (CGFloat)animationSpringDamping {
    id value = self.animation[@"springDamping"];
    CGFloat damping = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.68;
    return MIN(1.0, MAX(0.15, damping));
}

- (CGFloat)animationSpringVelocity {
    id value = self.animation[@"springVelocity"];
    CGFloat velocity = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.95;
    return MIN(4.0, MAX(0.0, velocity));
}

- (NSString *)iconNameForStatus:(NSString *)status {
    NSString *key = @"needKey";
    if ([status isEqualToString:@"LOADING"]) key = @"loading";
    else if ([status isEqualToString:@"NEED_UUID"]) key = @"needUuid";
    else if ([status isEqualToString:@"VALID"] || [status isEqualToString:@"OFFLINE_GRACE_VALID"]) key = @"valid";
    else if ([status isEqualToString:@"UPDATE_REQUIRED"]) key = @"updateRequired";
    else if ([status isEqualToString:@"MAINTENANCE"]) key = @"maintenance";
    else if ([status isEqualToString:@"APP_DISABLED"]) key = @"appDisabled";
    else if ([status isEqualToString:@"STORE_DISABLED"]) key = @"storeDisabled";
    else if ([status isEqualToString:@"PACKAGE_DISABLED"]) key = @"packageDisabled";
    else if ([status isEqualToString:@"PACKAGE_MAINTENANCE"]) key = @"packageMaintenance";
    else if ([status isEqualToString:@"PACKAGE_BUNDLE_DENIED"]) key = @"packageBundleDenied";
    else if ([status isEqualToString:@"BAD_PACKAGE_SESSION"]) key = @"badPackageSession";
    else if ([status isEqualToString:@"INVALID_API_KEY"]) key = @"invalidApiKey";
    else if ([status isEqualToString:@"INVALID_CLIENT_API_KEY"]) key = @"invalidClientApiKey";
    id value = self.icons[key];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

- (NSDictionary *)popupConfigForScreen:(NSString *)screenName {
    if (![self.popup isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *base = [self.popup mutableCopy];
    NSDictionary *screens = [base[@"screens"] isKindOfClass:NSDictionary.class] ? base[@"screens"] : @{};
    [base removeObjectForKey:@"screens"];
    NSDictionary *screen = [screens[screenName ?: @""] isKindOfClass:NSDictionary.class] ? screens[screenName ?: @""] : @{};
    NSMutableDictionary *merged = [[TserverUIConfig mergedDictionary:base override:screen] mutableCopy];
    if (screen[@"progress"] != nil && screen[@"progressTo"] == nil) {
        merged[@"progressTo"] = screen[@"progress"];
    }
    if (screen.count > 0 && screen[@"instances"] == nil && [merged[@"instances"] isKindOfClass:NSArray.class]) {
        NSMutableDictionary *instanceOverride = [screen mutableCopy];
        [instanceOverride removeObjectForKey:@"instances"];
        NSMutableArray *instances = [NSMutableArray array];
        for (id item in (NSArray *)merged[@"instances"]) {
            if ([item isKindOfClass:NSDictionary.class]) {
                NSMutableDictionary *next = [[TserverUIConfig mergedDictionary:item override:instanceOverride] mutableCopy];
                if (screen[@"progress"] != nil && screen[@"progressTo"] == nil) {
                    next[@"progressTo"] = screen[@"progress"];
                }
                [instances addObject:next];
            }
        }
        merged[@"instances"] = instances;
    }
    return [merged copy];
}

@end
