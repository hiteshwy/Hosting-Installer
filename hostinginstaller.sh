#!/bin/bash
# =========================================================
#   ⚡ Shadow Installer & Manager v1.0 ⚡
#   All-in-one single-installer (Puffer, Draco, Skyport)
#   Author: Shadow Gamer
#   Supported panel (Puffer / Draco / Skyport)
# =========================================================
# Run as root:
#   sudo bash hostinginstaller.sh
# =========================================================

# -------------------------
# Config / Globals
# -------------------------
UPDATE_URL="https://raw.githubusercontent.com/yourusername/yourrepo/main/shadow-installer.sh"
LOG_DIR="/var/log/shadow-installer"
mkdir -p "$LOG_DIR"
TIMESTAMP() { date +"%Y-%m-%d_%H-%M-%S"; }
MAIN_LOG="$LOG_DIR/main-$(TIMESTAMP).log"

# Colors / style
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Ensure script executed as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}${BOLD}✖ Please run this script as root.${NC}"
  exit 1
fi

# Safe paths for installers (original URLs kept)
PUFFER_URL="https://raw.githubusercontent.com/JishnuTheGamer/Vps/refs/heads/main/puffer-panel"
DRACO_URL="https://raw.githubusercontent.com/JishnuTheGamer/Vps/refs/heads/main/draco"
DAEMON_URL="https://raw.githubusercontent.com/JishnuTheGamer/Vps/refs/heads/main/daemon"
SKYPORT_URL="https://raw.githubusercontent.com/JishnuTheGamer/Vps/refs/heads/main/skyport"
SKYPORT_WINGS_URL="https://raw.githubusercontent.com/JishnuTheGamer/skyport/refs/heads/main/wings"
PLAYIT_BINARY_URL="https://github.com/playit-cloud/playit-agent/releases/download/v0.15.26/playit-linux-amd64"
RUN247_URL="https://raw.githubusercontent.com/JishnuTheGamer/24-7/refs/heads/main/24"

