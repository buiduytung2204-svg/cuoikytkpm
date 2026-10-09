# Jenkins cho dự án Giải đấu

## Cấu hình hiện tại

- Jenkins LTS 2.580.1 được cài bằng Windows Installer và chạy thành Windows service `Jenkins`.
- Java 21 được dùng để chạy Jenkins.
- Jenkins mở tại `http://127.0.0.1:8081` trên chính máy này.
- Dữ liệu Jenkins, plugin, job và lịch sử build nằm trong `D:\tkpm\.jenkins-home`.
- Service tự khởi động cùng Windows.

## Chạy pipeline

1. Mở `http://127.0.0.1:8081`.
2. Đăng nhập `admin`; mật khẩu được lưu trong `D:\tkpm\.jenkins-home\jenkins-admin.txt`.
3. Mở job `giai-dau-ci`, chọn **Build Now**.
4. Mở **Console Output** xem kết quả. Build thành công lưu các tệp chính trong **Last Successful Artifacts**.

Build #9 đã chạy thành công dưới Windows service: `npm ci`, `npm run check` và lưu 6 artifact. Các kiểm tra bao gồm cú pháp Node/HTML, điều hướng mobile và quy tắc không đưa dữ liệu nhạy cảm lên web.

Job hiện copy source từ thư mục local `D:\tkpm` để chạy trên Windows service. `Jenkinsfile` đã có sẵn trong repository; sau khi repository GitHub được kết nối, chuyển job sang **Pipeline script from SCM** với nhánh `main` và đường dẫn `Jenkinsfile`.

## Quản lý Windows service

Mở PowerShell bằng quyền phù hợp:

```powershell
Get-Service Jenkins
Start-Service Jenkins
Stop-Service Jenkins
```

## GitHub

Repository local đã có nhánh `main` và commit pipeline. GitHub chưa được kết nối, vì vậy chưa có remote URL và chưa có mã nào được đẩy lên GitHub. Sau khi kết nối tài khoản, tạo repository, đẩy nhánh `main`, rồi đổi job `giai-dau-ci` sang repository GitHub.

Không commit `.env`, `.postgres-admin-password.txt`, database SQLite hoặc `node_modules`; các đường dẫn này đã bị loại khỏi Git.

## Giới hạn truy cập

Jenkins chỉ lắng nghe trên `127.0.0.1`; máy khác không thể truy cập. Không mở Jenkins trực tiếp lên Internet hoặc qua tunnel của ứng dụng web. Nếu thầy cần xem build từ xa, dùng Jenkins của trường hoặc thống nhất cách cấp quyền truy cập repository.
