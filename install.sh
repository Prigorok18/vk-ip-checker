#!/bin/bash
# 🚀 VK IP Checker Docker Installer
# Установка: curl -fsSL https://raw.githubusercontent.com/Prigorok18/vk-ip-checker/main/install.sh | sudo bash

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Пути
INSTALL_DIR="/opt/vk-ip-checker"
BIN_PATH="/usr/local/bin/vk-ip-checker"
ENV_FILE="$INSTALL_DIR/.env"
GOOD_IPS_FILE="$INSTALL_DIR/good_ips.txt"
LOG_DIR="$INSTALL_DIR/logs"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${GREEN}         VK Cloud IP Checker Docker Installer          ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Этот скрипт должен запускаться от root!${NC}"
    echo -e "${YELLOW}Используйте: sudo bash install.sh${NC}"
    exit 1
fi

# Проверка Docker
echo -e "${BLUE}🔍 Проверка Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker не установлен!${NC}"
    echo -e "${YELLOW}Установите Docker:${NC}"
    echo -e "  ${CYAN}sudo pacman -S docker docker-compose${NC}"
    echo -e "  ${CYAN}sudo systemctl enable --now docker${NC}"
    echo -e "  ${CYAN}sudo usermod -aG docker $SUDO_USER${NC}"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker Compose не найден, устанавливаем...${NC}"
    sudo pacman -S docker-compose --noconfirm
fi
echo -e "${GREEN}✅ Docker и Docker Compose готовы${NC}"

# Создание директорий
echo ""
echo -e "${BLUE}📁 Создание директорий...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
echo -e "${GREEN}✅ Директории созданы: $INSTALL_DIR${NC}"

# Создание Dockerfile
echo -e "${BLUE}📝 Создание Dockerfile...${NC}"
cat > "$INSTALL_DIR/Dockerfile" << 'DOCKERFILE'
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir requests python-dotenv

COPY checker.py .

RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

CMD ["python", "checker.py"]
DOCKERFILE

# Создание docker-compose.yml
echo -e "${BLUE}📝 Создание docker-compose.yml...${NC}"
cat > "$INSTALL_DIR/docker-compose.yml" << 'DOCKERCOMPOSE'
version: '3.8'

services:
  vk-checker:
    build: .
    container_name: vk-ip-checker
    env_file:
      - .env
    environment:
      - TARGET_GOOD_IPS=${TARGET_GOOD_IPS:-1}
      - GOOD_IPS_FILE=/app/data/good_ips.txt
    volumes:
      - ./good_ips.txt:/app/data/good_ips.txt
      - ./logs:/app/logs
      - ./whitelist.txt:/app/whitelist.txt
      - ./cidr.txt:/app/cidr.txt
    restart: "no"
DOCKERCOMPOSE