# -------------------------
# Utility: Run command with spinner and logging
# -------------------------
run_with_spinner() {
  # Usage: run_with_spinner <logfile> <human-label> <command...>
  local logfile="$1"; shift
  local label="$1"; shift
  local cmd=( "$@" )

  echo -ne "${CYAN}⟳ ${label} ... ${NC}"
  (
    "${cmd[@]}"
  ) &>> "$logfile" &
  local pid=$!

  local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while kill -0 "$pid" 2>/dev/null; do
    for ((i=0;i<${#spinner_chars};i++)); do
      printf "\r${CYAN}%s ${WHITE}%s${NC}" "${spinner_chars:i:1}" "$label"
      sleep 0.08
    done
  done
  wait "$pid"
  local rc=$?
  if [ $rc -eq 0 ]; then
    printf "\r${GREEN}✔ %s completed.${NC}\n" "$label"
  else
    printf "\r${RED}✖ %s failed (exit=%d). See %s${NC}\n" "$label" "$rc" "$logfile"
  fi
  return $rc
}

# -------------------------
# Logo + small intro
# -------------------------
logo() {
  clear
  echo -e "${PURPLE}${BOLD}"
  echo "  ███████╗██╗  ██╗ █████╗ ██████╗  ██████╗ ██╗    ██╗"
  echo "  ██╔════╝██║  ██║██╔══██╗██╔══██╗██╔═══██╗██║    ██║"
  echo "  ███████╗███████║███████║██████╔╝██║   ██║██║ █╗ ██║"
  echo "  ╚════██║██╔══██║██╔══██║██╔══██╗██║   ██║██║███╗██║"
  echo "  ███████║██║  ██║██║  ██║██║  ██║╚██████╔╝╚███╔███╔╝"
  echo "  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝  ╚══╝╚══╝"
  echo -e "${WHITE}        Shadow Installer & Manager v1.0${NC}"
  echo ""
  echo -e "${CYAN}Made by: Shadow Gamer${NC}"
  echo ""
}

# -------------------------
# Service helpers (create/check)
# -------------------------
create_systemd_service() {
  # Usage: create_systemd_service <service-name> <working-dir> <exec-command>
  local service_name="$1"; shift
  local workdir="$1"; shift
  local exec_cmd="$*"

  local service_file="/etc/systemd/system/${service_name}.service"
  cat > "$service_file" <<EOF
[Unit]
Description=Shadow managed - ${service_name}
After=network.target

[Service]
Type=simple
WorkingDirectory=${workdir}
ExecStart=${exec_cmd}
Restart=on-failure
RestartSec=5
User=root
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$service_name"
  echo "Service $service_name created & enabled" >> "$MAIN_LOG"
}

# -------------------------
# Resource monitor (simple)
# -------------------------
show_resource_monitor() {
  echo -e "${BLUE}${BOLD}↺ System Resources${NC}"
  echo -e "${CYAN}Uptime:${NC} $(uptime -p)"
  echo -e "${CYAN}Load:${NC} $(cat /proc/loadavg | awk '{print $1" "$2" "$3}')"
  echo -e "${CYAN}Memory:${NC} $(free -h | awk '/^Mem:/ {print $3" used / "$2" total (" int($3/$2*100) "%)"}')"
  echo -e "${CYAN}Disk Root:${NC} $(df -h / | awk 'NR==2{print $3" used / "$2" total (" $5 " used)"}')"
  echo ""
  read -p "Press Enter to continue..."
}

# -------------------------
# Status / Service controls for panels/daemons
# -------------------------
service_exists() {
  systemctl list-unit-files --type=service | grep -q "^$1.service"
}

service_status() {
  if systemctl is-active --quiet "$1"; then
    echo -e "${GREEN}● $1 is running${NC}"
  else
    echo -e "${RED}○ $1 is not running${NC}"
  fi
}

service_start() { systemctl start "$1" && service_status "$1"; }
service_stop()  { systemctl stop  "$1" && service_status "$1"; }
service_restart() { systemctl restart "$1" && service_status "$1"; }

# -------------------------
# Admin-only wrapper
# -------------------------
require_admin() {
  # script runs as root so we're admin - but we keep a consistent check
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This action requires root privileges.${NC}"
    return 1
  fi
  return 0
}

# -------------------------
# Original feature wrappers (kept original names/URLs)
# each installer will log into $LOG_DIR/<name>-<ts>.log
# -------------------------
install_puffer() {
  local log="$LOG_DIR/puffer-$(TIMESTAMP).log"
  run_with_spinner "$log" "Puffer panel install" bash -c "bash <(curl -s $PUFFER_URL)"
}

install_draco() {
  local log="$LOG_DIR/draco-$(TIMESTAMP).log"
  run_with_spinner "$log" "Draco panel install" bash -c "bash <(curl -s $DRACO_URL)"
}

install_draco_daemon() {
  local log="$LOG_DIR/draco-daemon-$(TIMESTAMP).log"
  run_with_spinner "$log" "Draco daemon install (wings)" bash -c "bash <(curl -s $DAEMON_URL)"
}

install_skyport() {
  local log="$LOG_DIR/skyport-$(TIMESTAMP).log"
  run_with_spinner "$log" "Skyport panel install" bash -c "bash <(curl -s $SKYPORT_URL)"
}

install_skyport_wings() {
  local log="$LOG_DIR/skyport-wings-$(TIMESTAMP).log"
  run_with_spinner "$log" "Skyport daemon install (wings)" bash -c "bash <(curl -s $SKYPORT_WINGS_URL)"
}

run_24_7_original() {
  local log="$LOG_DIR/24-7-$(TIMESTAMP).log"
  run_with_spinner "$log" "24/7 runner" python3 - <<PY
import sys,subprocess
subprocess.run(["bash","-c","python3 <(curl -s $RUN247_URL)"], shell=True)
PY
}

# -------------------------
# Playit tunnel helpers
# -------------------------
ensure_playit_binary() {
  if [ ! -x "./playit-linux-amd64" ]; then
    echo -e "${CYAN}Downloading playit client...${NC}"
    run_with_spinner "$LOG_DIR/playit-download-$(TIMESTAMP).log" "download playit" wget -q -O playit-linux-amd64 "$PLAYIT_BINARY_URL"
    chmod +x playit-linux-amd64
  fi
}

playit_create() {
  ensure_playit_binary
  echo -e "${GREEN}Follow the interactive prompts from Playit to create a tunnel.${NC}"
  ./playit-linux-amd64
}

playit_start() {
  ensure_playit_binary
  ./playit-linux-amd64
}

# -------------------------
# Extra: create systemd service for panel/daemon (auto-start)
# -------------------------
offer_create_service() {
  read -p "Create systemd service for this component? (yes/no): " a
  if [[ "$a" =~ ^(y|yes)$ ]]; then
    read -p "Working directory (full path) where node should run (e.g. /root/panel): " wd
    read -p "Exec command (full command to run, e.g. /usr/bin/node .): " exec_cmd
    if [ -z "$wd" ] || [ -z "$exec_cmd" ]; then
      echo -e "${RED}Invalid input, skipping service creation.${NC}"
      return
    fi
    read -p "Service name (short, no spaces, e.g. draco-panel): " sname
    if [ -z "$sname" ]; then
      echo -e "${RED}No service name provided. Skipping.${NC}"
      return
    fi
    create_systemd_service "$sname" "$wd" "$exec_cmd"
    echo -e "${GREEN}Service $sname created & started.${NC}"
  fi
}

# -------------------------
# Status/Restart menus (for admin)
# -------------------------
manage_services_menu() {
  require_admin || return
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Admin: Service Manager${NC}"
    echo -e "${CYAN}1) Check status of a service"
    echo -e "2) Start a service"
    echo -e "3) Stop a service"
    echo -e "4) Restart a service"
    echo -e "5) List all shadow-related services (contains 'draco'/'skyport'/'puffer')"
    echo -e "🔙 Back"
    read -p "Choice [1-6]: " c
    case $c in
      1) read -p "Service name: " s; service_status "$s" ; read -p "Enter to continue...";;
      2) read -p "Service name: " s; service_start "$s" ; read -p "Enter to continue...";;
      3) read -p "Service name: " s; service_stop "$s" ; read -p "Enter to continue...";;
      4) read -p "Service name: " s; service_restart "$s" ; read -p "Enter to continue...";;
      5) systemctl list-units --type=service --state=running | egrep 'draco|skyport|puffer|playit' || echo "No matching services" ; read -p "Enter to continue...";;
      *) break ;;
    esac
  done
}

