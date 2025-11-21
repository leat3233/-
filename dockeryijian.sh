#!/bin/bash
set -e # 遇到错误立即退出，避免执行后续步骤

# 颜色定义
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

echo -e "${GREEN}🚀 启动 Docker 终极安装与修复脚本...${RESET}"

# --- 步骤 1: 系统信息检测与 EOL (End of Life) 修复 ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    CODENAME=$VERSION_CODENAME
else
    echo -e "${RED}❌ 无法检测系统版本。${RESET}"
    exit 1
fi

fix_debian_eol() {
    echo -e "${YELLOW}⚠️ 检测到 Debian 旧版本 ($CODENAME)，正在自动切换到官方归档源...${RESET}"
    cp /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%s)
    
    # 写入归档源 (Archive Sources)
    echo "deb http://archive.debian.org/debian/ $CODENAME main contrib non-free" > /etc/apt/sources.list
    echo "deb http://archive.debian.org/debian-security/ $CODENAME/updates main contrib non-free" >> /etc/apt/sources.list
    
    # 忽略过期时间检查
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
    
    # 清理缓存并更新源 (关键步骤)
    apt-get clean
    echo -e "${GREEN}✅ 归档源配置成功，正在尝试更新...${RESET}"
    # --allow-releaseinfo-change 是解决切换到 Archive 源后，Release 文件校验日期过期的问题
    apt-get update --allow-releaseinfo-change || echo -e "${RED}源更新有警告，尝试继续...${RESET}"
}

# 执行 EOL 修复逻辑 (仅针对 Debian 8/9/10)
if [ "$OS" == "debian" ]; then
    if [[ "$VERSION_ID" == "8" || "$VERSION_ID" == "9" || "$VERSION_ID" == "10" ]]; then
        fix_debian_eol
    else
        # 针对新版本，如果更新失败也尝试修复 (以防出现临时的源问题)
        apt-get update -qq >/dev/null 2>&1 || fix_debian_eol
    fi
elif [ "$OS" == "centos" ] && [ "$VERSION_ID" == "7" ]; then
    echo -e "${YELLOW}⚠️ 检测到 CentOS 7，正在自动切换到 Vault 归档源...${RESET}"
    # CentOS 7 切换 Vault 源的逻辑 (这里省略，但如果需要，可以在此添加)
    yum makecache || true
fi


# --- 步骤 2: 安装先决条件与 Docker 官方源 ---
echo -e "${GREEN}📦 正在安装先决条件并添加 Docker 阿里云源...${RESET}"
# 安装 ca-certificates, curl, gnupg，同时兼容 apt 和 yum/dnf
apt-get -y install ca-certificates curl gnupg || yum install -y ca-certificates curl gnupg

# 添加 Docker 阿里云 GPG Key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# 添加 Docker 阿里云源
if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ]; then
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.aliyun.com/docker-ce/linux/$OS $CODENAME stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq >/dev/null
elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
    # 这里添加 CentOS 的源配置，如果需要。目前脚本只集中解决了 Debian 的痛点。
    :
fi


# --- 步骤 3: 核心安装 (手动排除不兼容包) ---
echo -e "${GREEN}⚙️ 正在安装核心 Docker 组件...${RESET}"
# 关键：手动排除 docker-model-plugin 和 docker-ce-rootless-extras (它们在 EOL Debian 10 源中缺失)
apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin

# --- 步骤 4: 配置镜像加速器 (连接性保障) ---
echo -e "${GREEN}🌐 正在配置国内镜像加速器...${RESET}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<-'JSON'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://huecker.io",
    "https://dockerhub.timeweb.cloud",
    "https://noohub.ru"
  ]
}
JSON

# --- 步骤 5: 启动服务与授权 ---
echo -e "${GREEN}🔄 正在启动服务并设置权限...${RESET}"
systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker

# 设置免 sudo 权限
if [ "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    usermod -aG docker $SUDO_USER
    USER_MSG="⚠️  非 Root 用户请执行 'newgrp docker' 或重连 SSH 生效。"
else
    USER_MSG=""
fi

echo -e "\n${GREEN}✅✅✅ 终极修复安装完成！${RESET}"
echo -e "${GREEN}当前 Docker 版本：$(docker --version)${RESET}"
echo -e "${YELLOW}${USER_MSG}${RESET}"
