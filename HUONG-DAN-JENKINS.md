# Jenkins cho dự án Giải đấu

Jenkins đã được cài và cấu hình trên máy này. Job `giai-dau-ci` lấy mã từ repository Git cục bộ, đọc `Jenkinsfile`, chạy `npm ci`, kiểm tra ứng dụng bằng `npm run check`, rồi lưu các tệp chính thành artifact.

## Chạy và nộp kết quả

1. Mở `http://127.0.0.1:8081` trên chính máy đang chạy Jenkins.
2. Đăng nhập bằng tài khoản và mật khẩu trong `D:\tkpm\.jenkins-home\jenkins-admin.txt`.
3. Mở job `giai-dau-ci` rồi chọn **Build Now**.
4. Khi build thành công, mở **Console Output** và **Last Successful Artifacts** để xem log và tải tệp. Có thể chụp ảnh các stage màu xanh và kết quả `SUCCESS` để nộp cho thầy.

Pipeline hiện kiểm tra cú pháp Node.js/HTML, điều hướng mobile, allow-list của static route và quy tắc loại trừ dữ liệu nhạy cảm. Pipeline chưa triển khai ứng dụng lên máy chủ.

## Khởi động lại Jenkins sau khi tắt máy

Mở PowerShell và chạy:

```powershell
$env:JENKINS_HOME = 'D:\tkpm\.jenkins-home'
$env:GIT_CONFIG_GLOBAL = 'D:\tkpm\.jenkins-home\gitconfig'
& 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe' '-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true' -jar "$env:TEMP\jenkins-2.580.1.war" --httpListenAddress=127.0.0.1 --httpPort=8081
```

Giữ cửa sổ PowerShell mở khi cần Jenkins. Jenkins chỉ lắng nghe trên `127.0.0.1`; các máy khác không thể đăng nhập vào Jenkins qua mạng.

## Nếu thầy cần truy cập từ máy khác

Repository và Jenkins hiện chỉ ở máy này. Để thầy tự chạy job, cần đẩy repository lên nơi thầy yêu cầu (ví dụ GitHub) hoặc dùng Jenkins do trường cấp. Không mở cổng Jenkins trực tiếp ra Internet và không dùng tunnel của ứng dụng web cho Jenkins; Jenkins có quyền chạy lệnh trên máy.

## Kiểm tra thủ công

```powershell
npm ci
npm run check
```
