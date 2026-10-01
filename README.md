# BÁO CÁO BÀI TẬP 5: THIẾT LẬP THƯ MỤC WEB AN TOÀN TẠI PHÂN VÙNG HỆ THỐNG (/opt/)

---

## 1. Mục tiêu & Phân tích yêu cầu đề bài

### 1.1. Bối cảnh & Mục tiêu
Trong môi trường thực tế (Production), việc đặt mã nguồn website tại các thư mục mặc định của hệ điều hành (như `/var/www/` hoặc `/usr/share/nginx/html/`) tiềm ẩn nhiều rủi ro:
* **Nguy cơ chiếm dụng dung lượng phân vùng gốc (`/`):** Các tệp tin log sinh ra liên tục theo thời gian, nếu ghi vào `/var/log/` có thể làm đầy phân vùng hệ thống, dẫn đến việc hệ điều hành bị treo hoặc không thể ghi thêm tiến trình.
* **Nguyên tắc cô lập ứng dụng (Isolation):** Theo chuẩn **FHS (Filesystem Hierarchy Standard)**, phân vùng `/opt/` (Optional/Add-on software) là nơi lý tưởng để chứa các phần mềm, dịch vụ độc lập của bên thứ ba hoặc ứng dụng tự phát triển. Ta có thể dễ dàng gắn (mount) một ổ đĩa / phân vùng riêng biệt (Dedicated Partition / Volume) vào `/opt/my-app` để quản lý dung lượng, backup và snapshot độc lập.
* **Nguyên tắc đặc quyền tối thiểu (Least Privilege):** 
  * Quản trị viên deploy (`devops`) chỉ cần quyền sửa mã nguồn và xem logs mà **không cần quyền root / sudo**.
  * Tiến trình dịch vụ Nginx (`www-data`) chỉ có quyền **đọc** mã nguồn tĩnh (không được sửa/ghi mã nguồn web để chống webshell/tampering), nhưng **phải có quyền ghi vào thư mục logs** để ghi nhận nhật ký truy cập và lỗi.

### 1.2. Các ràng buộc kỹ thuật
1. Mã nguồn web đặt tại: `/opt/my-app/html/`
2. Thư mục logs đặt tại: `/opt/my-app/logs/`
3. Quyền sở hữu đệ quy: User `devops`, Group `www-data` (`devops:www-data`).
4. Phân quyền truy cập (Permissions):
   * Thư mục web `/opt/my-app/html/`: `750` (`rwxr-x---`)
   * Tệp mã nguồn: `640` (`rw-r-----`)
   * Thư mục logs `/opt/my-app/logs/`: `770` (`rwxrwx---`) để Group `www-data` có quyền ghi logs.
   * Tệp logs: `660` (`rw-rw----`) để cả devops và tiến trình Nginx đều đọc/ghi được.
5. Cấu hình Server Block của Nginx ghi log truy cập (`access_log`) và log lỗi (`error_log`) trực tiếp vào đường dẫn log mới này.

---

## 2. Bảng ma trận phân quyền chi tiết

| Đường dẫn / Tệp tin | Quyền Octal | Ký hiệu (Symbolic) | Owner (`devops`) | Group (`www-data`) | Others | Mục đích / Ý nghĩa an toàn |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `/opt/my-app` | `750` | `drwxr-x---` | `rwx` (Toàn quyền) | `r-x` (Đọc & Duyệt) | `---` | Thư mục cha, cho phép Nginx duyệt qua nhưng người ngoài không thể truy cập. |
| `/opt/my-app/html/` | `750` | `drwxr-x---` | `rwx` (Toàn quyền) | `r-x` (Đọc & Duyệt) | `---` | Nginx có quyền `x` để vào thư mục đọc web, không bị lỗi **403 Forbidden**. |
| `/opt/my-app/html/index.html` | `640` | `-rw-r-----` | `rw-` (Đọc & Ghi) | `r--` (Chỉ đọc) | `---` | `devops` cập nhật code không cần sudo; Nginx chỉ đọc, ngăn hacker sửa tệp qua lỗ hổng web. |
| `/opt/my-app/logs/` | `770` | `drwxrwx---` | `rwx` (Toàn quyền) | `rwx` (Toàn quyền ghi log) | `---` | **Group `www-data` có quyền `w`** để tạo tệp log mới và ghi logs. |
| `/opt/my-app/logs/*.log` | `660` | `-rw-rw----` | `rw-` (Đọc & Ghi) | `rw-` (Đọc & Ghi) | `---` | Cả `devops` và tiến trình `www-data` có thể đọc và ghi nhật ký. |

---

## 3. Các bước thực hiện chi tiết

### Bước 1: Khởi tạo tài khoản hệ thống (nếu chưa có)
```bash
# Kiểm tra và tạo user devops
if ! id "devops" &>/dev/null; then
    sudo useradd -m -s /bin/bash devops
fi

# Kiểm tra và tạo group www-data
if ! getent group www-data &>/dev/null; then
    sudo groupadd www-data
fi
```

