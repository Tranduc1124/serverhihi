// Generated native UI manifest marker and auto-registration.
#define TSERVER_NATIVE_UI_TEMPLATE_MANIFEST_SHA256 @"c7bc312f1f17df62b14bd454689f268a2ff7d7b351c5a53e17bf6bf812e33535"
#define TSERVER_NATIVE_UI_TEMPLATE_COUNT 2

#import "TserverSimpleUiPack.h"
#import "TserverTemplateRegistry.h"

@interface TserverPack_apple_glass : TserverSimpleUiPackBase
@end
@interface TserverPack_cyber_terminal : TserverSimpleUiPackBase
@end

static inline Class _TserverResolvedClassForRendererId(NSString *rendererId) {
    if ([rendererId isEqualToString:@"apple_glass"]) return [TserverPack_apple_glass class];
    if ([rendererId isEqualToString:@"cyber_terminal"]) return [TserverPack_cyber_terminal class];
    return nil;
}

static inline void _TserverKeepPackClassesLive(void) {
    Class knownPacks[] = {
        [TserverPack_apple_glass class],
        [TserverPack_cyber_terminal class],
    };
    (void)knownPacks;
}

static inline void _TserverForceLoadAllPacksOnce(void) {
        (void)[TserverPack_apple_glass class];
        (void)[TserverPack_cyber_terminal class];
}

static inline NSString *_TserverGeneratedDefaultTemplateId(void) {
    return @"apple_glass";
}

