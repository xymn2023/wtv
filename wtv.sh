#!/bin/bash

# 配置变量
APP_NAME="wtv-online"
INSTALL_DIR="/home/wtv-online-app"
SERVICE_FILE="/etc/systemd/system/wtv.service"
GITHUB_URL="https://github.com/biancangming/wtv-online/releases/download/1.2"
GO_VERSION="1.21.5" # 稳定的 Go 版本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 必须以 root 权限运行此脚本！${NC}"
   exit 1
fi

# 1. Go 环境检测与安装函数
check_go_env() {
    echo -e "${YELLOW}正在检测 Go 环境...${NC}"
    if command -v go >/dev/null 2>&1; then
        echo -e "${GREEN}检测到 Go 已安装: $(go version)${NC}"
    else
        echo -e "${YELLOW}未检测到 Go，准备自动安装 Go ${GO_VERSION}...${NC}"
        ARCH=$(uname -m)
        case $ARCH in
            x86_64) GO_ARCH="amd64" ;;
            aarch64) GO_ARCH="arm64" ;;
            *) echo -e "${RED}不支持的架构无法自动安装 Go，请手动安装。${NC}"; return 1 ;;
        esac

        wget -q --show-progress https://golang.google.cn/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz
        rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VERSION}.linux-${GO_ARCH}.tar.gz
        rm -f go${GO_VERSION}.linux-${GO_ARCH}.tar.gz

        # 写入环境变量
        if ! grep -q "/usr/local/go/bin" /etc/profile; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
            echo 'export GOPATH=$HOME/go' >> /etc/profile
            echo 'export PATH=$PATH:$GOPATH/bin' >> /etc/profile
        fi
        source /etc/profile
        
        # 立即在当前 shell 生效
        export PATH=$PATH:/usr/local/go/bin
        echo -e "${GREEN}Go 安装成功！版本: $(go version)${NC}"
    fi
}

# 2. 安装 wtv-online 函数
install_wtv() {
    check_go_env
    
    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  FILE="wtv-online_linux_amd64" ;;
        aarch64) FILE="wtv-online_linux_arm64" ;;
        i386|i686) FILE="wtv-online_linux_386" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
    esac

    echo -e "${YELLOW}正在从 GitHub 下载 $FILE...${NC}"
    wget -q --show-progress $GITHUB_URL/$FILE -O $APP_NAME
    chmod +x $APP_NAME

    # 初始化 app.ini
    if [ ! -f "app.ini" ]; then
        echo -e "${YELLOW}正在初始化默认配置文件...${NC}"
        cat <<EOF > app.ini
[user]
username = admin
password = admin123
[config]
title = 我的托管站
description = 在线托管 m3u8 等文本
EOF
    fi

    # 创建 Systemd 服务
    echo -e "${YELLOW}正在配置 Systemd 服务...${NC}"
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=WTV Online Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$APP_NAME
Restart=on-failure
Environment=GIN_MODE=release

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wtv
    echo -e "${GREEN}安装完成！程序目录: $INSTALL_DIR${NC}"
}

# 3. 菜单逻辑
show_menu() {
    echo -e "${YELLOW}=== WTV-Online 一键管理脚本 (含Go环境检测) ===${NC}"
    echo "1. 安装/更新 WTV-Online (含环境检测)"
    echo "2. 启动服务"
    echo "3. 停止服务"
    echo "4. 重启服务"
    echo "5. 查看运行状态与访问信息"
    echo "6. 修改 app.ini 配置"
    echo "7. 卸载程序"
    echo "0. 退出"
    echo -ne "${GREEN}请选择 [0-7]: ${NC}"
}

while true; do
    show_menu
    read choice
    case $choice in
        1) install_wtv ;;
        2) systemctl start wtv && echo -e "${GREEN}服务已启动！${NC}" ;;
        3) systemctl stop wtv && echo -e "${YELLOW}服务已停止。${NC}" ;;
        4) systemctl restart wtv && echo -e "${GREEN}服务已重启！${NC}" ;;
        5) 
            systemctl status wtv --no-pager
            IP=$(curl -s ifconfig.me)
            echo -e "\n${GREEN}--- 访问信息 ---${NC}"
            echo -e "访问地址: http://${IP}:1999"
            echo -e "配置文件: $INSTALL_DIR/app.ini"
            ;;
        6) nano $INSTALL_DIR/app.ini && systemctl restart wtv ;;
        7) 
            systemctl stop wtv
            systemctl disable wtv
            rm -f $SERVICE_FILE
            echo -e "${RED}程序已停止并移除服务，目录 $INSTALL_DIR 保留（可手动rm）。${NC}"
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项！${NC}" ;;
    esac
    echo ""
done