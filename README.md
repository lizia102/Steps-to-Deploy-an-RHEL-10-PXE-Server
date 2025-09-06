# 📦 RHEL PXE + UEFI PXE + HTTP/S Boot 一键部署脚本

## 📖 简介

本脚本用于一键部署 RHEL 网络安装源，支持以下三种启动方式：

| 启动方式          | 客户端设置               | 预期行为 |
|-------------------|--------------------------|----------|
| Legacy PXE        | BIOS 模式 + 网络启动     | 显示所有版本的 HTTP 菜单 |
| UEFI PXE          | UEFI 模式 + 网络启动     | 显示所有版本的 HTTP 菜单 |
| UEFI HTTP Boot    | UEFI 模式 + HTTP Boot    | 显示所有版本的 HTTP 和 HTTPS 菜单 |

- Legacy PXE 和 UEFI PXE 仅显示 HTTP 菜单
- UEFI HTTP Boot 显示 HTTP 和 HTTPS 菜单
- 支持多版本并存，后续版本增量添加

---

## ✨ 功能特点

- ✅ 支持 Legacy PXE（HTTP）
- ✅ 支持 UEFI PXE（HTTP）
- ✅ 支持 UEFI HTTP Boot（HTTP + HTTPS）
- ✅ 自动配置 DHCP、TFTP、HTTP/S 服务
- ✅ 自动生成启动菜单
- ✅ 支持多版本并存
- ✅ 增量添加新版本
- ✅ 自动适配防火墙与 SELinux

---

## 🛠️ 环境要求

- 操作系统：RHEL 10+ 或兼容系统（如 CentOS Stream、Rocky Linux、AlmaLinux）
- 用户权限：必须以 root 用户运行
- 网络环境：
- 静态 IP 地址（作为 DHCP/TFTP/HTTP 服务器）
- 客户端与服务器在同一局域网
- 必要软件包：脚本会自动安装

---

## 📁 脚本文件结构

/var/www/html/ ├── rhel10/ │   ├── EFI/ │   ├── images/ │   └── ... /var/lib/tftpboot/ ├── images/ ├── grub/ ├── pxelinux.0 └── ... /etc/dhcp/dhcpd.conf /etc/httpd/conf.d/ssl-pxe.conf

---

## ⚙️ 配置说明

在运行脚本前，请根据实际情况修改以下配置：

bash # ====================== 配置区 ====================== ISO_PATH="/path/to/rhel-10-x86_64-dvd.iso"          # RHEL ISO 文件路径 WEB_ROOT="/var/www/html"                            # Web 服务根目录 TFTP_ROOT="/var/lib/tftpboot"                       # TFTP 根目录 USE_HTTPS="true"                                    # 是否启用 HTTPS PXE_SUBNET="192.168.1.0"                            # PXE 子网 PXE_NETMASK="255.255.255.0"                         # 子网掩码 PXE_ROUTER="192.168.1.1"                            # 网关（也是 DHCP/TFTP/HTTP 服务器） PXE_DNS="8.8.8.8"                                   # DNS PXE_IP_RANGE="192.168.1.100 192.168.1.200"          # DHCP 地址池 DOMAIN_NAME="pxe.example.com"                       # 域名（用于 HTTPS） 

---

## 🚀 使用方法

### 1. 下载脚本

将脚本保存为 pxe-http-https-deploy.sh。

### 2. 配置 ISO 路径

编辑脚本，修改 ISO_PATH 为您的 RHEL ISO 文件路径。

### 3. 赋予执行权限

bash chmod +x pxe-http-https-deploy.sh 

### 4. 运行脚本

bash sudo ./pxe-http-https-deploy.sh 

脚本会自动完成所有配置，无需手动干预。

---

## 🔁 更新版本

如需添加新版本，只需：

1. 下载新版 RHEL ISO
2. 修改脚本中的 ISO_PATH 为新 ISO 路径
3. 重新运行脚本

脚本会自动：

- 创建新版本目录
- 复制新版本文件
- 更新所有启动菜单
- 不影响旧版本

---

## ✅ 验证方法

### Legacy PXE

1. 客户端设置为 BIOS 模式 + 网络启动
2. 启动后应显示 PXE 菜单，仅包含 HTTP 选项
3. 选择版本后进入安装程序

### UEFI PXE

1. 客户端设置为 UEFI 模式 + 网络启动
2. 启动后应显示 GRUB 菜单，仅包含 HTTP 选项
3. 选择版本后进入安装程序

### UEFI HTTP Boot

1. 客户端设置为 UEFI 模式 + HTTP Boot
2. 启动后应显示 GRUB 菜单，包含 HTTP 和 HTTPS 选项
3. 选择版本和协议后进入安装程序

---

## 🔒 防火墙与 SELinux

脚本会自动配置防火墙和 SELinux：

bash firewall-cmd --permanent --add-service={http,https,dhcp,tftp} firewall-cmd --reload  setsebool -P httpd_read_user_content=1 setsebool -P tftp_anon_write=1 

---

## 🛡️ 安全建议

- 如生产环境使用 HTTPS，建议使用正式 SSL 证书
- 限制 DHCP 地址池范围，避免 IP 冲突
- 定期更新 RHEL ISO 和脚本

---

## 📝 注意事项

- 确保客户端固件支持相应的启动方式
- 建议先在虚拟机或测试环境验证
- 如需集成 Kickstart 自动安装，可进一步定制脚本

---


## 📄 许可证

本脚本遵循 MIT 许可证，可自由使用、修改和分发。

