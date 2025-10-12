#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# MDKenZnhoTT - Auto Rejoin Tool v3.2 (root)
# Tự tạo file conf, API Roblox thật, giao diện chuẩn
# ============================================

# ====== PATH & FILES ======
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$SCRIPT_DIR/KenZnhoTT.conf"
LOGFILE="$SCRIPT_DIR/roblox_rejoin.log"

# ====== COLORS ======
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ====== TIME & LOG ======
timestamp(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "$(timestamp) $*" | tee -a "$LOGFILE"; }

# ====== LOGO ======
logo() {
  clear
  echo -e "${BLUE}"
  if command -v figlet >/dev/null 2>&1; then
    figlet -f big "KenZnhoTT"
  else
    echo "==== KenZnhoTT ===="
  fi
  echo -e "${NC}"
}

# ====== CONFIG ======
save_conf() {
  {
    echo "SERVER_PLACE_ID=${SERVER_PLACE_ID:-0}"
    for i in "${!CLIENTS[@]}"; do
      echo "CLIENT_${i}_NAME=${CLIENT_NAMES[$i]}"
      echo "CLIENT_${i}_PKG=${CLIENTS[$i]}"
      echo "CLIENT_${i}_USERID=${USER_IDS[$i]}"
    done
  } > "$CONF"
  log "[INFO] Đã lưu cấu hình tại: $CONF"
}

load_conf() {
  if [ ! -f "$CONF" ]; then
    echo "[INFO] Không tìm thấy file cấu hình, tạo mới tại: $CONF"
    touch "$CONF"
  else
    source "$CONF"
  fi
}

# ====== RESTART GAME ======
restart_one_pkg(){
  local pkg="$1"
  local reason="$2"
  log "[ACTION][$reason] Restart $pkg"
  am force-stop "$pkg" >/dev/null 2>&1 || true
  sleep 5
  if am start -p "$pkg" -a android.intent.action.MAIN >/dev/null 2>&1; then
    log "[DONE][$reason] $pkg started"
  fi
  if [ -n "$SERVER_PLACE_ID" ]; then
    am start -p "$pkg" -a android.intent.action.VIEW -d "roblox://placeId=$SERVER_PLACE_ID" >/dev/null 2>&1
    log "[INFO][$reason] Deeplink to $SERVER_PLACE_ID"
  fi
  sleep 10
}

# ====== API Roblox thật ======
get_username(){
  local uid="$1"
  if [ -z "$uid" ]; then echo "unknown"; return; fi
  local resp
  resp=$(curl -s "https://users.roblox.com/v1/users/${uid}")
  if [ -z "$resp" ]; then echo "unknown"; return; fi
  echo "$resp" | jq -r '.name // "unknown"'
}

get_status(){
  local uid="$1"
  if [ -z "$uid" ]; then echo "OFFLINE"; return; fi

  local API_URL="https://presence.roblox.com/v1/presence/users"
  local body; body=$(printf '{"userIds":[%s]}' "$uid")
  local resp; resp=$(curl -s -X POST -H "Content-Type: application/json" -d "$body" "$API_URL" --max-time 8)

  if [ -z "$resp" ]; then echo "OFFLINE"; return; fi
  local pres; pres=$(echo "$resp" | jq -r '.userPresences[0].userPresenceType // 0')

  case "$pres" in
    0) echo "OFFLINE" ;;
    1) echo "ONLINE" ;;
    2|3) echo "IN-GAME" ;;
    *) echo "OFFLINE" ;;
  esac
}

# ====== MONITOR ======
monitor_loop(){
  local cycle=0
  while true; do
    logo
    echo -e "${CYAN}KenZnhoTT Auto Rejoin Monitor${NC}"
    echo -e "${YELLOW}+-----------------+---------------+-----------+${NC}"
    echo -e "${GREEN}| Client          | Username      | Status    |${NC}"
    echo -e "${YELLOW}+-----------------+---------------+-----------+${NC}"

    for i in "${!CLIENTS[@]}"; do
      pkg="${CLIENTS[$i]}"
      name="${CLIENT_NAMES[$i]}"
      uid="${USER_IDS[$i]}"
      username=$(get_username "$uid")
      status=$(get_status "$uid")

      if [ "$status" = "OFFLINE" ]; then
        restart_one_pkg "$pkg" "OFFLINE"
      elif [ "$status" = "ONLINE" ]; then
        restart_one_pkg "$pkg" "ONLINE_RECHECK"
      fi

      printf "| %-15s | %-13s | %-9s |\n" "$name" "$username" "$status"
    done

    echo -e "${YELLOW}+-----------------+---------------+-----------+${NC}"
    echo "[KenZnhoTT] Next scan in 60s..."
    sleep 60
    clear
  done
}

# ====== SETUP CLIENTS ======
setup_clients(){
  CLIENTS=()
  CLIENT_NAMES=()
  USER_IDS=()

  while true; do
    read -p "Nhập client (hoặc 'n' để kết thúc): " client
    if [ "$client" = "n" ]; then break; fi
    read -p "Nhập ID tài khoản Roblox: " uid
    CLIENT_NAMES+=("$client")
    USER_IDS+=("$uid")

    pkg=$(pm list packages | grep -i "$client" | head -n 1 | cut -d':' -f2)
    if [ -n "$pkg" ]; then
      echo "Đã tìm thấy client: $pkg"
      CLIENTS+=("$pkg")
    fi
  done

  save_conf
  echo "Đã lưu cấu hình clients."
  sleep 3
}

# ====== MENU ======
menu(){
  logo
  echo -e "${CYAN}Version 3.2 | Created by KenZnhoTT${NC}"
  echo -e "${YELLOW}+----+--------------------------------------+${NC}"
  echo -e "${YELLOW}| No | Lựa chọn                             |${NC}"
  echo -e "${YELLOW}+----+--------------------------------------+${NC}"
  echo -e "| 1  | Bắt đầu Auto Rejoin (Monitor)        |"
  echo -e "| 2  | Thiết lập ID Server (deeplink)       |"
  echo -e "| 3  | Thiết lập Client + ID tài khoản      |"
  echo -e "| 4  | Thoát                                |"
  echo -e "${YELLOW}+----+--------------------------------------+${NC}"
  printf "[KenZnhoTT] Nhập lựa chọn: "
}

# ====== MAIN ======
while true; do
  load_conf
  menu
  read -r choice
  case $choice in
    1)
      if [ -z "${CLIENTS[*]}" ]; then
        echo "⚠️  Chưa có client nào! Vui lòng thiết lập trước (menu 3)."
        sleep 2
        continue
      fi
      monitor_loop
      ;;
    2)
      read -p "Nhập SERVER_PLACE_ID (link game VIP): " SERVER_PLACE_ID
      save_conf
      echo "Đã lưu SERVER_PLACE_ID=$SERVER_PLACE_ID"
      sleep 2
      ;;
    3)
      setup_clients
      ;;
    4)
      echo "Tạm biệt!"
      exit 0
      ;;
    *)
      echo "Lựa chọn không hợp lệ!"
      sleep 1
      ;;
  esac
done
