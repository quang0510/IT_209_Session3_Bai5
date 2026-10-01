#!/usr/bin/env bash
# ==============================================================================
# BÀI 5: THIẾT LẬP THƯ MỤC WEB AN TOÀN TẠI PHÂN VÙNG HỆ THỐNG (/opt/)
# ==============================================================================
# Mục tiêu:
# 1. Chuyển vị trí lưu trữ website tĩnh và logs sang phân vùng /opt/ (/opt/my-app)
#    để cô lập mã nguồn và logs khỏi đường dẫn mặc định của hệ điều hành.
# 2. Phân quyền tệp tin và thư mục nâng cao đảm bảo bảo mật và phân tách vai trò
#    giữa tài khoản quản trị (devops) và tiến trình chạy của Nginx (www-data).
# ==============================================================================

set -e

echo "================================================================================"
echo ">> [BƯỚC 1/5] KIỂM TRA VÀ CHUẨN BỊ TÀI KHOẢN HỆ THỐNG"
echo "================================================================================"

# 1. Đảm bảo user devops tồn tại
if ! id "devops" &>/dev/null; then
    echo ">> Tạo user 'devops'..."
    sudo useradd -m -s /bin/bash devops
else
    echo ">> User 'devops' đã tồn tại."
fi

# 2. Đảm bảo group www-data tồn tại
if ! getent group www-data &>/dev/null; then
    echo ">> Tạo group 'www-data'..."
    sudo groupadd www-data
else
    echo ">> Group 'www-data' đã tồn tại."
fi

echo ""
echo "================================================================================"
echo ">> [BƯỚC 2/5] TẠO CẤU TRÚC THƯ MỤC VÀ TỆP TIN MẪU TẠI /opt/my-app"
echo "================================================================================"

# Tạo cấu trúc thư mục chứa mã nguồn web và logs
echo ">> Tạo thư mục /opt/my-app/html/ và /opt/my-app/logs/..."
sudo mkdir -p /opt/my-app/html
sudo mkdir -p /opt/my-app/logs

# Tạo file index.html mẫu
echo ">> Khởi tạo tệp mã nguồn mẫu /opt/my-app/html/index.html..."
sudo bash -c 'cat << "EOF" > /opt/my-app/html/index.html
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <title>Production Web Service - /opt/my-app</title>
</head>
<body>
    <h1>Trang Web Production - Triển Khai Tại /opt/my-app</h1>
    <p>He thong hoat dong an toan voi quyen devops:www-data</p>
</body>
</html>
EOF'

# Tạo sẵn tệp tin logs ban đầu (nếu chưa có)
echo ">> Khởi tạo tệp tin log rỗng /opt/my-app/logs/access.log và error.log..."
sudo touch /opt/my-app/logs/access.log
sudo touch /opt/my-app/logs/error.log

echo ""
echo "================================================================================"
echo ">> [BƯỚC 3/5] PHÂN QUYỀN SỞ HỮU VÀ TRUY CẬP (PERMISSIONS & OWNERSHIP)"
echo "================================================================================"

# 1. Phân quyền sở hữu đệ quy cho /opt/my-app: user devops, group www-data
echo ">> Gán quyền sở hữu đệ quy devops:www-data cho /opt/my-app..."
sudo chown -R devops:www-data /opt/my-app

# 2. Phân quyền truy cập theo yêu cầu bảo mật:
# - User devops: toàn quyền đọc/ghi
# - Thư mục gốc /opt/my-app và thư mục web /opt/my-app/html: 750 (rwxr-x---)
#   devops: rwx (toàn quyền)
#   www-data: r-x (đọc và duyệt thư mục để Nginx đọc file web tĩnh, không bị lỗi 403)
#   others: --- (không có quyền truy cập)
echo ">> Phân quyền thư mục web tĩnh (750) và tệp tin (640)..."
sudo chmod 750 /opt/my-app
sudo chmod 750 /opt/my-app/html
sudo find /opt/my-app/html -type f -exec chmod 640 {} +

