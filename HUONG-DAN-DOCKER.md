# Hướng dẫn chạy dự án bằng Docker

Hệ thống được thiết lập gồm 2 container:
1. **giai-dau-db**: Cơ sở dữ liệu PostgreSQL 16 Alpine.
2. **giai-dau-app**: Ứng dụng Node.js (v22 Alpine) phục vụ trang web và API.

---

## 1. Yêu cầu trước khi chạy
- Đã cài đặt **Docker Desktop** trên Windows và Docker đang chạy.

---

## 2. Cách khởi chạy nhanh

### Cách 1: Sử dụng file script có sẵn (Khuyên dùng trên Windows)
- Nhấp đúp chuột vào file **`Chay-docker.bat`**.
- File script sẽ tự động build image, kích hoạt PostgreSQL và Node server, đồng thời tự động mở trang web:
  `http://localhost:8000/giai-dau.html`

### Cách 2: Sử dụng dòng lệnh (PowerShell / Command Prompt)
Mở terminal tại thư mục dự án và chạy:

```bash
docker compose up -d --build
```

Sau khi hoàn tất, mở trình duyệt tại:
- **Địa chỉ web**: [http://localhost:8000/giai-dau.html](http://localhost:8000/giai-dau.html)
- **Tài khoản ban đầu**: Nếu database mới tinh, hệ thống sẽ yêu cầu tạo tài khoản quản trị đầu tiên (mật khẩu tối thiểu 12 ký tự).

---

## 3. Các lệnh thường dùng

- **Xem nhật ký hoạt động (Logs):**
  ```bash
  docker compose logs -f app
  ```

- **Dừng hệ thống:**
  - Nhấp đúp vào **`Dung-docker.bat`**, hoặc chạy lệnh:
  ```bash
  docker compose down
  ```

- **Dừng và xóa toàn bộ dữ liệu database để làm mới từ đầu:**
  ```bash
  docker compose down -v
  ```

- **Kiểm tra trạng thái container:**
  ```bash
  docker compose ps
  ```

---

## 4. Cấu hình cổng và kết nối

| Dịch vụ | Cổng trên máy tính (Host) | Cổng container | Chú thích |
|---|---|---|---|
| Web App | `8000` | `8000` | Truy cập `http://localhost:8000` |
| PostgreSQL | `5432` | `5432` | Kết nối qua pgAdmin hoặc DBeaver |

Dữ liệu của PostgreSQL được lưu trữ bền vững trong Docker volume: `postgres_data`.
