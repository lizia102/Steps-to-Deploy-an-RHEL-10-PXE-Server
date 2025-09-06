#!/bin/bash

# 一键部署 PXE + UEFI PXE + HTTP/S Boot 安装源（支持 RHEL 10+）
# Legacy PXE 和 UEFI PXE 仅显示 HTTP 菜单
# UEFI HTTP Boot 显示 HTTP 和 HTTPS 菜单
# 新版本以增量方式添加，不影响旧版本
# 作者: lizia102


set -euo pipefail

# ====================== 配置区 ======================
ISO_PATH="/path/to/rhel-10-x86_64-dvd.iso"          # RHEL ISO 文件路径
WEB_ROOT="/var/www/html"                            # Web 服务根目录
TFTP_ROOT="/var/lib/tftpboot"                       # TFTP 根目录
USE_HTTPS="true"                                    # 是否启用 HTTPS
PXE_SUBNET="192.168.1.0"                            # PXE 子网
PXE_NETMASK="255.255.255.0"                         # 子网掩码
PXE_ROUTER="192.168.1.1"                            # 网关（也是 DHCP/TFTP/HTTP 服务器）
PXE_DNS="8.8.8.8"                                   # DNS
PXE_IP_RANGE="192.168.1.100 192.168.1.200"          # DHCP 地址池
DOMAIN_NAME="pxe.example.com"                       # 域名（用于 HTTPS）

# ====================== 日志函数 ======================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "[ERROR] $1"
    exit 1
}

# ====================== 检查是否为 root ======================
if [ "$(id -u)" -ne 0 ]; then
    error_exit "请使用 root 用户运行此脚本！"
fi

# ====================== 安装必要软件包 ======================
log "正在安装必要软件包..."
dnf install -y \
    dhcp-server \
    tftp-server \
    syslinux \
    httpd \
    mod_ssl \
    wget \
    xorriso \
    grub2-efi-x64-modules \
    shim-x64 \
    grub2-tools-extra

# ====================== 挂载 ISO 并复制文件 ======================
log "正在挂载 ISO 并复制安装源..."
mkdir -p /mnt/rhel-iso
mount -o loop "$ISO_PATH" /mnt/rhel-iso || error_exit "挂载 ISO 失败！"