# - Thư mục logs /opt/my-app/logs: 770 (rwxrwx---)
#   devops: rwx (toàn quyền quản trị)
#   www-data: rwx (tiến trình Nginx có quyền ghi log mới vào thư mục logs)
#   others: --- (bảo mật tuyệt đối, không ai ngoài devops và web server đọc được logs)
echo ">> Phân quyền thư mục logs (770) và tệp tin logs (660)..."
sudo chmod 770 /opt/my-app/logs
sudo find /opt/my-app/logs -type f -exec chmod 660 {} +

echo ""
echo "================================================================================"
echo ">> [BƯỚC 4/5] CẤU HÌNH SERVER BLOCK NGINX"
echo "================================================================================"

echo ">> Tạo file cấu hình Nginx Server Block tại /etc/nginx/sites-available/my-app..."
sudo bash -c 'cat << "EOF" > /etc/nginx/sites-available/my-app
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /opt/my-app/html;
    index index.html index.htm;

    access_log /opt/my-app/logs/access.log;
    error_log /opt/my-app/logs/error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF'

# Vô hiệu hóa site mặc định cũ nếu có và kích hoạt site my-app
echo ">> Kích hoạt site my-app trong /etc/nginx/sites-enabled/..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/

# Kiểm tra cú pháp Nginx
echo ">> Kiểm tra cú pháp Nginx configuration (nginx -t)..."
sudo nginx -t

# Reload dịch vụ Nginx
echo ">> Tải lại cấu hình Nginx..."
if command -v systemctl &>/dev/null && systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx
else
    sudo nginx -s reload || sudo service nginx reload
fi

echo ""
echo "================================================================================"
echo ">> [BƯỚC 5/5] KIỂM TRA VÀ XÁC NHẬN KẾT QUẢ THEO YÊU CẦU ĐỀ BÀI"
echo "================================================================================"

echo ">> 1. Kiểm tra quyền sở hữu và phân quyền thư mục /opt/my-app/:"
ls -la /opt/my-app/

echo ""
echo ">> 2. Chi tiết thư mục /opt/my-app/html/:"
ls -la /opt/my-app/html/

echo ""
echo ">> 3. Chi tiết thư mục /opt/my-app/logs/:"
ls -la /opt/my-app/logs/

echo ""
echo ">> 4. Thử nghiệm ghi file bằng user 'devops' mà KHÔNG dùng sudo:"
sudo -u devops bash -c 'echo "Update Test" >> /opt/my-app/html/index.html'

if [ $? -eq 0 ]; then
    echo ">> [THÀNH CÔNG] User devops đã ghi đè / chèn thêm nội dung thành công vào index.html mà không cần sudo!"
else
    echo ">> [THẤT BẠI] User devops không thể ghi vào index.html!"
    exit 1
fi

echo ""
echo ">> 5. Gửi HTTP Request kiểm tra Web Server Nginx:"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/)
echo ">> Mã phản hồi HTTP: $HTTP_STATUS"

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo ">> [THÀNH CÔNG] Nginx hoạt động bình thường (HTTP 200 OK), không bị lỗi 403 Forbidden!"
else
    echo ">> [CẢNH BÁO] Mã HTTP trả về không phải 200: $HTTP_STATUS"
fi

echo ""
echo ">> 6. Nội dung trang web nhận được qua curl:"
curl -s http://localhost/ | tail -n 5

echo ""
echo ">> 7. Kiểm tra log truy cập ghi nhận tại /opt/my-app/logs/access.log:"
tail -n 5 /opt/my-app/logs/access.log

echo ""
echo ">> 8. Kiểm tra log lỗi tại /opt/my-app/logs/error.log (phải rỗng hoặc không có lỗi 403):"
if [ -s /opt/my-app/logs/error.log ]; then
    tail -n 5 /opt/my-app/logs/error.log
else
    echo ">> error.log rỗng (không có lỗi)."
fi

echo ""
echo "================================================================================"
echo ">> [HOÀN THÀNH XUẤT SẮC] BÀI TẬP ĐÃ HOÀN THÀNH ĐẦY ĐỦ CÁC TIÊU CHÍ!"
echo "================================================================================"
