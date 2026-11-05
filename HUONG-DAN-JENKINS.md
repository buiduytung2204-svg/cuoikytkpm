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
- kakakakakakaka

## Continuous deployment to Docker Desktop

Jenkins polls `main` every minute. After a commit reaches GitHub, the pipeline validates the app, builds the CI image, then uses the online `windows-docker` agent to deploy the app through the host Docker Desktop engine. Open Jenkins at `http://localhost:8081`, select `giai-dau-ci`, and follow the build stages and Console Output.

The Windows agent starts at user logon through the scheduled task `Jenkins Windows Docker Agent`. Docker Desktop must be running and the user must be signed in for deployment to work. The agent uses the local Docker CLI; the Jenkins DinD daemon is not used for deployment.

The deploy stage is restricted to `main`. It deploys application files from the checked-out commit into `C:\Users\tungb\cuoikytkpm-git`, where the existing Compose project and private `.env.docker` live. It rebuilds and recreates only the `app` service, waits for its health check, and keeps the PostgreSQL service and named volume untouched. If the new app fails its health check, the stage restores the previous app image and files.

To make a deployment, commit and push changes to `main`. A manual build can be started from Jenkins with **Build Now**; choose the main branch job. For other computers, update the deploy directory in `Jenkinsfile` and `scripts/deploy-docker-windows.ps1`, then configure a connected Windows agent with the label `windows-docker`.