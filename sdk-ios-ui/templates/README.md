# Tserver Native UI Packs Architecture

Đây là **nơi duy nhất** để tạo và chỉnh sửa các gói giao diện (UI Pack) của SDK iOS.

---

## 🚀 Quy trình 3 bước chuẩn hóa để thêm UI mới

### Bước 1: Tạo thư mục pack mới
Tạo thư mục trong `sdk-ios-ui/templates/<pack_id>/` (ví dụ `frost_glass`, `anime_gacha`, `cyber_terminal`):

```text
sdk-ios-ui/templates/<pack_id>/
├─ manifest.json               # Khai báo metadata (id, name, description, tags)
├─ config.json                 # Cấu hình màu sắc, layout, style, screens text riêng
├─ <PackName>.mm               # Pack shell (Class TserverPack_<pack_id>)
└─ screens/
   ├─ <PackName>Loading.mm     # Màn hình đang kiểm tra / xác thực
   ├─ <PackName>KeyEntry.mm    # Màn hình nhập license key
   ├─ <PackName>DeviceVerify.mm# Màn hình cài đặt hồ sơ UUID
   └─ <PackName>Result.mm      # Màn hình kết quả thành công / lỗi / bảo trì
```

⚠️ **Quy tắc quan trọng**:
1. **Basename file phải unique**: Tên các file `.mm` trong `screens/` phải kèm tiền tố tên Pack (VD: `AnimeGachaKeyEntry.mm`, không đặt `KeyEntry.mm`) để compiler không bị ghi đè object file.
2. **Tên Class**: Phải đặt theo mẫu `@implementation TserverPack_<pack_id>`.
3. **Default/fallback**: `manifest.json` phải có `isDefault` và `fallbackTemplate`. Toàn catalog chỉ được đúng một `isDefault: true`; fallback phải là ID pack tồn tại hoặc `null`, không được tạo cycle.
4. **Loading riêng**: Pack phải cung cấp screen loading riêng và `config.json` phải giữ đúng `templateName` + `renderer.id/revision` theo manifest.
5. **Web là nguồn chọn UI**: Customer chỉ điền `kAPIClientPackageToken` một lần trong `APIClient.h`. Không điền template ID trong source; package chọn pack trên web.
6. **Không hardcode pack trong SDK core**: Không thêm `if (pack_id == ...)` trong bootstrap/registry. Presentation riêng của pack phải nằm trong manifest/config/class của pack.
7. **Regenerate + check**: Sau khi thêm/sửa pack, chạy generator và `--check`; build phải fail nếu generated catalog drift, default/fallback sai hoặc renderer metadata lệch.

Mỗi lần mở app, trước khi signed response hiện tại xác định pack, SDK chỉ dựng overlay trong suốt chặn touch: không card, không text, không default/cached pack. Khi response đã kiểm hash về, SDK mở đúng pack đang chọn trên web. Vì vậy đổi UI trên portal không bao giờ flash pack cũ.

---

### Bước 2: Tự động hóa Generator & Rebuild SDK
Chỉ cần chạy lệnh build trên WSL:
```bash
bash _build_sdk_demo_ipa.sh
```
Script `generate_ui_template_catalog.py` sẽ **tự động hoàn toàn**:
- Quét mọi template mới trong thư mục.
- Tự động sinh `nativeAuthUiTemplates.ts` cho **Backend Server & Web Portal**.
- Tự động sinh `TserverTemplateCatalog.gen.mm` chứa **Force-Load Symbol** để trình biên dịch Clang không bao giờ dead-strip class của UI mới.
- Biên dịch ra `libAPIClient.a` và đóng gói file test `TserverSdkDemo.ipa`.

---

### Bước 3: Safe deploy Server
Chạy lệnh deploy trên PowerShell Windows:
```powershell
.\deploy\vps\safe-update.ps1
```
Server sẽ tự nhận diện gói UI mới trong API và Web portal (`/packages`) sẽ tự hiển thị thẻ chọn UI mới gọn gàng.

---

## 🛡️ Cơ chế đảm bảo không bao giờ bị lẫn lộn giữa các UI

1. **Auto Class Force-Loading**: Generator tự động xuất symbol `[TserverPack_<pack_id> class]` vào file gen, đảm bảo code của tất cả các UI luôn có mặt trong dylib 100%.
2. **Cold-Start Isolated Routing**: SDK chờ signed package response hiện tại, chỉ chặn touch bằng overlay trong suốt trước đó; không đoán pack từ build/default/cache và không dùng fallback cứng của pack khác.
3. **Screen Text Isolation**: Server khi phục vụ package nào sẽ dùng đúng 100% bộ Screen Text nguyên bản của UI đó, không bị merge các text mặc định của Cyber Terminal.
