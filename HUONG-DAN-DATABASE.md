# Cài web giải đấu cho nhiều người dùng qua Internet

Ứng dụng dùng Node.js làm máy chủ và PostgreSQL làm database. Trình duyệt không kết nối trực tiếp tới PostgreSQL. Máy chủ Node.js dùng connection pool giới hạn mặc định 20 kết nối, còn các thao tác ghi trên những mục khác nhau được gộp để tránh ghi đè lẫn nhau. Nếu hai người sửa cùng một mục, người lưu sau sẽ được báo xung đột và cần tải lại trang.

## 1. Cài PostgreSQL trên Windows

1. Tải bộ cài Windows từ [trang PostgreSQL chính thức](https://www.postgresql.org/download/windows/).
2. Trong quá trình cài, đặt mật khẩu mạnh cho tài khoản `postgres`. Dùng mật khẩu gồm chữ, số và dấu gạch dưới để dễ đặt trong URL.
3. Mở **SQL Shell (psql)** từ Start Menu, kết nối bằng tài khoản `postgres`, rồi tạo database:

   ```sql
   CREATE DATABASE giai_dau;
   ```

Giữ cổng PostgreSQL chỉ truy cập được từ máy này; tunnel chỉ trỏ tới máy chủ web Node.js ở cổng 8000.

## 2. Cài và chạy web

Mở PowerShell tại `D:\tkpm`:

```powershell
Copy-Item .env.example .env
```

Mở `.env`, thay `CHANGE_THIS_PASSWORD` bằng mật khẩu PostgreSQL vừa đặt. Nếu mật khẩu có ký tự đặc biệt như `@`, `:`, `/` hoặc `#`, cần URL-encode ký tự đó.

Sau đó chạy:

```powershell
npm install
npm start
```

Mở `http://127.0.0.1:8000/giai-dau.html`. Nếu PostgreSQL chưa có dữ liệu, trang sẽ cho tạo tài khoản quản trị đầu tiên; đặt mật khẩu ít nhất 12 ký tự.

Nếu có `giai-dau.sqlite3` với dữ liệu cũ, máy chủ sẽ nhập một lần sang PostgreSQL. Các mật khẩu mẫu hoặc mật khẩu dưới 12 ký tự sẽ buộc đổi khi đăng nhập. Giữ bản SQLite cũ làm bản sao riêng tư cho tới khi xác nhận đã nhập đủ dữ liệu; không đưa file đó lên Internet.

## 3. Tạo tunnel thử nghiệm

1. Tải và cài `cloudflared` bằng bộ cài Windows từ [Cloudflare](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/).
2. Giữ máy chủ chạy trong PowerShell thứ nhất (`npm start`). Mở PowerShell thứ hai và chạy:

   ```powershell
   cloudflared tunnel --url http://localhost:8000
   ```

3. Mở địa chỉ `https://....trycloudflare.com` mà lệnh in ra. Giữ cả hai cửa sổ PowerShell mở khi dùng.

Quick Tunnel có địa chỉ tạm và dành cho thử nghiệm. Để dùng ổn định, cần một domain đã đưa vào Cloudflare, sau đó tạo tunnel trong Cloudflare Dashboard, thêm route **Published application** tới `http://localhost:8000` và cài tunnel như Windows service. [Hướng dẫn Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/).

## Bảo mật và sao lưu

- Chỉ chia sẻ địa chỉ tunnel sau khi đổi mật khẩu tài khoản cũ. Mật khẩu được băm bằng scrypt; phiên đăng nhập dùng cookie `HttpOnly`.
- PostgreSQL và file `.env` không được phục vụ qua web. Không gửi nội dung `.env` hoặc tunnel token cho người khác.
- Máy tính cần bật, có Internet ổn định và không ngủ trong thời gian mọi người truy cập. Tắt máy sẽ làm web ngừng hoạt động.
- Sao lưu database định kỳ bằng `pg_dump`; cất bản sao ngoài thư mục dự án.
- Có thể đổi số kết nối tối đa bằng `DB_POOL_SIZE` trong `.env` nếu cần.
