# Jenkins CI/CD cho dự án Giải đấu

## Trạng thái hiện tại

- Jenkins LTS 2.580.1 chạy dưới Windows service `Jenkins` trên `http://127.0.0.1:8081`.
- Jenkins Home: `C:\Windows\System32\config\systemprofile\AppData\Local\Jenkins\.jenkins`.
- Job `giai-dau-ci` đã nối với GitHub và nhánh `main`; lần chạy thành công đầu tiên đã deploy ứng dụng.
- Jenkins chỉ lắng nghe trên máy này. Không đưa Jenkins lên tunnel ngrok.

## Pipeline

Job dùng **Pipeline script from SCM**:

- Repository: `https://github.com/buiduytung2204-svg/cuoikytkpm.git`
- Branch: `*/main`
- Script path: `Jenkinsfile`
- Poll SCM: mỗi 5 phút.

Khi `main` thay đổi, Jenkins checkout code, chạy `npm ci` và `npm run check`, lưu artifact, rồi deploy. Chỉ nhánh `main` được deploy.

## Đích deploy và tiến trình server

Ứng dụng được deploy vào:

```text
C:\Users\tungb\OneDrive\Tài liệu\cuoikytkpm-main\cuoikytkpm-main
```

Script `scripts/deploy-windows.ps1` yêu cầu file `.env` đã tồn tại ở thư mục đích. Nó cài dependencies trong thư mục tạm, giữ nguyên `.env` và ngrok, thay các file ứng dụng, rồi kiểm tra `http://127.0.0.1:8000/api/bootstrap-status`. Nếu bước kiểm tra thất bại, script khôi phục các file và dependencies trước đó.

Jenkins khởi động app qua Windows Scheduled Task `GiaiDauServer` dưới tài khoản Windows đang đăng nhập. Cách này giữ quyền cho client quản lý server. Cần đăng nhập Windows khi pipeline deploy; sau deploy, client vẫn có thể bật/tắt server và ngrok.

## Chạy hoặc xem build

1. Mở `http://127.0.0.1:8081`.
2. Chọn job `giai-dau-ci`.
3. Dùng **Build Now** để chạy thủ công, hoặc mở **Console Output** để xem tiến trình.

Windows service Jenkins có thể điều khiển trong PowerShell:

```powershell
Get-Service Jenkins
Start-Service Jenkins
Stop-Service Jenkins
```

## Lưu ý

- Không commit `.env`, database hoặc thông tin bí mật.
- Artifact không chứa `.env`.
- Tunnel ngrok chỉ dùng cho web app ở cổng 8000, không dùng để công khai Jenkins.
