# Jenkins CI/CD cho dự án Giải đấu

## Jenkins trên Docker

Jenkins chạy bằng Docker Compose trên máy này tại http://localhost:8081. Cấu hình nằm trong docker-compose.jenkins.yml và Dockerfile.jenkins.

```powershell
docker compose -p giai-dau-jenkins -f docker-compose.jenkins.yml up -d --build
docker compose -p giai-dau-jenkins -f docker-compose.jenkins.yml ps
docker compose -p giai-dau-jenkins -f docker-compose.jenkins.yml logs -f jenkins
```

Dữ liệu Jenkins được lưu trong volume giai-dau-jenkins-home; workspace và Docker image cache cũng dùng volume riêng. Dừng hoặc khởi động lại container không xóa dữ liệu. Không dùng docker compose down -v vì lệnh đó xóa các volume dữ liệu.

Jenkins chỉ bind vào 127.0.0.1, không công khai cổng ra mạng. Jenkins sử dụng Docker-in-Docker có TLS ở mạng nội bộ Compose để build image.

## Pipeline

Job giai-dau-ci lấy mã từ repository GitHub buiduytung2204-svg/cuoikytkpm, nhánh main, file Jenkinsfile. Jenkins kiểm tra GitHub mỗi phút và thực hiện:

1. Checkout mã nguồn.
2. Chạy npm ci và npm run check trong Node 22.
3. Build Docker image trên nhánh main.
4. Lưu build artifacts.
5. Đẩy image lên Docker Hub nếu đã cấu hình DOCKERHUB_REPO và credential có ID hubdocker.

Build lỗi sẽ được ghi trong Console Output của Jenkins.

## Tài khoản Jenkins

Thông tin đăng nhập quản trị nằm trong file cục bộ C:\Users\tungb\.jenkins-home\jenkins-admin.txt. File này không được đưa vào Git. Không commit mật khẩu, API token hoặc Docker Hub access token.

## Jenkins Windows service cũ

Windows service Jenkins cũ đã được giữ lại nhưng dừng để tránh trùng cổng với container. Bản sao an toàn của Jenkins home nằm tại C:\JenkinsMigration\home; dữ liệu đang hoạt động được chuyển vào volume Docker giai-dau-jenkins-home.