static inline NSArray<TserverTemplateDescriptor *> *_TserverGeneratedDescriptors(void) {
    return @[
            TserverDescriptor(@"apple_glass", @"apple_glass", 1, nil, @{@"schemaVersion": @2, @"templateName": @"apple_glass", @"renderer": @{@"id": @"apple_glass", @"revision": @1}, @"layout": @"floating", @"style": @{@"accent": @"#0A84FF", @"background": @"#000000", @"card": @"#1C1C1E", @"text": @"#FFFFFF", @"mutedText": @"#8E8E93", @"danger": @"#FF453A", @"success": @"#30D158", @"radius": @18, @"blur": @YES, @"shadow": @YES}, @"geometry": @{@"maxCardWidth": @320, @"minCardWidth": @280, @"horizontalInset": @24}, @"animation": @{@"type": @"pop", @"durationMs": @260, @"distance": @0}, @"motion": @{@"haptic": @"light"}, @"popup": @{@"enabled": @YES, @"presentation": @"terminal_status", @"position": @"topTrailing", @"width": @246, @"opacity": @0.92, @"radius": @12, @"showProgress": @YES, @"animateProgress": @YES, @"progressFrom": @0, @"progressTo": @100, @"durationMs": @1800, @"collapseOnComplete": @YES, @"collapseDelayMs": @650}, @"screens": @{@"loading": @{@"title": @"Đang kiểm tra", @"subtitle": @"Vui lòng chờ trong giây lát…"}, @"needKey": @{@"title": @"Kích hoạt bản quyền", @"subtitle": @"Nhập license key để mở khóa tính năng.", @"placeholder": @"TSRV-XXXX-XXXX", @"buttonText": @"Kích hoạt"}, @"needUuid": @{@"title": @"Xác minh thiết bị", @"subtitle": @"Cài hồ sơ để xác nhận UUID máy an toàn.", @"buttonText": @"Cài hồ sơ UUID", @"copyLinkText": @"Sao chép liên kết", @"profileTitle": @"Cài hồ sơ xác minh", @"profileSubtitle": @"Hồ sơ chỉ đọc mã máy. Không cài VPN, không chứng chỉ root.", @"profileButtonText": @"Cài hồ sơ", @"profileAllowButtonText": @"Cho phép tải về", @"profileSteps": @[@"Bấm Cài hồ sơ để mở Safari", @"Bấm Cho phép khi iOS hỏi tải hồ sơ", @"Vào Cài đặt > Hồ sơ đã tải > Cài đặt"], @"openSettingsHint": @"Vào Cài đặt > Cài đặt chung > VPN & Quản lý thiết bị nếu cần."}, @"valid": @{@"title": @"Đã kích hoạt", @"subtitle": @"Bản quyền hợp lệ. Nhấn Tiếp tục để vào menu.", @"buttonText": @"Tiếp tục", @"continueMode": @"button", @"tapHint": @"Chạm để tiếp tục"}, @"expired": @{@"title": @"Key đã hết hạn", @"subtitle": @"Thời hạn sử dụng đã kết thúc. Vui lòng nhập key mới.", @"buttonText": @"Nhập key mới"}, @"revoked": @{@"title": @"Key đã bị thu hồi", @"subtitle": @"Key này đã bị khóa. Vui lòng liên hệ hỗ trợ.", @"buttonText": @"Đổi key khác"}, @"deviceBlocked": @{@"title": @"Thiết bị bị từ chối", @"subtitle": @"Thiết bị này đã bị chặn truy cập hệ thống.", @"buttonText": @"Đóng"}, @"deviceMismatch": @{@"title": @"Không đúng thiết bị", @"subtitle": @"Key đã được kích hoạt trên một thiết bị khác.", @"buttonText": @"Nhập key khác"}, @"updateRequired": @{@"title": @"Yêu cầu cập nhật", @"subtitle": @"Vui lòng nâng cấp bản mới nhất để tiếp tục sử dụng.", @"buttonText": @"Cập nhật ngay"}, @"networkError": @{@"title": @"Lỗi kết nối", @"subtitle": @"Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.", @"buttonText": @"Thử lại"}, @"serverError": @{@"title": @"Máy chủ bận", @"subtitle": @"Hệ thống đang xử lý, vui lòng thử lại sau.", @"buttonText": @"Thử lại"}, @"appDisabled": @{@"title": @"Tạm dừng phục vụ", @"subtitle": @"Server key đang tạm tắt.", @"buttonText": @"Đóng"}, @"storeDisabled": @{@"title": @"Hệ thống tạm đóng", @"subtitle": @"Dịch vụ đang tạm thời không khả dụng.", @"buttonText": @"Đóng"}, @"packageDisabled": @{@"title": @"Package tạm tắt", @"subtitle": @"Gói ứng dụng này đang tạm dừng hoạt động.", @"buttonText": @"Đóng"}, @"packageMaintenance": @{@"title": @"Đang bảo trì", @"subtitle": @"Hệ thống đang bảo trì, vui lòng quay lại sau.", @"buttonText": @"Đóng"}, @"packageBundleDenied": @{@"title": @"Ứng dụng không khớp", @"subtitle": @"Package không hỗ trợ ứng dụng hiện tại.", @"buttonText": @"Đóng"}, @"badPackageSession": @{@"title": @"Phiên làm việc hết hạn", @"subtitle": @"Vui lòng khởi động lại app để làm mới phiên.", @"buttonText": @"Làm mới"}, @"invalidApiKey": @{@"title": @"Mã xác thực không hợp lệ", @"subtitle": @"Package token không đúng hoặc đã bị đổi.", @"buttonText": @"Đóng"}}}, @[@"style", @"screens", @"assets", @"animation", @"typography", @"popup", @"geometry"]),
            TserverDescriptor(@"cyber_terminal", @"cyber_terminal", 1, @"apple_glass", @{@"schemaVersion": @2, @"templateName": @"cyber_terminal", @"renderer": @{@"id": @"cyber_terminal", @"revision": @1}, @"layout": @"floating", @"style": @{@"accent": @"#39F6C0", @"background": @"#03130F", @"card": @"#08251C", @"text": @"#E8FFF8", @"mutedText": @"#78B6A4", @"danger": @"#FF617A", @"success": @"#4FFFB8", @"radius": @12, @"blur": @NO, @"shadow": @YES}, @"geometry": @{@"maxCardWidth": @400, @"minCardWidth": @300, @"horizontalInset": @40}, @"animation": @{@"type": @"fade", @"durationMs": @250, @"distance": @12}, @"motion": @{@"haptic": @"light", @"scan": @YES}, @"popup": @{@"enabled": @YES, @"presentation": @"terminal_status", @"position": @"topTrailing", @"width": @246, @"opacity": @0.92, @"radius": @10, @"showProgress": @YES, @"animateProgress": @YES, @"progressFrom": @0, @"progressTo": @100, @"durationMs": @1800, @"collapseOnComplete": @YES, @"collapseDelayMs": @650}}, @[@"style", @"screens", @"assets", @"animation", @"typography", @"popup", @"geometry"])
    ];
}