# -------------------------
# Update self
# -------------------------
self_update() {
  require_admin || return
  echo -e "${CYAN}Downloading updated installer from configured UPDATE_URL...${NC}"
  tmp="/tmp/shadow-installer-$(date +%s).sh"
  if curl -fsSL "$UPDATE_URL" -o "$tmp"; then
    echo -e "${GREEN}Downloaded updated script to $tmp${NC}"
    read -p "Replace current script with downloaded version? (yes/no): " ans
    if [[ "$ans" =~ ^(y|yes)$ ]]; then
      cp "$tmp" "$(realpath "$0")"
      chmod +x "$(realpath "$0")"
      echo -e "${GREEN}Updated. Please re-run the script.${NC}"
      exit 0
    else
      echo "Update canceled."
    fi
  else
    echo -e "${RED}Failed to download update. Check UPDATE_URL.${NC}"
  fi
}

# -------------------------
# Logs browser
# -------------------------
browse_logs() {
  clear
  echo -e "${BLUE}${BOLD}Logs in: $LOG_DIR${NC}"
  ls -lh "$LOG_DIR"
  echo ""
  read -p "Enter log filename to show (or leave empty to return): " lf
  if [ -n "$lf" ] && [ -f "$LOG_DIR/$lf" ]; then
    less "$LOG_DIR/$lf"
  fi
}

# -------------------------
# Menus for each panel (original features preserved)
# -------------------------
puffer_menu() {
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Puffer Panel${NC}"
    echo -e "${CYAN}1) Install Puffer Panel (original installer)"
    echo -e "2) Create systemd service for Puffer"
    echo -e "3) Status / Start / Stop a service"
    echo -e "🔙 Back"
    read -p "Choice [1-4]: " ch
    case $ch in
      1) install_puffer; prompt_daemon "puffer"; read -p "Press Enter...";;
      2) offer_create_service; read -p "Press Enter...";;
      3) manage_services_menu; ;;
      *) break ;;
    esac
  done
}

draco_menu() {
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Draco${NC}"
    echo -e "${CYAN}1) Install Draco Panel (original installer)"
    echo -e "2) Install Draco Daemon (wings) (original installer)"
    echo -e "3) Start Panel (run node locally now)"
    echo -e "4) Start Daemon (run node locally now)"
    echo -e "5) Create systemd service for Panel/Daemon"
    echo -e "6) Status / Start / Stop a service"
    echo -e "🔙 Back"
    read -p "Choice [1-7]: " ch
    case $ch in
      1) install_draco; prompt_daemon "draco"; read -p "Press Enter...";;
      2) install_draco_daemon; read -p "Press Enter...";;
      3) echo -e "${CYAN}Starting panel (node .) from ./panel/panel (if exists)${NC}"; cd panel/panel 2>/dev/null || echo "Dir missing"; node . &>> "$LOG_DIR/draco-panel-$(TIMESTAMP).log" & echo $! > /tmp/draco-panel.pid; echo "Started (PID stored /tmp/draco-panel.pid)"; read -p "Press Enter...";;
      4) echo -e "${CYAN}Starting daemon (node .) from ./daemon/daemon (if exists)${NC}"; cd daemon/daemon 2>/dev/null || echo "Dir missing"; node . &>> "$LOG_DIR/draco-daemon-$(TIMESTAMP).log" & echo $! > /tmp/draco-daemon.pid; echo "Started (PID stored /tmp/draco-daemon.pid)"; read -p "Press Enter...";;
      5) offer_create_service; ;;
      6) manage_services_menu; ;;
      *) break ;;
    esac
  done
}

