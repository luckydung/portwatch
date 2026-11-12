# portwatch

**Port Dashboard** — cho biết port nào đang mở trên máy, ứng dụng nào đang chiếm port đó, và cho phép dừng ứng dụng để giải phóng port. Không cần cài đặt gì thêm.

Hữu ích khi gặp lỗi kiểu "port 8080 is already in use" mà không biết cái gì đang chiếm.

Có hai phiên bản:

| | Windows | Linux |
|---|---|---|
| Giao diện | Cửa sổ (WPF) | Trong terminal, như `htop`; dùng được qua SSH |
| Thư mục | [`windows/`](windows) | [`linux/`](linux) |
| Cần có | Windows 10/11, PowerShell 5.1 (có sẵn) | Python 3.6+ (thường có sẵn), chỉ dùng thư viện chuẩn |

## Tải về

Không cần git, chỉ cần tải file của hệ điều hành bạn dùng:

| Hệ điều hành | File tải về | Cách mở |
|---|---|---|
| Windows | [**portwatch-windows.zip**](https://github.com/luckydung/portwatch/releases/latest/download/portwatch-windows.zip) | Giải nén, double-click `PortDashboard.bat` |
| Linux | [**portwatch.py**](https://github.com/luckydung/portwatch/releases/latest/download/portwatch.py) | `python3 portwatch.py` |

Link luôn trỏ tới phiên bản mới nhất. Các phiên bản cũ và ghi chú thay đổi nằm ở trang [Releases](https://github.com/luckydung/portwatch/releases).

## Tính năng

- **Danh sách port đang lắng nghe (TCP)**: số port, tên ứng dụng, PID, đường dẫn file chạy (Linux: kèm người dùng và câu lệnh đầy đủ).
- **Giải thích port dùng để làm gì** cho các port quen thuộc (HTTP, MySQL, PostgreSQL, Redis, Vite, Spring Boot...).
- **Phạm vi truy cập**: port chỉ mở cho máy này (`127.0.0.1`) hay máy khác trong mạng cũng truy cập được.
- **Tìm kiếm** theo số port, tên ứng dụng, PID hoặc đường dẫn.
- **Dừng ứng dụng** đang chiếm port, có hỏi xác nhận và cảnh báo riêng với dịch vụ hệ thống.
- **Ẩn/hiện port hệ thống** để danh sách gọn hơn.
- **Tự động làm mới** theo chu kỳ tùy chỉnh. Dữ liệu được đọc ở luồng nền nên giao diện không bị đứng.
- **Thông tin máy** trong một hộp thoại riêng: tên máy, người dùng, hệ điều hành, IP, CPU, RAM, thời gian đã bật máy; có nút sao chép.
- **Chạy lại với quyền Admin / sudo** ngay từ trong ứng dụng.

## Windows

1. Tải [**portwatch-windows.zip**](https://github.com/luckydung/portwatch/releases/latest/download/portwatch-windows.zip).

2. **Bỏ chặn file trước khi giải nén:** chuột phải file zip → **Properties** → tick **Unblock** → **OK**. Windows đánh dấu mọi file tải từ Internet; nếu bỏ qua bước này, mỗi lần mở sẽ hiện hộp thoại cảnh báo bảo mật.

3. Giải nén, mở thư mục `portwatch-windows` rồi double-click **`PortDashboard.bat`**. Hai file `PortDashboard.bat` và `PortDashboard.ps1` phải luôn nằm cùng thư mục.

4. Chọn một dòng trong bảng rồi bấm **Dừng ứng dụng** để giải phóng port.

Nếu đã clone repo thì double-click `windows\PortDashboard.bat`, hoặc chạy trực tiếp từ PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\windows\PortDashboard.ps1
```

**Khi nào cần quyền Admin:** chạy bình thường vẫn xem được danh sách port. Bấm **Chạy lại với quyền Admin** khi cột "Đường dẫn" của một số ứng dụng bị trống, hoặc không dừng được ứng dụng do người dùng khác hay hệ thống khởi chạy.

### Cài đặt (Windows)

Bấm nút **Cài đặt** ở góc trên bên phải:

| Mục | Ý nghĩa | Mặc định |
|---|---|---|
| Tự động làm mới danh sách port | Bật/tắt việc tự đọc lại danh sách | Bật |
| Làm mới mỗi ... giây | Chu kỳ làm mới, từ 1 đến 3600 giây | 5 |
| Hiện nút "Thông tin máy" | Ẩn/hiện nút mở hộp thoại thông tin máy | Bật |
| Hiện port hệ thống của Windows | Hiện cả port của các dịch vụ Windows | Tắt |
| Cửa sổ luôn nằm trên | Giữ cửa sổ nổi trên các cửa sổ khác | Tắt |

Cài đặt được lưu tại `%APPDATA%\PortDashboard\settings.json`. Xóa file này để quay về mặc định.

## Linux

Toàn bộ bản Linux chỉ là một file `portwatch.py`. Tải bản mới nhất rồi chạy bằng Python 3:

```bash
curl -fsSLO https://github.com/luckydung/portwatch/releases/latest/download/portwatch.py
```

```bash
python3 portwatch.py
```

Muốn gõ `portwatch` ở bất kỳ đâu thì chép vào thư mục lệnh của bạn:

```bash
install -Dm755 portwatch.py ~/.local/bin/portwatch
```

**Khi nào cần sudo:** không có sudo bạn vẫn thấy mọi port, nhưng chỉ biết tiến trình nào giữ port nếu tiến trình đó là của bạn; port của người dùng khác hiện "(cần sudo để xem)". Bấm `u` trong ứng dụng hoặc chạy `sudo python3 portwatch.py` để xem và dừng được tất cả.

### Phím tắt

| Phím | Việc |
|---|---|
| `↑` `↓` `PgUp` `PgDn` `Home` `End` | Chọn dòng |
| `/` | Tìm (gõ để lọc, `Enter` xong, `Esc` xóa) |
| `Enter` | Xem chi tiết: địa chỉ, file chạy, thư mục, câu lệnh đầy đủ |
| `k` hoặc `Delete` | Dừng ứng dụng đang chọn |
| `r` hoặc `F5` | Làm mới ngay |
| `a` | Bật/tắt tự làm mới |
| `h` | Ẩn/hiện port hệ thống |
| `i` | Thông tin máy (`c` để sao chép) |
| `s` | Cài đặt |
| `u` | Chạy lại với sudo |
| `q` | Thoát |

### Cài đặt (Linux)

Bấm `s`:

| Mục | Ý nghĩa | Mặc định |
|---|---|---|
| Tự động làm mới danh sách port | Bật/tắt việc tự đọc lại danh sách | Bật |
| Làm mới mỗi ... giây | Chu kỳ làm mới, từ 1 đến 3600 giây (`◀` `▶` hoặc gõ số) | 5 |
| Hiện port hệ thống | Hiện cả port của dịch vụ hệ thống (người dùng có UID dưới 1000) | Tắt |
| Cách dừng ứng dụng | **Lịch sự (SIGTERM)**: để ứng dụng tự dọn dẹp rồi thoát; nếu sau 2 giây chưa thoát sẽ hỏi có buộc dừng không. **Buộc dừng (SIGKILL)**: dừng ngay. | SIGTERM |

Cài đặt được lưu tại `~/.config/portwatch/settings.json`. Khi chạy bằng sudo, file vẫn nằm trong home của bạn và vẫn thuộc về bạn, không thuộc root.

### In danh sách ra màn hình

Dùng trong script hoặc khi chỉ muốn xem nhanh:

```bash
python3 portwatch.py --list
```

Thêm `--system` để hiện cả port hệ thống.

## Lưu ý

- **Dừng ứng dụng sẽ làm mất dữ liệu chưa lưu** trong ứng dụng đó. Bản Windows buộc tắt ngay (tương đương End Task); bản Linux mặc định gửi SIGTERM trước.
- Dừng dịch vụ hệ thống có thể làm máy chạy không ổn định. Ứng dụng cảnh báo trước và không cho dừng các tiến trình lõi.
- Chỉ liệt kê port TCP đang ở trạng thái lắng nghe; chưa hỗ trợ UDP.
- Ứng dụng chỉ đọc thông tin trên máy cục bộ, không gửi dữ liệu đi đâu.

## Giấy phép

[MIT](LICENSE)
