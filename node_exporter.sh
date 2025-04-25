#!/bin/bash

# 检查当前操作系统类型和包管理器
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_ID=$VERSION_ID
    else
        echo "无法检测操作系统类型。"
        exit 1
    fi
}

# 检查 systemd 服务文件路径是否可用
check_service_path() {
    if [ ! -d "/etc/systemd/system" ]; then
        echo "系统不支持 /etc/systemd/system 路径。"
        exit 1
    fi
}

# 安装所需的依赖工具（curl、tar 等）
install_dependencies() {
    case $OS in
    ubuntu|debian)
        sudo apt update -y && sudo apt install -y curl tar
        ;;
    centos|rocky|almalinux|fedora)
        sudo yum install -y curl tar
        ;;
    suse|opensuse)
        sudo zypper install -y curl tar
        ;;
    *)
        echo "暂不支持的操作系统: $OS"
        exit 1
        ;;
    esac
}

# 停止并清理旧版本的 Node Exporter
cleanup_old_node_exporter() {
    if systemctl is-active --quiet node_exporter; then
        echo "node_exporter 正在运行，停止并禁用它。"
        sudo systemctl stop node_exporter
        sudo systemctl disable node_exporter
    fi

    service_path=$(sudo systemctl show -p FragmentPath node_exporter | sed 's/FragmentPath=//')
    if [ -f "$service_path" ]; then
        sudo rm -f "$service_path"
    fi

    echo "删除 node_exporter 相关文件和目录..."
    sudo rm -rf /usr/local/bin/node_exporter
    sudo rm -rf /etc/systemd/system/node_exporter.service
    sudo rm -rf /etc/systemd/system/node_exporter.socket
    sudo rm -rf /etc/sysconfig/node_exporter
    sudo rm -rf /etc/default/node_exporter
    sudo rm -rf /var/lib/node_exporter
}

# 下载并解压最新版本的 Node Exporter
download_and_extract_node_exporter() {
    # 使用 GitHub API 获取最新的 node_exporter 版本号
    latest_version=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/^v//')
    # latest_version=1.8.0  # 可以通过 GitHub API 动态获取最新版本
    echo "最新版本的 node_exporter 是 $latest_version"
    download_url="https://xxxx.oss-cn-hangzhou.aliyuncs.com/software/node_exporter-${latest_version}.linux-amd64.tar.gz"

    echo "正在下载 node_exporter..."
    if ! curl -o "node_exporter-${latest_version}.linux-amd64.tar.gz" -C - $download_url; then
        echo "下载失败，请检查网络连接或下载链接。"
        exit 1
    fi
    
    echo "正在验证下载的文件格式..."
    if ! file "node_exporter-${latest_version}.linux-amd64.tar.gz" | grep -q "gzip compressed data"; then
        echo "下载的文件不是有效的 gzip 格式，请检查下载链接或文件。"
        echo "正在清理下载的文件..."
        sudo rm -f "node_exporter-${latest_version}.linux-amd64.tar.gz"
        exit 1
    fi

    echo "正在解压 node_exporter..."
    if ! tar -zxvf "node_exporter-${latest_version}.linux-amd64.tar.gz"; then
        echo "解压失败，请检查压缩文件。"
        echo "正在清理下载的文件和目录..."
        sudo rm -rf "node_exporter-${latest_version}.linux-amd64.tar.gz"
        sudo rm -rf "node_exporter-${latest_version}.linux-amd64"
        return 1
    fi
    sudo mv "node_exporter-${latest_version}.linux-amd64/node_exporter" /usr/sbin/
}

# 创建 node_exporter 用户
create_node_exporter_user() {
    if ! id "node_exporter" &>/dev/null; then
        echo "创建 node_exporter 用户..."
        sudo useradd --no-create-home --shell /sbin/nologin node_exporter
    fi
}

# 配置 systemd 服务
configure_systemd_service() {
    echo "创建 node_exporter 的 systemd 服务文件..."
    sudo bash -c 'cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Requires=node_exporter.socket

[Service]
User=node_exporter
# Fallback when environment file does not exist
Environment=OPTIONS=
EnvironmentFile=-/etc/sysconfig/node_exporter
ExecStart=/usr/sbin/node_exporter --web.systemd-socket $OPTIONS

[Install]
WantedBy=multi-user.target
EOF'

    echo "创建 node_exporter 的 systemd socket 文件..."
    sudo bash -c 'cat <<EOF > /etc/systemd/system/node_exporter.socket
[Unit]
Description=Node Exporter

[Socket]
ListenStream=9100

[Install]
WantedBy=sockets.target
EOF'

    case $OS in
    ubuntu|debian)
        echo "OPTIONS=\"--collector.textfile.directory /var/lib/node_exporter/textfile_collector\"" | sudo tee /etc/default/node_exporter
        ;;
    centos|rocky|almalinux|fedora|suse|opensuse)
        echo "OPTIONS=\"--collector.textfile.directory /var/lib/node_exporter/textfile_collector\"" | sudo tee /etc/sysconfig/node_exporter
        ;;
    esac

    echo "创建文本文件收集器目录..."
    sudo mkdir -p /var/lib/node_exporter/textfile_collector
    sudo chown -R node_exporter:node_exporter /var/lib/node_exporter
}

# 启动和启用服务
start_and_enable_service() {
    sudo systemctl daemon-reload
    if ! sudo systemctl enable --now node_exporter; then
        echo "无法启动或启用 node_exporter 服务。"
        exit 1
    fi
    sudo systemctl status --no-pager node_exporter 
}

# 主程序
main() {
    check_os
    echo "检测到操作系统: $OS $VERSION_ID"

    while true; do
        echo "请选择操作:"
        echo "1) 安装 Node Exporter"
        echo "2) 卸载 Node Exporter"
        echo "3) 退出"
        read -rp "请输入选项 (1/2/3): " choice

        case $choice in
            1)
                check_service_path
                install_dependencies
                cleanup_old_node_exporter
                download_and_extract_node_exporter
                create_node_exporter_user
                configure_systemd_service
                start_and_enable_service
                echo "Node Exporter 安装完成！"
                ;;
            2)
                cleanup_old_node_exporter
                echo "Node Exporter 已卸载。"
                ;;
            3)
                echo "退出程序。"
                exit 0
                ;;
            *)
                echo "无效选项，请重新选择。"
                ;;
        esac
    done
}

main
