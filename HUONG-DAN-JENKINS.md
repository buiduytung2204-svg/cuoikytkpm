# Jenkins CI/CD cho dự án Giải đấu

## Pipeline hiện tại

`Jenkinsfile` chạy trên agent Linux và thực hiện:

1. Checkout source từ SCM.
2. Dùng image `node:22-alpine` để chạy `npm ci` và `npm run check`.
3. Trên nhánh `main`, build image từ `Dockerfile`.
4. Nếu có khai báo `DOCKERHUB_REPO`, đẩy image lên Docker Hub bằng credential Jenkins có ID `hubdocker`.
5. Lưu các file build làm artifact của Jenkins.

Nhánh khác chỉ chạy validate và lưu artifact. Pipeline không tự thay container app/database đang chạy để tránh ghi đè môi trường hiện tại.

## Yêu cầu cho Jenkins agent

Pipeline dùng Docker Pipeline plugin và cần agent có Docker CLI cùng quyền kết nối Docker daemon. Jenkins container hiện tại chạy Linux; Jenkinsfile Windows cũ dùng `bat` và đường dẫn deploy trên một máy cụ thể nên đã được thay bằng pipeline tương thích Linux.

Trong Jenkins, vào **Manage Jenkins → Plugins** và cài **Docker Pipeline** nếu chưa có. Đảm bảo agent được gán Docker daemon an toàn trước khi chạy job. Không bật Docker daemon TCP không mã hóa ra mạng công cộng.

## Tạo job

1. Mở Jenkins tại `http://localhost:8081` và hoàn tất Setup Wizard.
2. Tạo **Pipeline** job (hoặc Multibranch Pipeline nếu muốn build nhiều nhánh).
3. Chọn **Pipeline script from SCM**, cấu hình Git repository của dự án, branch `*/main` và script path `Jenkinsfile`.
4. Lưu job và chạy thử. Bản build đầu tiên có thể không push image nếu để `DOCKERHUB_REPO` trống.

## Đẩy image lên Docker Hub

1. Tạo repository trên Docker Hub, ví dụ `ten-tai-khoan/giai-dau`.
2. Trong Jenkins thêm credential kiểu **Username with password** (ưu tiên Docker Hub access token thay cho mật khẩu tài khoản) và đặt ID chính xác là `hubdocker`.
3. Chạy build trên nhánh `main`, nhập `DOCKERHUB_REPO` theo dạng `ten-tai-khoan/giai-dau` và `IMAGE_TAG` mong muốn.
4. Xem **Console Output** và kiểm tra repository trên Docker Hub.

Không lưu username/token trong Jenkinsfile, mã nguồn hoặc file `.env` được commit.

## Jenkins container local

Jenkins chạy tại `http://localhost:8081` trong container `giai-dau-jenkins`. Dữ liệu cấu hình nằm trong volume `giai_dau_jenkins_home`.

```powershell
docker logs -f giai-dau-jenkins
docker restart giai-dau-jenkins
```

Compose của ứng dụng chạy riêng ở `http://localhost:8000`; Jenkins pipeline chưa tự deploy Compose.
