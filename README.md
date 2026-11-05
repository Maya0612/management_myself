# Kỷ luật mỗi ngày

Ứng dụng Flutter quản lý thói quen cá nhân, lưu dữ liệu cục bộ bằng SQLite.

## Chạy trên Android Emulator

```powershell
flutter pub get
flutter devices
flutter run -d emulator-5554
```

Nếu Pixel_7 có mã thiết bị khác, thay `emulator-5554` bằng mã hiển thị từ `flutter devices`.

## Tài khoản dùng thử

- Tên hiển thị: `hathu`
- Email: `test@gmail.com`
- Mật khẩu: `123456`

Lần đầu mở ứng dụng, tài khoản dùng thử được tạo cùng một số thói quen mẫu. Lịch sử hoàn thành ban đầu để trống để thống kê phản ánh đúng những lần người dùng tự đánh dấu.

## Thông báo dùng thử

Trên Android, mở màn hình **Tổng quan** và nhấn **Thử ngay** trong thẻ **Thông báo dùng thử**. Nếu Android hỏi quyền thông báo, chọn **Cho phép**; lời nhắc sẽ xuất hiện trong thanh thông báo của thiết bị, không chỉ trong ứng dụng. Nếu đã từ chối, bật quyền tại **Cài đặt Android → Ứng dụng → Kỷ luật mỗi ngày → Thông báo**.

## Kiểm tra

```powershell
flutter analyze
flutter test
```
