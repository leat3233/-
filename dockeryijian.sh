#!/bin/bash
set -e # 遇到致命错误立即退出 (但对非致命更新错误进行了容错处理)

# 颜色定义
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

echo -e "${GREEN}🚀 启动 Docker 终极安装与自修复脚本 (最终版)...${RESET}"

# --- 步骤 1: 系统信息检测与变量定义 ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    VERSION_ID=$VERSION_ID
    CODENAME=$VERSION_CODENAME
else
    echo -e "${RED}❌ 无法检测系统版本。${RESET}"
    exit 1
fi

echo -e "${YELLOW}ℹ️ 系统信息: $OS $VERSION_ID ($CODENAME)${RESET}"

# 核心函数：Debian/Ubuntu 源修复
fix_debian_sources() {
    echo -e "${YELLOW}⚠️ 正在检查并修复 Debian/Ubuntu APT 源配置...${RESET}"
    
    # 1. 备份当前 sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.bak_pre_fix_$(date +%s) || true
    
    # 2. 清理可能导致错误的旧 Docker 源文件和 EOL 配置文件
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/apt.conf.d/99no-check-valid-until
    
    # 3. 针对不同版本进行源配置
    if [[ "$OS" == "debian" ]]; then
        # 统一处理 EOL 和支持版本，确保核心源正确
        echo -e "${GREEN}✅ 设置 Debian 核心源...${RESET}"
        
        # 写入核心源 (Main/Security)
        cat > /etc/apt/sources.list <<EOF
# Core Main Repository
deb http://deb.debian.org/debian/ $CODENAME main contrib non-free
# Security Updates
deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free
EOF

        # 如果是 EOL 版本，额外添加归档配置
        if [[ "$VERSION_ID" == "8" || "$VERSION_ID" == "9" || "$VERSION_ID" == "10" ]]; then
            echo -e "${YELLOW}🚨 检测到 Debian EOL 版本，添加 Archive 源和忽略检查...${RESET}"
            echo "deb http://archive.debian.org/debian/ $CODENAME main contrib non-free" >> /etc/apt/sources.list
            echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
        fi

        # 尝试添加 Backports (在 /etc/apt/sources.list.d/ 中独立处理，便于失败时删除)
        echo -e "${YELLOW}🌐 尝试添加 Backports 源...${RESET}"
        echo "deb http://deb.debian.org/debian/ $CODENAME-backports main contrib non-free" | sudo tee /etc/apt/sources.list.d/backports.list > /dev/null

    elif [[ "$OS" == "ubuntu" ]]; then
        # Ubuntu 使用默认配置
        echo -e "${GREEN}✅ Ubuntu 使用默认 sources.list 配置。${RESET}"
    fi
    
    # 4. 执行更新并允许 Release Info 变化 (解决校验问题)
    echo -e "${GREEN}🔄 正在更新源，并处理 Backports 错误...${RESET}"
    
    # **关键容错处理：** 允许 apt update 因 Backports 等非致命错误而返回非零退出码
    if ! apt-get update --allow-releaseinfo-change; then
        echo -e "${YELLOW}⚠️ 警告：apt update 返回错误。正在检查是否是 Backports 导致的...${RESET}"
        
        # 如果更新失败，检查日志中是否包含 'backports' 的错误信息
        if apt-get update 2>&1 | grep -q 'backports'; then
            echo -e "${RED}❌ Backports 源导致更新失败。已删除 /etc/apt/sources.list.d/backports.list 文件。${RESET}"
            rm -f /etc/apt/sources.list.d/backports.list
            # 重新尝试更新，这次必须成功
            if ! apt-get update --allow-releaseinfo-change; then
                 echo -e "${RED}❌ 核心源更新失败，脚本中止。请检查网络。${RESET}"
                 exit 1
            fi
        else
            echo -e "${RED}❌ 核心源更新失败，脚本中止。请检查网络或源地址。${RESET}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✅ 源更新成功。${RESET}"
}

# 核心函数：CentOS/RHEL 源修复
fix_centos_sources() {
    echo -e "${YELLOW}⚠️ 正在检查并修复 CentOS/RHEL 源配置...${RESET}"
    if [ "$VERSION_ID" == "7" ] || [ "$VERSION_ID" == "8" ]; then
        echo -e "${YELLOW}🚨 检测到 CentOS ${VERSION_ID}，切换到 Vault 归档源...${RESET}"
        # 修复 CentOS 7/8 EOL 后的 Vault 源
        sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*.repo
        sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo
        yum clean all
        yum makecache
    fi
}

# --- 步骤 2: 执行源修复 ---
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    fix_debian_sources
elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
    fix_centos_sources
fi


# --- 步骤 3: 安装先决条件与 Docker 官方源 ---
echo -e "${GREEN}📦 正在安装先决条件并配置 Docker 官方源...${RESET}"
if command -v apt-get &> /dev/null; then
    # Debian/Ubuntu
    apt-get -y install ca-certificates curl gnupg lsb-release
    
    # 添加 Docker 官方 GPG Key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # 添加 Docker 官方稳定源
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 最终更新
    apt-get update
    
elif command -v yum &> /dev/null; then
    # CentOS/RHEL
    yum install -y yum-utils device-mapper-persistent-data lvm2 ca-certificates curl gnupg
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache
fi


# --- 步骤 4: 核心安装 ---
echo -e "${GREEN}⚙️ 正在安装核心 Docker 组件...${RESET}"
if command -v apt-get &> /dev/null; then
    apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
elif command -v yum &> /dev/null; then
    yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi


# --- 步骤 5: 配置国内镜像加速器 ---
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

# --- 步骤 6: 启动服务与授权 ---
echo -e "${GREEN}🔄 正在启动服务并设置权限...${RESET}"
systemctl daemon-reload
systemctl enable --now docker
systemctl restart docker

# 设置免 sudo 权限
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    usermod -aG docker $SUDO_USER 2>/dev/null || true
    USER_MSG="⚠️  非 Root 用户请执行 'newgrp docker' 或重连 SSH 生效。"
else
    USER_MSG=""
fi

echo -e "\n${GREEN}✅✅✅ Docker 终极安装与修复完成！${RESET}"
# 验证安装
if docker run hello-world &> /dev/null; then
    echo -e "${GREEN}✅ Docker 环境验证成功！版本：$(docker --version)${RESET}"
else
    echo -e "${RED}❌ Docker 验证失败，请手动检查。${RESET}"
fi

echo -e "${YELLOW}${USER_MSG}${RESET}"
