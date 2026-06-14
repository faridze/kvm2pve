#!/usr/bin/env bash
# kvm2pve destination-side helper for Proxmox
set -Eeuo pipefail

VERSION="0.2.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${KVM2PVE_CONFIG:-${SCRIPT_DIR}/kvm2pve.env}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
info(){ echo "${BLUE}>>${NC} $*"; }
ok(){ echo "${GREEN}OK${NC} $*"; }
warn(){ echo "${YELLOW}WARN${NC} $*"; }
die(){ echo "${RED}ERROR${NC} $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

usage(){ cat <<EOF
kvm2pve-dst.sh v${VERSION}

Usage:
  ./kvm2pve-dst.sh init
  ./kvm2pve-dst.sh show
  ./kvm2pve-dst.sh export
  ./kvm2pve-dst.sh close
  ./kvm2pve-dst.sh boot
  ./kvm2pve-dst.sh status
EOF
}

ask(){ local var="$1" prompt="$2" def="${3:-}" val; read -r -p "$prompt${def:+ [$def]}: " val; printf -v "$var" '%s' "${val:-$def}"; }
confirm(){ local prompt="$1" ans; read -r -p "$prompt [yes/no]: " ans; [[ "$ans" == "yes" ]]; }

load_config(){
  [[ -f "$CONFIG_FILE" ]] || die "Config not found: $CONFIG_FILE. Run: ./kvm2pve-dst.sh init"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  : "${VM_NAME:?}"; : "${PVE_VMID:?}"; : "${PVE_DISK:?}"
  NBD_PORT="${NBD_PORT:-10809}"
  NBD_EXPORT="${NBD_EXPORT:-$VM_NAME}"
}

init_config(){
  local vm vmid disk nbd_port nbd_export
  ask vm "Source VM name / NBD export base" "kvm3023"
  ask vmid "Destination Proxmox VMID" "2672"
  ask disk "Destination disk path" "/dev/pve/vm-${vmid}-disk-0"
  ask nbd_port "NBD port" "10809"
  ask nbd_export "NBD export name" "$vm"
  cat > "$CONFIG_FILE" <<EOF
VM_NAME=$vm
PVE_VMID=$vmid
PVE_DISK=$disk
NBD_PORT=$nbd_port
NBD_EXPORT=$nbd_export
EOF
  chmod 600 "$CONFIG_FILE"
  ok "Config written: $CONFIG_FILE"
}

show_config(){
  load_config
  cat <<EOF
Destination Proxmox
-------------------
VM name/export : $VM_NAME
VMID           : $PVE_VMID
Disk           : $PVE_DISK
NBD            : 127.0.0.1:${NBD_PORT}, export=${NBD_EXPORT}
EOF
}

status(){
  load_config
  qm status "$PVE_VMID" 2>/dev/null || true
  pgrep -a qemu-nbd || true
  ss -lntp | grep "$NBD_PORT" || true
  [[ -e "$PVE_DISK" ]] && blockdev --getsize64 "$PVE_DISK" 2>/dev/null || true
}

export_disk(){
  load_config; need qemu-nbd; need ss
  [[ -b "$PVE_DISK" || -f "$PVE_DISK" ]] || die "Destination disk not found: $PVE_DISK"
  if qm status "$PVE_VMID" >/dev/null 2>&1; then
    qm stop "$PVE_VMID" >/dev/null 2>&1 || true
  else
    warn "VMID $PVE_VMID not found by qm status; continuing with disk export only"
  fi
  if ss -lntp | grep -q "127.0.0.1:${NBD_PORT}"; then
    die "NBD port already in use: 127.0.0.1:${NBD_PORT}"
  fi
  pgrep -a qemu-nbd || true
  info "Starting qemu-nbd on 127.0.0.1:${NBD_PORT} export=${NBD_EXPORT} disk=${PVE_DISK}"
  qemu-nbd -t --fork -b 127.0.0.1 -p "$NBD_PORT" -x "$NBD_EXPORT" -f raw "$PVE_DISK"
  sleep 1
  ss -lntp | grep -q "127.0.0.1:${NBD_PORT}" || die "qemu-nbd did not start"
  ok "NBD export is ready"
}

close_export(){
  load_config
  pkill -f "qemu-nbd.*${NBD_PORT}.*${NBD_EXPORT}" >/dev/null 2>&1 || true
  pkill -f "qemu-nbd.*${PVE_DISK}" >/dev/null 2>&1 || true
  sleep 1
  ss -lntp | grep "$NBD_PORT" && warn "Port still appears open" || ok "NBD export closed"
}

boot_vm(){
  load_config
  close_export || true
  qm start "$PVE_VMID"
  ok "Boot command sent for VMID $PVE_VMID"
}

cmd="${1:-}"
case "$cmd" in
  init) init_config ;;
  show) show_config ;;
  export) export_disk ;;
  close) close_export ;;
  boot) boot_vm ;;
  status) status ;;
  -h|--help|help|"") usage ;;
  *) usage; die "Unknown command: $cmd" ;;
esac
