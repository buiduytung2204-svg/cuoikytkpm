# Jenkins cho dự án Giải đấu

Pipeline hiện có ba bước: lấy mã nguồn từ Git, cài đúng dependency theo `package-lock.json`, rồi kiểm tra cú pháp Node.js/HTML, điều hướng mobile và các quy tắc không đưa tệp bí mật/database lên web. Kết quả build lưu lại `Jenkinsfile` và các tệp chính làm artifact.

## Yêu cầu

- Jenkins bản Windows hiện hành cần Java 21 trở lên.
- Máy đã có Node.js và npm.
- Tạo một repository Git cho bài tập. Không đưa `.env`, `.postgres-admin-password.txt`, `node_modules` hoặc file database SQLite vào repository.

## Tạo Pipeline job

1. Cài Jenkins bằng bộ cài Windows chính thức và hoàn tất tài khoản quản trị ban đầu.
2. Đưa mã nguồn cùng `Jenkinsfile` lên repository Git của bài tập.
3. Trong Jenkins chọn **New Item → Pipeline**.
4. Ở **Pipeline definition**, chọn **Pipeline script from SCM**, SCM **Git**, điền URL repository, branch và Script Path `Jenkinsfile`.
5. Chọn **Build Now**. Build thành công khi các stage **Checkout**, **Install dependencies** và **Validate application** đều xanh.
6. Mở **Console Output** và **Archived Artifacts** để chụp ảnh nộp bài.

Jenkinsfile chưa tự triển khai ứng dụng. Web vẫn được chạy riêng bằng `npm start`; database và Cloudflare Tunnel cũng là các dịch vụ riêng. Nếu đề bài yêu cầu tự động triển khai, cần bổ sung đúng môi trường deploy mà thầy yêu cầu.

## Kiểm tra trên máy phát triển

```powershell
npm ci
npm run check
```
