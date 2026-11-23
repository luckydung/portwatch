# portwatch

**Port Dashboard** — cho biết port nào đang mở trên máy, ứng dụng nào đang chiếm port đó, và cho phép dừng ứng dụng để giải phóng port. Không cần cài đặt gì thêm.

Hữu ích khi gặp lỗi kiểu "port 8080 is already in use" mà không biết cái gì đang chiếm.

Có ba phiên bản:

| | Windows | macOS | Linux |
|---|---|---|---|
| Giao diện | Cửa sổ (WPF) | Ứng dụng macOS (SwiftUI) | Trong terminal, như `htop`; dùng được qua SSH |
| Thư mục | [`windows/`](windows) | [`macos/`](macos) | [`linux/`](linux) |
| Cần có | Windows 10/11, PowerShell 5.1 (có sẵn) | macOS 14 trở lên, Mac Apple Silicon hoặc Intel | Python 3.6+ (thường có sẵn), chỉ dùng thư viện chuẩn |

Bản Linux (`portwatch.py`) cũng chạy được trên macOS, nếu bạn thích dùng trong terminal.

## Tải về

Không cần git, chỉ cần tải file của hệ điều hành bạn dùng:

| Hệ điều hành | File tải về | Cách mở |
|---|---|---|
| Windows | [**portwatch-windows.zip**](https://github.com/luckydung/portwatch/releases/latest/download/portwatch-windows.zip) | Giải nén, double-click `PortDashboard.bat` |
| macOS | Chưa có file tải sẵn | [Build từ mã nguồn](#macos) bằng một lệnh, rồi double-click `Port Dashboard.app` |
| Linux | [**portwatch.py**](https://github.com/luckydung/portwatch/releases/latest/download/portwatch.py) | `python3 portwatch.py`; chạy `--install` một lần để [mở bằng click](#mở-bằng-click) |

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
| Tự mở khi đăng nhập Windows | Mở ứng dụng (thu nhỏ xuống thanh tác vụ) mỗi khi đăng nhập | Tắt |

Cài đặt được lưu tại `%APPDATA%\PortDashboard\settings.json`. Xóa file này để quay về mặc định.

Chế độ tự khởi động được lưu riêng trong registry của người dùng (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, mục `PortDashboard`), không cần quyền Admin. Có thể tắt ở đây hoặc trong **Task Manager → Startup apps**. Nếu di chuyển thư mục chứa ứng dụng, mở ứng dụng một lần từ vị trí mới để đường dẫn khởi động được cập nhật.

## macOS

Bản macOS là một ứng dụng thật: double-click là mở, không cần Terminal hay Python.

### Cài đặt

Hiện chưa có file tải sẵn, nên cần build từ mã nguồn một lần. Máy cần có Xcode hoặc Command Line Tools (nếu chưa có, chạy `xcode-select --install`).

```bash
git clone https://github.com/luckydung/portwatch.git
```

```bash
portwatch/macos/build.sh --install
```

Lệnh này biên dịch ứng dụng (chạy được trên cả Apple Silicon và Intel), vẽ icon và chép **Port Dashboard** vào thư mục **Applications**. Sau đó mở bằng Launchpad, Spotlight (`⌘ Space`, gõ "Port") hoặc kéo vào Dock. Bỏ `--install` nếu chỉ muốn build ra `macos/build/Port Dashboard.app` mà không chép đi đâu.

### Sử dụng

- **Chọn một dòng rồi bấm Dừng ứng dụng** (hoặc phím `Delete`) để giải phóng port. Ứng dụng gửi tín hiệu dừng lịch sự trước; nếu sau 2 giây chưa thoát sẽ hỏi có buộc dừng không.
- **Double-click một dòng** để xem chi tiết: file chạy, thư mục, câu lệnh đầy đủ. Từ đây có thể mở `http://localhost:<port>` trong trình duyệt, hiện file trong Finder hoặc sao chép thông tin.
- **Chuột phải một dòng** để mở trong trình duyệt, sao chép số port, PID hoặc câu lệnh.
- Ô tìm kiếm ở thanh công cụ lọc theo số port, tên ứng dụng, PID hoặc đường dẫn. `⌘R` để làm mới ngay.

**Khi nào cần mật khẩu Admin:** chỉ khi dừng ứng dụng do người dùng khác hoặc hệ thống chạy. macOS sẽ hiện hộp thoại hỏi mật khẩu; ứng dụng không bao giờ thấy mật khẩu của bạn.

**Port 5000 và 7000 bị chiếm sẵn?** Đó là **AirPlay Receiver** của macOS, hay đụng với Flask hoặc các dev server. Dừng tiến trình không có tác dụng vì macOS tự mở lại; ứng dụng sẽ chỉ cách tắt trong **Cài đặt hệ thống → Chung → AirDrop & Handoff** và có nút mở thẳng trang đó. Port do `launchd` giữ (SSH, chia sẻ màn hình, chia sẻ file) cũng được hướng dẫn tắt ở **Cài đặt hệ thống → Chung → Chia sẻ**.

### Cài đặt (macOS)

Bấm nút bánh răng trên thanh công cụ hoặc `⌘,`:

| Mục | Ý nghĩa | Mặc định |
|---|---|---|
| Tự động làm mới danh sách port | Bật/tắt việc tự đọc lại danh sách | Bật |
| Làm mới mỗi ... giây | Chu kỳ làm mới, từ 1 đến 3600 giây | 5 |
| Hiện nút "Thông tin máy" | Ẩn/hiện nút mở hộp thoại thông tin máy | Bật |
| Hiện port hệ thống của macOS | Hiện cả port của dịch vụ hệ thống (tiến trình trong `/System`, `/usr/libexec`... hoặc chạy bằng tài khoản hệ thống) | Tắt |
| Cửa sổ luôn nằm trên | Giữ cửa sổ nổi trên các cửa sổ khác | Tắt |
| Tự mở khi đăng nhập macOS | Mở ứng dụng mỗi khi đăng nhập; tắt được ở **Cài đặt hệ thống → Chung → Mục đăng nhập** | Tắt |

Cài đặt được lưu trong `~/Library/Preferences/io.github.luckydung.portwatch.plist`.

**Hạn chế:** ứng dụng dùng `lsof` nên chỉ thấy port của tài khoản đang đăng nhập; port do root giữ (vd. 88 Kerberos, 5900 chia sẻ màn hình) có thể không hiện. Đó đều là port hệ thống, mặc định vẫn được ẩn.

### Dùng trong terminal trên macOS

`linux/portwatch.py` cũng chạy trên macOS (đọc port bằng `lsof`, `netstat`, `ps` thay cho `/proc`), có đủ tính năng và phím tắt như [bản Linux](#phím-tắt) trừ `--install` / phím `m`:

```bash
python3 portwatch/linux/portwatch.py
```

Nếu máy chưa có Python 3, macOS sẽ đề nghị cài Command Line Tools khi bạn chạy lệnh `python3` lần đầu.

## Linux

Toàn bộ bản Linux chỉ là một file `portwatch.py`. Tải bản mới nhất rồi chạy bằng Python 3:

```bash
curl -fsSLO https://github.com/luckydung/portwatch/releases/latest/download/portwatch.py
```

```bash
python3 portwatch.py
```

**Khi nào cần sudo:** không có sudo bạn vẫn thấy mọi port, nhưng chỉ biết tiến trình nào giữ port nếu tiến trình đó là của bạn; port của người dùng khác hiện "(cần sudo để xem)". Bấm `u` trong ứng dụng hoặc chạy `sudo python3 portwatch.py` để xem và dừng được tất cả.

### Mở bằng click

Chạy lệnh sau **một lần**:

```bash
python3 portwatch.py --install
```

Lệnh này thêm **Port Dashboard** vào menu ứng dụng, tạo biểu tượng ngoài Desktop và cài lệnh `portwatch`. Từ đó về sau:
- Mở menu (hoặc bấm phím Super), gõ "Port" rồi click. Có thể ghim vào dock hay thanh tác vụ.
- Hoặc double-click biểu tượng ngoài Desktop. Trên GNOME, lần đầu cần chuột phải → **Allow Launching**.

Đang mở ứng dụng trong terminal thì bấm `m` cũng được. Gỡ bằng `portwatch --uninstall`.

Khi được mở bằng click, ứng dụng tự mở cửa sổ terminal có sẵn trên máy (GNOME Terminal, Konsole, Xfce Terminal, xterm...). Nếu có lỗi, cửa sổ sẽ chờ bạn bấm Enter rồi mới đóng, để kịp đọc thông báo.

**Không muốn gõ lệnh nào?** Trên KDE, Xfce, Cinnamon và MATE: chuột phải `portwatch.py` → **Properties** → **Permissions** → tick **Allow executing file as program**. Sau đó double-click file, chọn **Run**, rồi bấm `m` để thêm vào menu. Riêng Nautilus (trình quản lý file của GNOME) không chạy script bằng double-click, nên trên GNOME phải chạy lệnh `--install` ở trên.

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
| `m` | Thêm vào menu ứng dụng để lần sau mở bằng click (chỉ hiện khi chưa thêm) |
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

- **Dừng ứng dụng sẽ làm mất dữ liệu chưa lưu** trong ứng dụng đó. Bản Windows buộc tắt ngay (tương đương End Task); bản macOS và Linux mặc định gửi SIGTERM trước.
- Dừng dịch vụ hệ thống có thể làm máy chạy không ổn định. Ứng dụng cảnh báo trước và không cho dừng các tiến trình lõi.
- Chỉ liệt kê port TCP đang ở trạng thái lắng nghe; chưa hỗ trợ UDP.
- Ứng dụng chỉ đọc thông tin trên máy cục bộ, không gửi dữ liệu đi đâu.

## Giấy phép

[MIT](LICENSE)
