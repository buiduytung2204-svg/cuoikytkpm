@echo off
chcp 65001 >nul
echo ===================================================
echo     DỪNG DỰ ÁN QUẢN LÝ GIẢI ĐẤU DOCKER
echo ===================================================
echo Đang dừng các container...
docker compose down

echo.
echo [THÀNH CÔNG] Đã dừng tất cả các container.
pause
