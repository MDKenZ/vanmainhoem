#!/data/data/com.termux/files/usr/bin/bash
# MDKenZnhoTT - Auto Rejoin Tool (root)
# Run: su -c ./MDkenZnhoTT.sh

CONF="$HOME/.MDkenZnhoTT.conf"
LOGFILE="$HOME/roblox_rejoin.log"
save_conf() {
    mkdir -p "$(dirname "$CONF")"   # đảm bảo thư mục tồn tại
    {
        echo "PLACE_ID=${PLACE_ID:-0}"   # nếu PLACE_ID rỗng thì gán tạm 0
        echo "LAST_UPDATE=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$CONF"
}

load_conf() {
    if [ ! -f "$CONF" ]; then
        echo "[INFO] Config not found. Creating default..."
        save_conf                # Tạo file conf mặc định
    fi
    source "$CONF" 2>/dev/null   # Load giá trị (kể cả khi rỗng)
}


# ====== COLORS ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

# Ensure logfile dir exists
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
touch "$LOGFILE" 2>/dev/null || true

# ====== UTILITIES ======
timestamp(){ date '+%Y-%m-%d %H:%M:%S'; }
log(){ echo "$(timestamp) $*" | tee -a "$LOGFILE"; }

# check required commands (best-effort)
check_requirements(){
  for cmd in pm am logcat date awk sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "[WARN] Thiếu lệnh: $cmd (một số chức năng có thể không hoạt động)"
    fi
  done
}
check_requirements

detect_packages() {
    # trả về package name dạng com.example.app mỗi line
    pm list packages 2>/dev/null | grep -Ei "roblox|codexglobal|mangcut" | cut -d: -f2
}

get_username() {
    pkg="$1"
    prefs="/data/data/$pkg/shared_prefs/roblox_prefs.xml"
    if [ -f "$prefs" ]; then
        # dùng sed để trích nội dung giữa tag <string name="username">...</string>
        name=$(sed -n 's/.*<string name="username">\([^<]*\)<\/string>.*/\1/p' "$prefs" | head -n1)
        [ -n "$name" ] && echo "$name" || echo "unknown"
    else
        echo "unknown"
    fi
}

# Foreground check (with fallback)
is_foreground(){
    pkg=$1
    if dumpsys activity activities 2>/dev/null | grep -q "ResumedActivity.*$pkg"; then
      return 0
    fi
    if dumpsys window windows 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | grep -q "$pkg"; then
      return 0
    fi
    return 1
}

# ====== RESTART GAME ======
restart_one_pkg(){
  local pkg="$1"
  local reason="$2"

  log "[ACTION][$reason] Restart $pkg"

  # Kill app
  am force-stop "$pkg" >/dev/null 2>&1 || true
  sleep 6
  log "[ACTION][$reason] $pkg killed"

  # Try generic start first (safer) then specific activity
  if am start -p "$pkg" -a android.intent.action.MAIN >/dev/null 2>&1; then
    log "[DONE][$reason] $pkg started (generic MAIN)"
  else
    am start -n "$pkg/com.roblox.client.AppActivity" -a android.intent.action.MAIN >/dev/null 2>&1 \
      && log "[DONE][$reason] $pkg started with AppActivity" \
      || log "[WARN][$reason] Không thể start bằng AppActivity"
  fi
  sleep 10

  # Deeplink if available
  if [ -n "$PLACE_ID" ]; then
    am start -p "$pkg" -a android.intent.action.VIEW -d "roblox://placeId=$PLACE_ID" >/dev/null 2>&1
    log "[INFO][$reason] Deeplink sau được 10s start -> $PLACE_ID"
  fi

  # Reset watchdog timer (use LAST_ACTIVE associative array)
  LAST_ACTIVE["$pkg"]=$(date +%s)

  # Đợi game load
  log "[WAIT] Chờ game $pkg load (30s)..."
  sleep 30
  
 # Nếu PLACE_ID chưa được set
  log "[ERROR][$reason] PLACE_ID chưa được set!"
  # Có thể thoát hoặc quay lại vòng lặp tùy logic của bạn
  return 1

  sleep 30
  log "[DONE][$reason] Restarted $pkg (đã join)"
}

# ====== STATUS CHECK ======
get_status() {
    pkg=$1
    # Try pidof, fallback to pgrep -f
    pid=$(pidof "$pkg" 2>/dev/null || pgrep -f "$pkg" 2>/dev/null || true)
    if [ -n "$pid" ]; then
        echo "RUNNING"
    else
        echo "OFFLINE"
    fi
}

# ====== LOGCAT ERROR CHECK ======
check_logcat_errors(){
    pkg=$1
    # Escape pkg for grep-safe usage
    pkg_escaped=$(printf '%s' "$pkg" | sed 's/[]\/$*.^[]/\\&/g')
    if logcat -d 2>/dev/null | grep -E "${pkg_escaped}.*(268|277|279|771|267)" >/dev/null 2>&1; then
        log "[ERROR] $pkg gặp lỗi Roblox (268/277/279/771|267) -> restart"
        logcat -c 2>/dev/null || true
        restart_one_pkg "$pkg" "ROBLOX_ERROR"
        return
    fi
    logcat -c 2>/dev/null || true
}

declare -A LAST_ACTIVE

update_activity(){
    pkg=$1
    LAST_ACTIVE["$pkg"]=$(date +%s)
}

check_idle(){
    pkg=$1
    now=$(date +%s)
    last=${LAST_ACTIVE["$pkg"]:-0}
    idle=$((now - last))

    if [ "$idle" -ge 180 ]; then   # 180 giây = 3 phút
        log "[IDLE] $pkg không hoạt động > 3 phút -> restart"
        restart_one_pkg "$pkg" "IDLE_TIMEOUT"
        LAST_ACTIVE["$pkg"]=$now
    fi
}

# Clean exit on Ctrl+C
trap 'log "[INFO] Caught signal, exiting..."; exit 0' INT TERM

# ====== MONITOR LOOP ======
monitor_loop(){
  local cycle=0
  while true; do
    # readarray to preserve newlines and avoid word-splitting
    readarray -t PACKS < <(detect_packages)

    logo
    CPU=$(top -n 1 2>/dev/null | awk '/CPU/ {print $2; exit}' 2>/dev/null || echo "??")
    RAM=$(dumpsys meminfo 2>/dev/null | awk '/Used RAM/ {print $3; exit}' 2>/dev/null || echo "??")
    echo -e "CPU: $CPU | RAM: $RAM"
    echo -e "${YELLOW}+---------------------------+---------------+------------+${NC}"
    echo -e "${GREEN}| Package                   | Username      | Status     |${NC}"
    echo -e "${YELLOW}+---------------------------+---------------+------------+${NC}"

    if [ ${#PACKS[@]} -eq 0 ]; then
      echo "| Không tìm thấy package Roblox nào trên thiết bị. |"
    fi

    for p in "${PACKS[@]}"; do
        # skip empty lines
        [ -z "$p" ] && continue

        user=$(get_username "$p")
        status=$(get_status "$p")

        # Nếu có logcat error -> restart
        check_logcat_errors "$p"

        if [ "$status" = "RUNNING" ]; then
            update_activity "$p"
        else
            log "[WARN] $p OFFLINE -> restart"
            restart_one_pkg "$p" "OFFLINE"
        fi

        # Check idle > 3 phút
        check_idle "$p"

        printf "| %-25s | %-13s | %-10s |\n" "$p" "$user" "$status"
    done

    echo -e "${YELLOW}+---------------------------+---------------+------------+${NC}"
    cycle=$((cycle+1))
    if [ $cycle -ge 120 ]; then
      log "[INFO] Scheduled full refresh"
      for p in "${PACKS[@]}"; do
        [ -z "$p" ] && continue
        restart_one_pkg "$p" "SCHEDULED"
      done
      cycle=0
    fi

    echo "[KenZnhoTT] Next scan in 60s..."
    sleep 60
    logcat -c 2>/dev/null || true
  done
}

# ====== CONFIG ======
save_conf(){ echo "PLACE_ID=$PLACE_ID" > "$CONF"; }
load_conf(){ [ -f "$CONF" ] && source "$CONF"; }

# ====== MENU ======
menu() {
    logo
    echo -e "${CYAN}Version 2.3 | Created by KenZnhoTT${NC}"
    echo -e "${YELLOW}+----+--------------------------------------+${NC}"
    echo -e "${YELLOW}| No | Service Name                         |${NC}"
    echo -e "${YELLOW}+----+--------------------------------------+${NC}"
    echo -e "| 1  | Start Auto Rejoin (Monitor)          |"
    echo -e "| 2  | Setup Game PLACE_ID                  |"
    echo -e "| 3  | Show detected Roblox packages        |"
    echo -e "| 4  | Exit                                 |"
    echo -e "${YELLOW}+----+--------------------------------------+${NC}"
    printf "[KenZnhoTT] Enter command: "
}

# ====== MAIN LOOP ======
while true; do
    load_conf
    menu
    read -r choice
    case $choice in
        1)
            load_conf
            if [ -z "$PLACE_ID" ]; then
                echo "PLACE_ID not set! Please setup first."
                sleep 2
                continue
            fi
            monitor_loop
            ;;
        2)
            printf "Enter PLACE_ID: "
            read -r PLACE_ID
            if [ -n "$PLACE_ID" ]; then
                save_conf
                echo "Saved PLACE_ID=$PLACE_ID"
            else
                echo "PLACE_ID cannot be empty!"
            fi
            sleep 2
            ;;
        3)
            echo "Detected packages:"
            detect_packages
            sleep 3
            ;;
        4)
            echo "Bye!"
            exit 0
            ;;
        *)
            echo "Invalid choice!"
            sleep 1
            ;;
    esac
done
