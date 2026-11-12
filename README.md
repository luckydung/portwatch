# portwatch

**Port Dashboard** — một cửa sổ nhỏ trên Windows cho biết port nào đang mở, ứng dụng nào đang chiếm port đó, và cho phép dừng ứng dụng để giải phóng port. Không cần cài đặt: chỉ gồm một file PowerShell và một file `.bat` để mở.

Hữu ích khi gặp lỗi kiểu "port 8080 is already in use" mà không biết cái gì đang chiếm.

## Tính năng

- **Danh sách port đang lắng nghe (TCP)**: số port, tên ứng dụng, PID, đường dẫn file chạy.
- **Giải thích port dùng để làm gì** cho các port quen thuộc (HTTP, MySQL, PostgreSQL, Redis, Vite, Spring Boot...).
- **Phạm vi truy cập**: port chỉ mở cho máy này (`127.0.0.1`) hay máy khác trong mạng cũng truy cập được.
- **Tìm kiếm** theo số port, tên ứng dụng, PID hoặc đường dẫn.
- **Dừng ứng dụng** đang chiếm port, có hỏi xác nhận và cảnh báo riêng với dịch vụ hệ thống.
- **Mở thư mục chứa** file chạy của ứng dụng.
- **Ẩn/hiện port hệ thống** của Windows để danh sách gọn hơn.
- **Tự động làm mới** theo chu kỳ tùy chỉnh. Dữ liệu được đọc ở luồng nền nên cửa sổ không bị đứng.
- **Thông tin máy** trong một hộp thoại riêng: tên máy, người dùng, hệ điều hành, IP, CPU, RAM, thời gian đã bật máy; có nút sao chép.
- **Chạy lại với quyền Admin** ngay từ trong ứng dụng.

## Yêu cầu

- Windows 10 hoặc Windows 11
- Windows PowerShell 5.1 (có sẵn trong Windows)

## Cách dùng

1. Tải repo về (Code → Download ZIP) hoặc clone:

   ```bash
   git clone https://github.com/luckydung/portwatch.git
   ```

2. Double-click **`PortDashboard.bat`**. Hai file `PortDashboard.bat` và `PortDashboard.ps1` phải nằm cùng thư mục.

3. Chọn một dòng trong bảng rồi bấm **Dừng ứng dụng** để giải phóng port.

Cũng có thể chạy trực tiếp từ PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\PortDashboard.ps1
```

### Khi nào cần quyền Admin

Chạy bình thường vẫn xem được danh sách port. Cần bấm **Chạy lại với quyền Admin** khi:

- cột "Đường dẫn" của một số ứng dụng bị trống, hoặc
- không dừng được ứng dụng do người dùng khác hoặc hệ thống khởi chạy.

## Cài đặt

Bấm nút **Cài đặt** ở góc trên bên phải:

| Mục | Ý nghĩa | Mặc định |
|---|---|---|
| Tự động làm mới danh sách port | Bật/tắt việc tự đọc lại danh sách | Bật |
| Làm mới mỗi ... giây | Chu kỳ làm mới, từ 1 đến 3600 giây | 5 |
| Hiện nút "Thông tin máy" | Ẩn/hiện nút mở hộp thoại thông tin máy | Bật |
| Hiện port hệ thống của Windows | Hiện cả port của các dịch vụ Windows | Tắt |
| Cửa sổ luôn nằm trên | Giữ cửa sổ nổi trên các cửa sổ khác | Tắt |

Cài đặt được lưu tại `%APPDATA%\PortDashboard\settings.json` và giữ nguyên cho lần mở sau. Xóa file này để quay về mặc định.

## Lưu ý

- **Dừng ứng dụng là buộc tắt tiến trình** (tương đương End Task): dữ liệu chưa lưu trong ứng dụng đó sẽ mất.
- Dừng dịch vụ hệ thống có thể làm Windows hoạt động không ổn định. Ứng dụng có cảnh báo trước và không cho dừng các tiến trình lõi (PID từ 4 trở xuống).
- Chỉ liệt kê port TCP đang ở trạng thái lắng nghe; chưa hỗ trợ UDP.
- Ứng dụng chỉ đọc thông tin trên máy cục bộ, không gửi dữ liệu đi đâu.

## Giấy phép

[MIT](LICENSE)