### Bước 2: Tạo cấu trúc thư mục và tệp tin mẫu
```bash
# Tạo cấu trúc thư mục chứa mã nguồn và logs tại /opt/
sudo mkdir -p /opt/my-app/html
sudo mkdir -p /opt/my-app/logs

# Khởi tạo tệp index.html mẫu
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

# Tạo sẵn tệp tin logs
sudo touch /opt/my-app/logs/access.log
sudo touch /opt/my-app/logs/error.log
```

### Bước 3: Phân quyền sở hữu và truy cập nâng cao
```bash
# 1. Gán quyền sở hữu toàn bộ thư mục /opt/my-app cho devops:www-data
sudo chown -R devops:www-data /opt/my-app

# 2. Phân quyền thư mục gốc và thư mục html
sudo chmod 750 /opt/my-app
sudo chmod 750 /opt/my-app/html
sudo find /opt/my-app/html -type f -exec chmod 640 {} +

# 3. Phân quyền thư mục logs: Cấp quyền GHI (write) cho group www-data
sudo chmod 770 /opt/my-app/logs
sudo find /opt/my-app/logs -type f -exec chmod 660 {} +
```

### Bước 4: Cấu hình Server Block của Nginx
Tạo tệp cấu hình `/etc/nginx/sites-available/my-app`:
```bash
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
```

Kích hoạt cấu hình và tải lại Nginx:
```bash
# Gỡ liên kết site mặc định cũ
sudo rm -f /etc/nginx/sites-enabled/default

# Kích hoạt site my-app
sudo ln -sf /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/

# Kiểm tra cú pháp cấu hình
sudo nginx -t

# Tải lại cấu hình Nginx
sudo systemctl reload nginx
```

---

## 4. Kiểm tra và xác nhận kết quả (Verification)

### 4.1. Kiểm tra phân quyền thư mục
Chạy lệnh kiểm tra trên máy chủ:
```bash
ls -la /opt/my-app/
```
**Kết quả thực tế:**
```text
total 16
drwxr-x--- 4 devops www-data 4096 Oct  1 10:19 .
drwxr-xr-x 3 root   root     4096 Oct  1 10:19 ..
drwxr-x--- 2 devops www-data 4096 Oct  1 10:19 html
drwxrwx--- 2 devops www-data 4096 Oct  1 10:19 logs
```
* `/opt/my-app/html`: Quyền `drwxr-x---` (750), sở hữu `devops:www-data`.
* `/opt/my-app/logs`: Quyền `drwxrwx---` (770), sở hữu `devops:www-data` (Group `www-data` có cờ `w`).

Kiểm tra tệp tin bên trong:
```bash
ls -la /opt/my-app/html/
ls -la /opt/my-app/logs/
```
**Kết quả thực tế:**
```text
/opt/my-app/html/:
-rw-r----- 1 devops www-data  297 Oct  1 10:20 index.html

/opt/my-app/logs/:
-rw-rw---- 1 devops www-data  320 Oct  1 10:20 access.log
-rw-rw---- 1 devops www-data    0 Oct  1 10:20 error.log
```

---

### 4.2. Thử nghiệm ghi file bằng user devops (không dùng sudo)
Chạy lệnh dưới quyền user `devops`:
```bash
# Chuyển user devops và ghi file:
su - devops
echo "Update Test" >> /opt/my-app/html/index.html
exit
```
Hoặc kiểm tra nhanh qua:
```bash
sudo -u devops bash -c 'echo "Update Test" >> /opt/my-app/html/index.html'
```
**Kết quả thực tế:**
* Lệnh thực thi thành công không có lỗi `Permission denied`.
* Nội dung tệp `index.html` được nối thêm chuỗi `Update Test`.

---

### 4.3. Kiểm tra hoạt động của Nginx và logs phát sinh
Gửi HTTP Request kiểm tra:
```bash
curl -i http://localhost/
```
**Kết quả trả về:**
```text
HTTP/1.1 200 OK
Server: nginx/1.28.3 (Ubuntu)
Content-Type: text/html
Content-Length: 297
...
<!DOCTYPE html>
<html lang="vi">
...
Update Test
```
* Mã trạng thái HTTP: **200 OK** (hoạt động bình thường, không gặp lỗi 403 Forbidden).

Kiểm tra logs phát sinh:
```bash
tail -n 5 /opt/my-app/logs/access.log
```
**Kết quả thực tế:**
```text
::1 - - [01/Oct/2026:10:20:24 +0700] "GET / HTTP/1.1" 200 297 "-" "curl/8.18.0"
::1 - - [01/Oct/2026:10:20:29 +0700] "GET / HTTP/1.1" 200 297 "-" "curl/8.18.0"
```
Log truy cập tự động được Nginx ghi vào đúng đường dẫn mới `/opt/my-app/logs/access.log`.

---

## 5. Script tự động hóa (`solution.sh`)

Toàn bộ quá trình từ chuẩn bị tài khoản, tạo thư mục, phân quyền, cấu hình Server Block Nginx đến kiểm tra toàn diện đã được đóng gói trong tệp script [solution.sh](file:///D:/Desktop/IT209/ss03/Bai5/solution.sh).

Cách chạy:
```bash
chmod +x solution.sh
sudo ./solution.sh
```
