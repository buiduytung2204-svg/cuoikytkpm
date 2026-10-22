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

## Khởi tạo Jenkins lần đầu

Jenkins 2.580.1 đã được cài lại vào `C:\Jenkins`; service `Jenkins` chạy tự động trên cổng `8081`. Bản cài cũ trỏ tới ổ `D:` không còn khả dụng, nên đây là Jenkins home mới và lịch sử build/job cũ không có trong bản cài này.

Mở `http://127.0.0.1:8081`, nhập mật khẩu khởi tạo từ `C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword`, cài các plugin được đề xuất và tạo tài khoản quản trị. Sau đó tạo/cấu hình job `giai-dau-ci` theo mục GitHub phía trên. Jenkins cần quyền chạy Node.js/npm và đọc/ghi thư mục deploy; service hiện chạy dưới `LocalSystem`.

Jenkins chỉ nên lắng nghe trên `127.0.0.1`; không đưa trang Jenkins lên tunnel ngrok. `.env` không nằm trong Git và tuyệt đối không được thêm vào artifact.

Jenkins chỉ nên lắng nghe trên `127.0.0.1`; không đưa trang Jenkins lên tunnel ngrok. `.env` không nằm trong Git và tuyệt đối không được thêm vào artifact.
