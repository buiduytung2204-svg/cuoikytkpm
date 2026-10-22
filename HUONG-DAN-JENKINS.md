# Jenkins CI/CD cho dự án Giải đấu

## Pipeline

`Jenkinsfile` thực hiện checkout, `npm ci`, `npm run check`, lưu artifact, rồi triển khai nhánh `main` lên máy Windows. Jenkins kiểm tra GitHub mỗi 5 phút; webhook không cần truy cập Jenkins từ Internet.

Đích deploy hiện dùng thư mục ứng dụng local:

```text
C:\Users\tungb\OneDrive\Tài liệu\cuoikytkpm-main\cuoikytkpm-main
```

Script `scripts/deploy-windows.ps1` yêu cầu `.env` đã có sẵn ở đích. Nó dựng dependencies trong thư mục tạm, giữ nguyên `.env`, thay mã ứng dụng, khởi động lại Node trên cổng 8000 và kiểm tra `/api/bootstrap-status`. Tiến trình ngrok đang chạy được giữ nguyên; nút client vẫn có thể tắt/bật server và tunnel. Nếu health check thất bại, script khôi phục bản ứng dụng trước.

## Nối job `giai-dau-ci` với GitHub

Trong Jenkins, cấu hình job dạng **Pipeline script from SCM**:

- SCM: Git
- Repository URL: `https://github.com/buiduytung2204-svg/cuoikytkpm.git`
- Branch specifier: `*/main`
- Script path: `Jenkinsfile`

Không bật thêm polling trong giao diện; lịch polling 5 phút đã nằm trong Jenkinsfile. Mỗi lần `main` thay đổi, Jenkins sẽ tự build và deploy sau khi các bước kiểm tra thành công. Nhánh khác chỉ chạy CI.

## Trạng thái Jenkins trên máy

Lần kiểm tra gần nhất, Windows service `Jenkins` đang dừng và được cấu hình chạy `D:\Jenkins\jenkins.exe`; đường dẫn đó không khả dụng trong môi trường hiện tại, nên chưa thể bật job hoặc chạy deploy từ đây. Cần khôi phục Jenkins tại đường dẫn cấu hình hoặc cài Jenkins lại, rồi trỏ job `giai-dau-ci` tới SCM ở trên. Jenkins cần chạy bằng tài khoản có quyền đọc/ghi thư mục đích và quyền chạy Node.js/npm. Service hiện khai báo `LocalSystem`, tài khoản này có quyền hệ thống trên thư mục ứng dụng đã phát hiện.

Jenkins chỉ nên lắng nghe trên `127.0.0.1`; không đưa trang Jenkins lên tunnel ngrok. `.env` không nằm trong Git và tuyệt đối không được thêm vào artifact.