# Создание checker.py
echo -e "${BLUE}📝 Создание checker.py...${NC}"
cat > "$INSTALL_DIR/checker.py" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
VK Cloud IP Whitelist Checker (Docker version)
"""

import os
import sys
import time
import logging
import ipaddress
import requests
from datetime import datetime

# Пути внутри контейнера
GOOD_IPS_FILE = os.getenv("GOOD_IPS_FILE", "/app/data/good_ips.txt")
WHITELIST_FILE = "/app/whitelist.txt"
CIDR_FILE = "/app/cidr.txt"
LOG_DIR = "/app/logs"

# Настройка логирования
os.makedirs(LOG_DIR, exist_ok=True)
LOG_FILE = os.path.join(LOG_DIR, f"checker_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Конфигурация из переменных окружения
VK_API_TOKEN = os.getenv("VK_API_TOKEN", "")
PROJECT_ID = os.getenv("PROJECT_ID", "")
SERVER_NAME = os.getenv("SERVER_NAME", "vk-ip-checker")
FLAVOR_REF = os.getenv("FLAVOR_REF", "BASIC-1-2-20")
IMAGE_REF = os.getenv("IMAGE_REF", "ubuntu-22-04")
NETWORK_UUID = os.getenv("NETWORK_UUID", "public")
NOVA_API_URL = os.getenv("NOVA_API_URL", "https://infra.mail.ru:8774/v2.1")
IP_WAIT_TIMEOUT = int(os.getenv("IP_WAIT_TIMEOUT", "120"))
TARGET_GOOD_IPS = int(os.getenv("TARGET_GOOD_IPS", "1"))

WHITELIST_IP_URL = "https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/ipwhitelist.txt"
WHITELIST_CIDR_URL = "https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt"

found_good_ips = 0


def update_whitelists():
    """Обновляет локальные белые списки."""
    logger.info("📥 Обновление белых списков...")
    
    try:
        resp = requests.get(WHITELIST_IP_URL, timeout=30)
        resp.raise_for_status()
        with open(WHITELIST_FILE, 'w') as f:
            f.write(resp.text)
        
        resp = requests.get(WHITELIST_CIDR_URL, timeout=30)
        resp.raise_for_status()
        with open(CIDR_FILE, 'w') as f:
            f.write(resp.text)
        
        logger.info("✅ Списки обновлены")
        return True
    except Exception as e:
        logger.error(f"❌ Ошибка: {e}")
        return False


def load_whitelists():
    """Загружает белые списки."""
    ips = []
    cidrs = []
    
    if os.path.exists(WHITELIST_FILE):
        with open(WHITELIST_FILE, 'r') as f:
            ips = [line.strip() for line in f if line.strip() and not line.startswith('#')]
    
    if os.path.exists(CIDR_FILE):
        with open(CIDR_FILE, 'r') as f:
            cidrs = [line.strip() for line in f if line.strip() and not line.startswith('#')]
    
    return ips, cidrs


def is_ip_whitelisted(ip, ips, cidrs):
    """Проверяет IP."""
    try:
        ip_obj = ipaddress.ip_address(ip)
    except ValueError:
        return False
    
    if ip in ips:
        return True
    
    for cidr in cidrs:
        try:
            network = ipaddress.ip_network(cidr, strict=False)
            if ip_obj in network:
                return True
        except ValueError:
            continue
    
    return False


def create_server():
    """Создает сервер."""
    headers = {
        'X-Auth-Token': VK_API_TOKEN,
        'Content-Type': 'application/json'
    }
    
    timestamp = int(time.time())
    payload = {
        "server": {
            "name": f"{SERVER_NAME}-{timestamp}",
            "flavorRef": FLAVOR_REF,
            "imageRef": IMAGE_REF,
            "networks": [{"uuid": NETWORK_UUID}],
            "adminPass": "TempPass123!@#"
        }
    }
    
    try:
        response = requests.post(
            f"{NOVA_API_URL}/{PROJECT_ID}/servers",
            headers=headers,
            json=payload,
            timeout=60
        )
        
        if response.status_code == 202:
            server_data = response.json().get('server')
            server_id = server_data.get('id')
            logger.info(f"✅ Сервер создан. ID: {server_id}")
            return server_id
        else:
            logger.error(f"❌ Ошибка: {response.status_code}")
            return None
    except Exception as e:
        logger.error(f"❌ Ошибка: {e}")
        return None


def wait_for_ip(server_id):
    """Ожидает IP."""
    headers = {'X-Auth-Token': VK_API_TOKEN}
    start_time = time.time()
    
    logger.info(f"⏳ Ожидание IP (макс {IP_WAIT_TIMEOUT} сек)...")
    
    while time.time() - start_time < IP_WAIT_TIMEOUT:
        try:
            response = requests.get(
                f"{NOVA_API_URL}/{PROJECT_ID}/servers/{server_id}",
                headers=headers,
                timeout=30
            )
            
            if response.status_code == 200:
                server_info = response.json().get('server', {})
                addresses = server_info.get('addresses', {})
                
                for network_name, network_ips in addresses.items():
                    for ip_info in network_ips:
                        addr = ip_info.get('addr', '')
                        if addr and '.' in addr:
                            logger.info(f"🌐 Получен IP: {addr}")
                            return addr
            time.sleep(5)
        except Exception as e:
            logger.warning(f"Ошибка: {e}")
            time.sleep(5)
    
    return None


def delete_server(server_id):
    """Удаляет сервер."""
    headers = {'X-Auth-Token': VK_API_TOKEN}
    
    try:
        response = requests.delete(
            f"{NOVA_API_URL}/{PROJECT_ID}/servers/{server_id}",
            headers=headers,
            timeout=30
        )
        
        if response.status_code == 204:
            logger.info(f"🗑️ Сервер {server_id} удален")
            return True
        else:
            logger.error(f"Ошибка удаления: {response.status_code}")
            return False
    except Exception as e:
        logger.error(f"Ошибка: {e}")
        return False


def save_good_ip(ip):
    """Сохраняет хороший IP."""
    global found_good_ips
    
    if os.path.exists(GOOD_IPS_FILE):
        with open(GOOD_IPS_FILE, 'r') as f:
            existing = [line.strip() for line in f]
            if ip in existing:
                return
    
    with open(GOOD_IPS_FILE, 'a') as f:
        f.write(f"{ip}\n")
    
    found_good_ips += 1
    logger.info(f"💾 IP {ip} сохранен ({found_good_ips}/{TARGET_GOOD_IPS})")


def load_good_ips():
    """Загружает найденные IP."""
    global found_good_ips
    
    if os.path.exists(GOOD_IPS_FILE):
        with open(GOOD_IPS_FILE, 'r') as f:
            ips = [line.strip() for line in f if line.strip()]
            found_good_ips = len(ips)
            return found_good_ips
    return 0


def run_check():
    """Основной цикл."""
    global found_good_ips
    
    load_good_ips()
    
    if TARGET_GOOD_IPS > 0 and found_good_ips >= TARGET_GOOD_IPS:
        logger.info(f"✅ Цель достигнута! Найдено {found_good_ips} IP")
        return True
    
    if not update_whitelists():
        return False
    
    ips, cidrs = load_whitelists()
    logger.info(f"Загружено: {len(ips)} IP, {len(cidrs)} CIDR")
    
    iteration = 1
    while True:
        if TARGET_GOOD_IPS > 0 and found_good_ips >= TARGET_GOOD_IPS:
            logger.info(f"🎉 Достигнута цель! Найдено {found_good_ips} IP")
            break
        
        logger.info(f"\n🔄 Итерация {iteration}")
        
        server_id = create_server()
        if not server_id:
            time.sleep(10)
            continue
        
        ip = wait_for_ip(server_id)
        if not ip:
            delete_server(server_id)
            time.sleep(5)
            continue
        
        if is_ip_whitelisted(ip, ips, cidrs):
            logger.info(f"✅✅✅ IP {ip} ВХОДИТ в белый список!")
            save_good_ip(ip)
        else:
            logger.warning(f"❌ IP {ip} НЕ входит в белый список")
            delete_server(server_id)
        
        iteration += 1
        time.sleep(3)
    
    logger.info(f"📊 Итог: найдено {found_good_ips} хороших IP")
    return True


if __name__ == "__main__":
    run_check()
PYTHON_SCRIPT

chmod +x "$INSTALL_DIR/checker.py"

# Создание .env.example
echo -e "${BLUE}📝 Создание .env.example...${NC}"
cat > "$INSTALL_DIR/.env.example" << 'ENV_EXAMPLE'
# VK Cloud API настройки
VK_API_TOKEN=ваш_токен_здесь
PROJECT_ID=ваш_project_id_здесь

# Параметры сервера
SERVER_NAME=vk-ip-checker
FLAVOR_REF=BASIC-1-2-20
IMAGE_REF=ubuntu-22-04
NETWORK_UUID=public

# API endpoint
NOVA_API_URL=https://infra.mail.ru:8774/v2.1

# Настройки
IP_WAIT_TIMEOUT=120
ENV_EXAMPLE

# Создание главного скрипта
echo -e "${BLUE}🔧 Создание главного скрипта...${NC}"

cat > "$BIN_PATH" << 'MAIN_SCRIPT'
#!/bin/bash
# 🚀 VK IP Checker CLI (Docker version)

INSTALL_DIR="/opt/vk-ip-checker"
ENV_FILE="$INSTALL_DIR/.env"
GOOD_IPS_FILE="$INSTALL_DIR/good_ips.txt"
LOG_DIR="$INSTALL_DIR/logs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Требуются root права!${NC}"
        echo -e "${YELLOW}Используйте: sudo vk-ip-checker${NC}"
        exit 1
    fi
}

check_config() {
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}❌ Файл конфигурации не найден!${NC}"
        echo -e "${YELLOW}Запустите: sudo vk-ip-checker --config${NC}"
        return 1
    fi
    
    source "$ENV_FILE"
    if [ -z "$VK_API_TOKEN" ] || [ "$VK_API_TOKEN" = "ваш_токен_здесь" ]; then
        echo -e "${RED}❌ VK_API_TOKEN не заполнен!${NC}"
        return 1
    fi
    
    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "ваш_project_id_здесь" ]; then
        echo -e "${RED}❌ PROJECT_ID не заполнен!${NC}"
        return 1
    fi
    
    return 0
}

configure() {
    echo -e "${CYAN}⚙️  Настройка VK IP Checker${NC}"
    echo ""
    
    if [ ! -f "$ENV_FILE" ]; then
        cp "$INSTALL_DIR/.env.example" "$ENV_FILE"
    fi
    
    source "$ENV_FILE" 2>/dev/null || true
    
    read -p "VK API Token [${VK_API_TOKEN:-не задан}]: " input_token
    read -p "Project ID [${PROJECT_ID:-не задан}]: " input_project
    read -p "Flavor [${FLAVOR_REF:-BASIC-1-2-20}]: " input_flavor
    read -p "Образ ОС [${IMAGE_REF:-ubuntu-22-04}]: " input_image
    
    [ -n "$input_token" ] && sed -i "s/^VK_API_TOKEN=.*/VK_API_TOKEN=$input_token/" "$ENV_FILE"
    [ -n "$input_project" ] && sed -i "s/^PROJECT_ID=.*/PROJECT_ID=$input_project/" "$ENV_FILE"
    [ -n "$input_flavor" ] && sed -i "s/^FLAVOR_REF=.*/FLAVOR_REF=$input_flavor/" "$ENV_FILE"
    [ -n "$input_image" ] && sed -i "s/^IMAGE_REF=.*/IMAGE_REF=$input_image/" "$ENV_FILE"
    
    echo -e "${GREEN}✅ Конфигурация сохранена!${NC}"
}

show_status() {
    echo -e "${CYAN}📊 Статус VK IP Checker${NC}"
    echo ""
    
    if [ -f "$GOOD_IPS_FILE" ] && [ -s "$GOOD_IPS_FILE" ]; then
        COUNT=$(wc -l < "$GOOD_IPS_FILE")
        echo -e "  ${GREEN}Найдено хороших IP: ${YELLOW}$COUNT${NC}"
        echo ""
        echo -e "  ${BLUE}Список IP:${NC}"
        cat -n "$GOOD_IPS_FILE"
    else
        echo -e "  ${YELLOW}Хорошие IP пока не найдены${NC}"
    fi
}

show_list() {
    if [ -f "$GOOD_IPS_FILE" ] && [ -s "$GOOD_IPS_FILE" ]; then
        echo -e "${GREEN}📋 Найденные IP:${NC}"
        echo "────────────────────────────────────────"
        cat -n "$GOOD_IPS_FILE"
        echo "────────────────────────────────────────"
    else
        echo -e "${YELLOW}Нет сохраненных IP${NC}"
    fi
}

clean_list() {
    echo -e "${RED}⚠️  Очистить список? (y/N)${NC}"
    read -r confirm
    if [ "$confirm" = "y" ]; then
        rm -f "$GOOD_IPS_FILE"
        echo -e "${GREEN}✅ Список очищен${NC}"
    fi
}

run_search() {
    local target=$1
    
    if ! check_config; then
        return 1
    fi
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    if [ "$target" -eq 0 ]; then
        echo -e "${GREEN}♾️  Бесконечный поиск...${NC}"
    else
        echo -e "${GREEN}🎯 Поиск $target IP...${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    
    cd "$INSTALL_DIR"
    TARGET_GOOD_IPS=$target docker compose up --abort-on-container-exit
    
    show_status
}

uninstall() {
    echo -e "${RED}⚠️  Удалить VK IP Checker? (y/N)${NC}"
    read -r confirm
    if [ "$confirm" = "y" ]; then
        cd "$INSTALL_DIR" && docker compose down 2>/dev/null
        rm -rf "$INSTALL_DIR"
        rm -f "$BIN_PATH"
        echo -e "${GREEN}✅ Удалено${NC}"
    fi
}

view_logs() {
    if [ -d "$LOG_DIR" ]; then
        echo -e "${CYAN}📋 Последние логи:${NC}"
        tail -50 "$LOG_DIR"/checker_*.log 2>/dev/null || echo "Логов нет"
    fi
}

update_lists() {
    echo -e "${BLUE}🔄 Обновление списков...${NC}"
    cd "$INSTALL_DIR"
    docker compose run --rm vk-checker python -c "
import requests
url_ip = 'https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/ipwhitelist.txt'
url_cidr = 'https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt'
try:
    r = requests.get(url_ip, timeout=30)
    with open('whitelist.txt', 'w') as f: f.write(r.text)
    r = requests.get(url_cidr, timeout=30)
    with open('cidr.txt', 'w') as f: f.write(r.text)
    print('✅ Списки обновлены')
except Exception as e:
    print(f'❌ Ошибка: {e}')
"
    echo -e "${GREEN}✅ Готово!${NC}"
}

show_menu() {
    while true; do
        clear
        COUNT=0
        [ -f "$GOOD_IPS_FILE" ] && COUNT=$(wc -l < "$GOOD_IPS_FILE" 2>/dev/null)
        
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}         VK Cloud IP Checker v1.0 (Docker)             ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${GREEN}📊 Найдено: ${YELLOW}$COUNT${NC}"
        echo ""
        echo -e "${CYAN}┌────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│${GREEN} 1${NC}) 🔍 Найти 1 IP                                   ${CYAN}│${NC}"
        echo -e "${CYAN}│${GREEN} 2${NC}) 🔍 Найти 3 IP                                  ${CYAN}│${NC}"
        echo -e "${CYAN}│${GREEN} 3${NC}) 🔍 Найти 5 IP                                  ${CYAN}│${NC}"
        echo -e "${CYAN}│${GREEN} 4${NC}) 🔍 Найти 10 IP                                 ${CYAN}│${NC}"
        echo -e "${CYAN}│${GREEN} 5${NC}) ♾️  Бесконечный поиск                           ${CYAN}│${NC}"
        echo -e "${CYAN}│${GREEN} 6${NC}) 🎲 Своё количество                             ${CYAN}│${NC}"
        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${MAGENTA} 7${NC}) 📋 Показать найденные IP                       ${CYAN}│${NC}"
        echo -e "${CYAN}│${MAGENTA} 8${NC}) 🗑️  Очистить список                           ${CYAN}│${NC}"
        echo -e "${CYAN}│${MAGENTA} 9${NC}) 🔄 Обновить белые списки                      ${CYAN}│${NC}"
        echo -e "${CYAN}│${MAGENTA}10${NC}) 📜 Показать логи                              ${CYAN}│${NC}"
        echo -e "${CYAN}│${MAGENTA}11${NC}) ⚙️  Настройки                                 ${CYAN}│${NC}"
        echo -e "${CYAN}├────────────────────────────────────────────────────────┤${NC}"
        echo -e "${CYAN}│${RED}12${NC}) 🗑️  Удалить программу                           ${CYAN}│${NC}"
        echo -e "${CYAN}│${RED} 0${NC}) 🚪 Выход                                         ${CYAN}│${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────────────┘${NC}"
        echo ""
        read -p "Выберите пункт (0-12): " choice
        
        case $choice in
            1) check_root && run_search 1 ; read -p "Нажмите Enter..." ;;
            2) check_root && run_search 3 ; read -p "Нажмите Enter..." ;;
            3) check_root && run_search 5 ; read -p "Нажмите Enter..." ;;
            4) check_root && run_search 10 ; read -p "Нажмите Enter..." ;;
            5) check_root && run_search 0 ; read -p "Нажмите Enter..." ;;
            6)
                read -p "Введите количество (0=бесконечно): " custom
                [[ "$custom" =~ ^[0-9]+$ ]] && check_root && run_search "$custom"
                read -p "Нажмите Enter..."
                ;;
            7) show_list ; read -p "Нажмите Enter..." ;;
            8) clean_list ; read -p "Нажмите Enter..." ;;
            9) update_lists ; read -p "Нажмите Enter..." ;;
            10) view_logs ; read -p "Нажмите Enter..." ;;
            11) configure ; read -p "Нажмите Enter..." ;;
            12) uninstall && exit 0 ;;
            0) echo -e "${GREEN}До свидания!${NC}" ; exit 0 ;;
        esac
    done
}

case "${1:-}" in
    --config|-c) check_root && configure ;;
    --status|-s) show_status ;;
    --list|-l) show_list ;;
    --clean) clean_list ;;
    --update|-u) update_lists ;;
    --logs) view_logs ;;
    --uninstall) check_root && uninstall ;;
    [0-9]*) check_root && run_search "$1" ;;
    "") show_menu ;;
    *) echo -e "${RED}Неизвестная опция: $1${NC}" ; exit 1 ;;
esac
MAIN_SCRIPT

chmod +x "$BIN_PATH"

# Первая сборка образа
echo ""
echo -e "${BLUE}🐳 Сборка Docker образа...${NC}"
cd "$INSTALL_DIR"
docker compose build

echo ""
echo -e "${GREEN}✅ Установка завершена!${NC}"
echo ""
echo -e "${BLUE}📝 Настройка:${NC}"
echo -e "  ${YELLOW}sudo vk-ip-checker --config${NC}"
echo ""
echo -e "${BLUE}🚀 Запуск:${NC}"
echo -e "  ${YELLOW}vk-ip-checker${NC}          # Открыть меню"
echo -e "  ${YELLOW}vk-ip-checker 5${NC}        # Найти 5 IP"
echo ""

read -p "Хотите настроить программу сейчас? (y/N): " setup_now
if [ "$setup_now" = "y" ] || [ "$setup_now" = "yes" ]; then
    $BIN_PATH --config
fi
EOF

chmod +x install.sh

echo ""
echo -e "${GREEN}✅ Все файлы созданы!${NC}"
echo ""
echo -e "${BLUE}Запустите установку:${NC}"
echo -e "  ${YELLOW}sudo bash install.sh${NC}"