ISO_NAME=$(basename "$ISO_PATH" .iso)
VERSION_DIR="$WEB_ROOT/$ISO_NAME"
rm -rf "$VERSION_DIR"
mkdir -p "$VERSION_DIR"
cp -r /mnt/rhel-iso/* "$VERSION_DIR/"

umount /mnt/rhel-iso
log "安装源已复制至 $VERSION_DIR"

# ====================== 配置 DHCP 服务 ======================
log "正在配置 DHCP 服务..."
cat > /etc/dhcp/dhcpd.conf <<EOF
subnet $PXE_SUBNET netmask $PXE_NETMASK {
    range $PXE_IP_RANGE;
    option routers $PXE_ROUTER;
    option domain-name-servers $PXE_DNS;
    next-server $PXE_ROUTER;

    # Legacy PXE
    if option arch = 00:07 {
        filename "grub/grubx64.efi";
    } else {
        filename "pxelinux.0";
    }

    # UEFI HTTP Boot
    option vendor-class-identifier "HTTPClient";
    if option arch = 16 {
        filename "http://${USE_HTTPS:+$DOMAIN_NAME}${USE_HTTPS:-$PXE_ROUTER}/$ISO_NAME/EFI/BOOT/grubx64.efi";
    }
}
EOF

systemctl enable --now dhcpd

# ====================== 配置 TFTP 服务 ======================
log "正在配置 TFTP 服务..."
systemctl enable --now tftp.socket

# 复制 Legacy PXE 启动文件
cp /usr/share/syslinux/pxelinux.0 "$TFTP_ROOT/"
cp /usr/share/syslinux/ldlinux.c32 "$TFTP_ROOT/"
cp /usr/share/syslinux/menu.c32 "$TFTP_ROOT/"
cp /usr/share/syslinux/libcom32.c32 "$TFTP_ROOT/"
cp /usr/share/syslinux/libutil.c32 "$TFTP_ROOT/"

# 复制内核和 initrd
mkdir -p "$TFTP_ROOT/images/$ISO_NAME"
cp "$VERSION_DIR/images/pxeboot/vmlinuz" "$TFTP_ROOT/images/$ISO_NAME/"
cp "$VERSION_DIR/images/pxeboot/initrd.img" "$TFTP_ROOT/images/$ISO_NAME/"

# ====================== 配置 Legacy PXE 菜单（仅 HTTP） ======================
log "正在配置 Legacy PXE 菜单..."
mkdir -p "$TFTP_ROOT/pxelinux.cfg"

cat > "$TFTP_ROOT/pxelinux.cfg/default" <<EOF
default menu.c32
prompt 0
timeout 300

MENU TITLE PXE Boot Menu

EOF

# 遍历所有版本，添加 HTTP 菜单项
for version_dir in "$WEB_ROOT"/rhel*; do
    if [ -d "$version_dir" ]; then
        version_name=$(basename "$version_dir")
        cat >> "$TFTP_ROOT/pxelinux.cfg/default" <<EOF

LABEL $version_name-http
    MENU LABEL Install $version_name (HTTP)
    KERNEL images/$version_name/vmlinuz
    APPEND initrd=images/$version_name/initrd.img inst.repo=http://$PXE_ROUTER/$version_name
EOF
    fi
done

# ====================== 配置 UEFI PXE（TFTP，仅 HTTP） ======================
log "正在配置 UEFI PXE（TFTP）..."
mkdir -p "$TFTP_ROOT/grub"
cp "$VERSION_DIR/EFI/BOOT/grubx64.efi" "$TFTP_ROOT/grub/" || \
    cp /boot/efi/EFI/redhat/grubx64.efi "$TFTP_ROOT/grub/"

cat > "$TFTP_ROOT/grub/grub.cfg" <<EOF
set timeout=5

EOF

# 遍历所有版本，添加 UEFI PXE 菜单项（仅 HTTP）
for version_dir in "$WEB_ROOT"/rhel*; do
    if [ -d "$version_dir" ]; then
        version_name=$(basename "$version_dir")
        cat >> "$TFTP_ROOT/grub/grub.cfg" <<EOF
menuentry "Install $version_name (HTTP)" {
    linuxefi /images/$version_name/vmlinuz inst.repo=http://$PXE_ROUTER/$version_name
    initrdefi /images/$version_name/initrd.img
}

EOF
    fi
done

# ====================== 配置 UEFI HTTP Boot（HTTP + HTTPS） ======================
log "正在配置 UEFI HTTP Boot..."
mkdir -p "$VERSION_DIR/EFI/BOOT"

cp "$VERSION_DIR/EFI/BOOT/grubx64.efi" "$VERSION_DIR/EFI/BOOT/" || \
    cp /boot/efi/EFI/redhat/grubx64.efi "$VERSION_DIR/EFI/BOOT/"

cp "$VERSION_DIR/EFI/BOOT/shim.efi" "$VERSION_DIR/EFI/BOOT/" || \
    cp /boot/efi/EFI/redhat/shim.efi "$VERSION_DIR/EFI/BOOT/"

cat > "$VERSION_DIR/EFI/BOOT/grub.cfg" <<EOF
set timeout=5

EOF

# 遍历所有版本，添加 UEFI HTTP Boot 菜单项（HTTP + HTTPS）
for version_dir in "$WEB_ROOT"/rhel*; do
    if [ -d "$version_dir" ]; then
        version_name=$(basename "$version_dir")
        cat >> "$VERSION_DIR/EFI/BOOT/grub.cfg" <<EOF
menuentry "Install $version_name (HTTP)" {
    linuxefi /$version_name/images/pxeboot/vmlinuz inst.repo=http://$PXE_ROUTER/$version_name
    initrdefi /$version_name/images/pxeboot/initrd.img
}

menuentry "Install $version_name (HTTPS)" {
    linuxefi /$version_name/images/pxeboot/vmlinuz inst.repo=https://$DOMAIN_NAME/$version_name
    initrdefi /$version_name/images/pxeboot/initrd.img
}

EOF
    fi
done

# ====================== 配置 HTTPS 服务 ======================
if [ "$USE_HTTPS" = "true" ]; then
    log "正在配置 HTTPS..."
    mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/pki/tls/private/pxe.key \
        -out /etc/pki/tls/certs/pxe.crt \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=PXE/CN=$DOMAIN_NAME"

    cat > /etc/httpd/conf.d/ssl-pxe.conf <<EOF
<VirtualHost *:443>
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/pxe.crt
    SSLCertificateKeyFile /etc/pki/tls/private/pxe.key
    DocumentRoot "$WEB_ROOT"
    <Directory "$WEB_ROOT">
        Options Indexes FollowSymLinks
        Require all granted
    </Directory>
</VirtualHost>
EOF

    systemctl restart httpd
fi

systemctl enable --now httpd

# ====================== 配置防火墙与 SELinux ======================
log "正在配置防火墙与 SELinux..."
firewall-cmd --permanent --add-service={http,https,dhcp,tftp}
firewall-cmd --reload

setsebool -P httpd_read_user_content=1
setsebool -P tftp_anon_write=1

# ====================== 完成 ======================
log "PXE + UEFI PXE + HTTP/S Boot 安装源部署完成！"
log "Legacy PXE 和 UEFI PXE 仅显示 HTTP 菜单。"
log "UEFI HTTP Boot 显示 HTTP 和 HTTPS 菜单。"
log "如需添加新版本，请替换 ISO_PATH 并重新运行此脚本。"