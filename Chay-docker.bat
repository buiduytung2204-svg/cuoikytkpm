@echo off
chcp 65001 >nul
echo ===================================================
echo     KHỞI ĐỘNG DỰ ÁN QUẢN LÝ GIẢI ĐẤU VỚI DOCKER
echo ===================================================
echo Đang xây dựng và khởi chạy các container (PostgreSQL + Node.js)...
docker compose up -d --build

if %ERRORLEVEL% equ 0 (
    echo.
    echo [THÀNH CÔNG] Server đang chạy tại: http://localhost:8000/giai-dau.html
    echo.
    echo Mở trình duyệt tại: http://localhost:8000/giai-dau.html
    start http://localhost:8000/giai-dau.html
) else (
    echo.
    echo [LỖI] Không thể khởi động Docker. Hãy kiểm tra xem Docker Desktop đã bật chưa!
)
pause