skyport_menu() {
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Skyport${NC}"
    echo -e "${CYAN}1) Install Skyport Panel (original installer)"
    echo -e "2) Install Skyport Daemon (wings) (original installer)"
    echo -e "3) Start Panel (run node locally now)"
    echo -e "4) Start Daemon (run node locally now)"
    echo -e "5) Create systemd service for Panel/Daemon"
    echo -e "6) Status / Start / Stop a service"
    echo -e "🔙 Back"
    read -p "Choice [1-7]: " ch
    case $ch in
      1) install_skyport; prompt_daemon "skyport"; read -p "Press Enter...";;
      2) install_skyport_wings; read -p "Press Enter...";;
      3) echo -e "${CYAN}Starting panel (node .) from ./panel (if exists)${NC}"; cd panel 2>/dev/null || echo "Dir missing"; node . &>> "$LOG_DIR/skyport-panel-$(TIMESTAMP).log" & echo $! > /tmp/skyport-panel.pid; echo "Started (PID stored /tmp/skyport-panel.pid)"; read -p "Press Enter...";;
      4) echo -e "${CYAN}Starting daemon (node .) from ./skyportd (if exists)${NC}"; cd skyportd 2>/dev/null || echo "Dir missing"; node . &>> "$LOG_DIR/skyport-daemon-$(TIMESTAMP).log" & echo $! > /tmp/skyport-daemon.pid; echo "Started (PID stored /tmp/skyport-daemon.pid)"; read -p "Press Enter...";;
      5) offer_create_service; ;;
      6) manage_services_menu; ;;
      *) break ;;
    esac
  done
}

# prompt daemon install after panel install (keeps original UX)
prompt_daemon() {
  local panel="$1"
  read -p "Do you want to install the daemon (wings) for ${panel}? (yes/no): " ans
  if [[ "$ans" =~ ^(y|yes)$ ]]; then
    if [[ "$panel" == "skyport" ]]; then
      install_skyport_wings
    else
      install_draco_daemon
    fi
  fi
}

# -------------------------
# Top-level menus
# -------------------------
main_menu() {
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Main Menu${NC}"
    echo -e "${CYAN}1️⃣  Install Panel (Puffer / Draco / Skyport)"
    echo -e "2️⃣  24/7 Run (original)"
    echo -e "3️⃣  Tunnel Create (Playit)"
    echo -e "4️⃣  Admin: Service & Status"
    echo -e "5️⃣  Resource Monitor"
    echo -e "6️⃣  Logs"
    echo -e "7️⃣  Update Installer"
    echo -e "❌  Exit"
    echo ""
    read -p "👉 Enter your choice [1-8]: " choice
    case $choice in
      1)
        panel_selector_menu
        ;;
      2)
        read -p "Run 24/7 runner now? (yes/no): " r
        if [[ "$r" =~ ^(y|yes)$ ]]; then run_24_7_original; fi
        ;;
      3)
        tunnel_menu
        ;;
      4)
        manage_main_admin
        ;;
      5)
        show_resource_monitor
        ;;
      6)
        browse_logs
        ;;
      7)
        self_update
        ;;
      8|exit|q|quit)
        echo -e "${GREEN}Goodbye — Shadow Installer${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option${NC}"
        sleep 0.6
        ;;
    esac
  done
}

panel_selector_menu() {
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Install / Manage Panels${NC}"
    echo -e "${CYAN}1) Puffer Panel"
    echo -e "2) Draco"
    echo -e "3) Skyport"
    echo -e "🔙 Back"
    read -p "Choice [1-4]: " c
    case $c in
      1) puffer_menu ;;
      2) draco_menu ;;
      3) skyport_menu ;;
      *) break ;;
    esac
  done
}

tunnel_menu() {
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Tunnel (Playit)${NC}"
    echo -e "${CYAN}1) Create Tunnel (interactive Playit)"
    echo -e "2) Start Playit client (if configured)"
    echo -e "3) Download/Ensure Playit client"
    echo -e "🔙 Back"
    read -p "Choice [1-4]: " c
    case $c in
      1) playit_create; read -p "Press Enter...";;
      2) playit_start; read -p "Press Enter...";;
      3) ensure_playit_binary; read -p "Press Enter...";;
      *) break ;;
    esac
  done
}

manage_main_admin() {
  require_admin || return
  while true; do
    clear; logo
    echo -e "${BLUE}${BOLD}Admin Control${NC}"
    echo -e "${CYAN}1) Service Manager (start/stop/status)"
    echo -e "2) Create systemd service (generic)"
    echo -e "3) List shadow logs directory"
    echo -e "🔙 Back"
    read -p "Choice [1-4]: " ch
    case $ch in
      1) manage_services_menu ;;
      2) offer_create_service ;;
      3) ls -lh "$LOG_DIR"; read -p "Press Enter...";;
      *) break ;;
    esac
  done
}

# -------------------------
# Entry
# -------------------------
main_menu
