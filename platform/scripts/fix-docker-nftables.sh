#!/usr/bin/env bash
# fix-docker-nftables.sh
#
# Docker 29.x (nftables backend) only auto-adds FORWARD/CT accept rules and
# a POSTROUTING masquerade rule for the default `docker0` bridge. Any custom
# bridge network (e.g. agent-vault-net) is left without them, so the
# nftables FORWARD chain (policy DROP) silently drops all container
# in/outbound traffic on that network. This happens regardless of whether
# iptables is set to legacy or nftables mode — Docker manages its own
# nftables ruleset either way.
#
# Usage:
#   fix-docker-nftables.sh --check    # report missing rules, no changes (default)
#   fix-docker-nftables.sh --apply    # add any missing rules (requires root)
#   fix-docker-nftables.sh --install  # install a systemd unit that runs
#                                      # --apply every time docker.service
#                                      # starts, so the fix survives reboots
#                                      # and Docker daemon restarts

set -euo pipefail

MODE="${1:---check}"
ERRORS=0

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Must run as root (sudo)." >&2
    exit 1
  fi
}

list_custom_bridge_networks() {
  docker network ls --filter driver=bridge --format '{{.Name}}' | grep -vx 'bridge'
}

bridge_iface_for() {
  local net_id
  net_id="$(docker network inspect "$1" -f '{{.Id}}')"
  echo "br-${net_id:0:12}"
}

subnet_for() {
  docker network inspect "$1" -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
}

check_and_maybe_apply() {
  local name="$1" iface subnet forward_ok=0 ct_ok=0 nat_ok=0

  iface="$(bridge_iface_for "$name")"
  subnet="$(subnet_for "$name")"

  if ! ip link show "$iface" >/dev/null 2>&1; then
    echo "SKIP  $name: interface $iface not present (network not currently in use)"
    return
  fi

  nft list chain ip filter DOCKER-FORWARD 2>/dev/null \
    | grep -qF "iifname \"$iface\" accept" && forward_ok=1

  nft list chain ip filter DOCKER-CT 2>/dev/null \
    | grep -qF "oifname \"$iface\" ct state established,related accept" && ct_ok=1

  if [[ -n "$subnet" ]]; then
    if nft list chain ip nat POSTROUTING 2>/dev/null | grep -F "ip saddr $subnet" | grep -qF "masquerade"; then
      nat_ok=1
    fi
  else
    nat_ok=1 # no IPAM subnet reported, nothing to masquerade for
  fi

  if [[ $forward_ok -eq 1 && $ct_ok -eq 1 && $nat_ok -eq 1 ]]; then
    echo "PASS  $name ($iface)"
    return
  fi

  echo "FAIL  $name ($iface, subnet=${subnet:-none}) forward=$forward_ok ct=$ct_ok nat=$nat_ok"
  ERRORS=$((ERRORS + 1))

  if [[ "$MODE" == "--apply" ]]; then
    require_root
    [[ $forward_ok -eq 0 ]] && nft add rule ip filter DOCKER-FORWARD iifname "$iface" accept
    [[ $ct_ok -eq 0 ]] && nft add rule ip filter DOCKER-CT oifname "$iface" ct state established,related accept
    [[ $nat_ok -eq 0 && -n "$subnet" ]] && nft add rule ip nat POSTROUTING ip saddr "$subnet" oifname != "$iface" masquerade
    echo "FIXED $name"
  fi
}

install_unit() {
  require_root
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  cat > /etc/systemd/system/aaas-fix-docker-nft.service <<UNIT
[Unit]
Description=Reapply nftables rules for custom Docker bridge networks
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=${script_path} --apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now aaas-fix-docker-nft.service
  echo "Installed and started aaas-fix-docker-nft.service (runs --apply after every docker.service start)"
}

case "$MODE" in
  --check|--apply)
    command -v nft >/dev/null 2>&1 || { echo "nft not found" >&2; exit 1; }
    command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
    while IFS= read -r net; do
      check_and_maybe_apply "$net"
    done < <(list_custom_bridge_networks)
    echo ""
    echo "summary errors=$ERRORS"
    [[ "$ERRORS" -eq 0 ]]
    ;;
  --install)
    install_unit
    ;;
  *)
    echo "Usage: $0 [--check|--apply|--install]" >&2
    exit 1
    ;;
esac
