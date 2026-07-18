# shellcheck shell=bash
# Local VM stable IP: status, drift, Netplan static wizard + rollback.
# Sourced by the toolkit entry point after lib/access.sh; do not execute directly.

[[ -n "${_ERPNEXT_DEV_LOCAL_IP_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_LOCAL_IP_LOADED=1

: "${LOCAL_IP_STATE_FILE:=/etc/erpnext-dev/local-ip.state}"
: "${LOCAL_IP_NETPLAN_DIR:=/etc/netplan}"
: "${LOCAL_IP_BACKUP_DIR:=/etc/erpnext-dev/local-ip-backups}"
: "${LOCAL_IP_NETPLAN_FILE:=99-erpnext-dev-static.yaml}"
: "${LOCAL_IP_DRY_RUN:=0}"

local_ip_state_file() {
  printf '%s\n' "${LOCAL_IP_STATE_FILE}"
}

local_ip_netplan_dir() {
  printf '%s\n' "${LOCAL_IP_NETPLAN_DIR}"
}

local_ip_backup_dir() {
  printf '%s\n' "${LOCAL_IP_BACKUP_DIR}"
}

local_ip_netplan_path() {
  printf '%s/%s\n' "$(local_ip_netplan_dir)" "${LOCAL_IP_NETPLAN_FILE}"
}

local_ip_read_state_key() {
  local key="$1" file
  file="$(local_ip_state_file)"
  [[ -r "$file" ]] || return 1
  sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -n1
}

local_ip_current_ip() {
  if [[ -n "${LOCAL_IP_DETECT_IP:-}" ]]; then
    printf '%s\n' "${LOCAL_IP_DETECT_IP}"
    return 0
  fi
  if declare -F get_vm_ip >/dev/null 2>&1; then
    get_vm_ip
  else
    printf 'unknown\n'
  fi
}

local_ip_current_iface() {
  if [[ -n "${LOCAL_IP_DETECT_IFACE:-}" ]]; then
    printf '%s\n' "${LOCAL_IP_DETECT_IFACE}"
    return 0
  fi
  if declare -F get_primary_interface >/dev/null 2>&1; then
    get_primary_interface 2>/dev/null || true
  else
    printf '\n'
  fi
}

local_ip_current_gateway() {
  if [[ -n "${LOCAL_IP_DETECT_GATEWAY:-}" ]]; then
    printf '%s\n' "${LOCAL_IP_DETECT_GATEWAY}"
    return 0
  fi
  if declare -F get_default_gateway >/dev/null 2>&1; then
    get_default_gateway 2>/dev/null || true
  else
    printf '\n'
  fi
}

# dhcp | static | unknown — based on Netplan files + toolkit drop-in.
local_ip_detect_method() {
  local dir netplan_file found_dhcp=0 found_static=0
  dir="$(local_ip_netplan_dir)"
  netplan_file="$(local_ip_netplan_path)"

  if [[ -f "$netplan_file" ]]; then
    if grep -Eqi 'dhcp4:[[:space:]]*true' "$netplan_file" 2>/dev/null; then
      printf 'dhcp\n'
      return 0
    fi
    if grep -Eqi 'dhcp4:[[:space:]]*false' "$netplan_file" 2>/dev/null \
      || grep -Eqi 'addresses:' "$netplan_file" 2>/dev/null; then
      printf 'static\n'
      return 0
    fi
  fi

  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' f; do
      [[ "$(basename "$f")" == "${LOCAL_IP_NETPLAN_FILE}" ]] && continue
      if grep -Eqi 'dhcp4:[[:space:]]*true' "$f" 2>/dev/null; then
        found_dhcp=1
      fi
      if grep -Eqi 'dhcp4:[[:space:]]*false' "$f" 2>/dev/null; then
        found_static=1
      fi
    done < <(find "$dir" -maxdepth 1 \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null || true)
  fi

  if (( found_static == 1 && found_dhcp == 0 )); then
    printf 'static\n'
  elif (( found_dhcp == 1 )); then
    printf 'dhcp\n'
  else
    printf 'unknown\n'
  fi
}

local_ip_prefix_for_iface() {
  local iface="${1:-}" cand
  [[ -n "$iface" ]] || { printf '24\n'; return 0; }
  cand="$(ip -o -4 addr show dev "$iface" scope global 2>/dev/null | awk '{print $4; exit}' || true)"
  if [[ "$cand" == */* ]]; then
    printf '%s\n' "${cand##*/}"
  else
    printf '24\n'
  fi
}

local_ip_save_mapping() {
  local ip iface method site gateway recorded file dir
  require_sudo

  ip="$(local_ip_current_ip)"
  iface="$(local_ip_current_iface)"
  method="$(local_ip_detect_method)"
  gateway="$(local_ip_current_gateway)"
  site="${SITE_NAME:-erp.test}"
  recorded="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)"
  file="$(local_ip_state_file)"
  dir="$(dirname "$file")"

  if [[ "$ip" == "unknown" ]] || ! is_usable_vm_ip "$ip" 2>/dev/null; then
    fail "Cannot save mapping: no usable VM IP detected (got '${ip}')"
  fi

  if [[ "${LOCAL_IP_DRY_RUN}" == "1" ]]; then
    mkdir -p "$dir" 2>/dev/null || true
  else
    $SUDO mkdir -p "$dir"
  fi

  {
    printf 'SAVED_IP=%s\n' "$ip"
    printf 'SITE_NAME=%s\n' "$site"
    printf 'IFACE=%s\n' "${iface:-}"
    printf 'METHOD=%s\n' "$method"
    printf 'GATEWAY=%s\n' "${gateway:-}"
    printf 'RECORDED_AT=%s\n' "$recorded"
    if [[ -n "${LOCAL_IP_LAST_BACKUP:-}" ]]; then
      printf 'NETPLAN_BACKUP=%s\n' "${LOCAL_IP_LAST_BACKUP}"
    elif saved_backup="$(local_ip_read_state_key NETPLAN_BACKUP 2>/dev/null || true)" && [[ -n "$saved_backup" ]]; then
      printf 'NETPLAN_BACKUP=%s\n' "$saved_backup"
    fi
  } | if [[ "${LOCAL_IP_DRY_RUN}" == "1" ]]; then
    cat >"$file"
  else
    $SUDO tee "$file" >/dev/null
    $SUDO chmod 600 "$file"
    $SUDO chown root:root "$file" 2>/dev/null || true
  fi

  status_line "Saved mapping" "OK" "${site} -> ${ip} (${method})"
  echo "State file: ${file}"
}

show_local_ip_status() {
  local ip iface method gateway mac site saved_ip saved_at saved_method drift
  ip="$(local_ip_current_ip)"
  iface="$(local_ip_current_iface)"
  method="$(local_ip_detect_method)"
  gateway="$(local_ip_current_gateway)"
  site="${SITE_NAME:-erp.test}"
  saved_ip="$(local_ip_read_state_key SAVED_IP 2>/dev/null || true)"
  saved_at="$(local_ip_read_state_key RECORDED_AT 2>/dev/null || true)"
  saved_method="$(local_ip_read_state_key METHOD 2>/dev/null || true)"
  if declare -F get_primary_mac >/dev/null 2>&1; then
    mac="$(get_primary_mac 2>/dev/null || true)"
  else
    mac=""
  fi

  ui_box_start "Local VM IP Status"
  status_line "Site" "INFO" "$site"
  if is_usable_vm_ip "$ip" 2>/dev/null; then
    status_line "Current IP" "OK" "$ip"
  else
    status_line "Current IP" "WARN" "${ip:-unknown}"
  fi
  status_line "Interface" "INFO" "${iface:-unknown}"
  status_line "Gateway" "INFO" "${gateway:-unknown}"
  status_line "MAC" "INFO" "${mac:-unknown}"
  case "$method" in
    static) status_line "Addressing" "OK" "static (Netplan signals)" ;;
    dhcp) status_line "Addressing" "WARN" "DHCP (IP may change after reboot)" ;;
    *) status_line "Addressing" "INFO" "unknown (inspect Netplan / DHCP)" ;;
  esac
  if [[ -n "$saved_ip" ]]; then
    if [[ "$saved_ip" == "$ip" ]]; then
      drift="match"
      status_line "Saved mapping" "OK" "${saved_ip} (${saved_method:-?}; ${saved_at:-unknown})"
      status_line "Drift" "OK" "$drift"
    else
      status_line "Saved mapping" "WARN" "${saved_ip} (${saved_method:-?}; ${saved_at:-unknown})"
      status_line "Drift" "FAIL" "saved ${saved_ip} != current ${ip}"
    fi
  else
    status_line "Saved mapping" "INFO" "not recorded; run $(toolkit_cmd local-ip-save)"
  fi
  ui_box_end

  echo "Next:"
  echo "  $(toolkit_cmd local-ip-plan)"
  echo "  $(toolkit_cmd local-ip-drift-check)"
  if [[ "$method" == "dhcp" || "$method" == "unknown" ]]; then
    echo "  $(toolkit_cmd local-static-ip-wizard)"
  fi
  echo "  $(toolkit_cmd hosts-command)"
}

show_local_ip_plan() {
  local ip method host_os
  ip="$(local_ip_current_ip)"
  method="$(local_ip_detect_method)"
  if declare -F effective_host_os >/dev/null 2>&1; then
    host_os="$(effective_host_os)"
  else
    host_os="linux"
  fi

  ui_box_start "Local VM Stable IP Plan"
  echo "Goal: keep ${SITE_NAME:-erp.test} working after guest reboot."
  echo "Current IP: ${ip} · Addressing: ${method} · Host OS hint: ${host_os}"
  echo
  echo "Recommended order:"
  echo "  1) Prefer a hypervisor DHCP reservation (stable lease by MAC)."
  echo "     Docs: docs/LOCAL-VM-STABLE-IP.md (KVM, VirtualBox, Hyper-V, VMware/Proxmox)."
  echo "     CLI guide: $(toolkit_cmd local-fixed-ip-guide)"
  echo "  2) Or pin a static address inside this guest with Netplan:"
  echo "     $(toolkit_cmd local-static-ip-wizard)"
  echo "  3) Always refresh HOST /etc/hosts when the IP changes:"
  echo "     $(toolkit_cmd hosts-command)"
  echo "  4) Save the mapping for drift detection:"
  echo "     $(toolkit_cmd local-ip-save)"
  echo
  echo "Rollback Netplan changes: $(toolkit_cmd local-static-ip-rollback)"
  ui_box_end
}

# Exit 0 = OK (match or no saved mapping)
# Exit 1 = drift (saved != current)
# Exit 2 = no usable current IP
run_local_ip_drift_check() {
  local ip saved_ip site
  ip="$(local_ip_current_ip)"
  saved_ip="$(local_ip_read_state_key SAVED_IP 2>/dev/null || true)"
  site="${SITE_NAME:-erp.test}"

  ui_box_start "Local IP Drift Check"
  if [[ "$ip" == "unknown" ]] || ! is_usable_vm_ip "$ip" 2>/dev/null; then
    status_line "Current IP" "FAIL" "${ip:-unknown}"
    ui_box_end
    return 2
  fi
  status_line "Current IP" "OK" "$ip"

  if [[ -z "$saved_ip" ]]; then
    status_line "Saved mapping" "INFO" "none — run $(toolkit_cmd local-ip-save) after hosts/SSL are OK"
    status_line "Drift" "OK" "nothing to compare"
    ui_box_end
    echo "HOST /etc/hosts should map ${site} -> ${ip}:"
    if declare -F print_host_dns_commands_for_site >/dev/null 2>&1; then
      print_host_dns_commands_for_site "$site" "$ip"
    fi
    return 0
  fi

  status_line "Saved mapping" "INFO" "$saved_ip"
  if [[ "$saved_ip" == "$ip" ]]; then
    status_line "Drift" "OK" "match"
    ui_box_end
    return 0
  fi

  status_line "Drift" "FAIL" "saved ${saved_ip} != current ${ip}"
  ui_box_end
  warn "Guest IP changed. Update HOST /etc/hosts, then $(toolkit_cmd local-ip-save)."
  echo
  if declare -F print_host_dns_commands_for_site >/dev/null 2>&1; then
    print_host_dns_commands_for_site "$site" "$ip"
  fi
  echo
  echo "Optional: pin a static guest IP with $(toolkit_cmd local-static-ip-wizard)"
  return 1
}

local_ip_backup_netplan() {
  local dir backup_root stamp dest
  dir="$(local_ip_netplan_dir)"
  backup_root="$(local_ip_backup_dir)"
  stamp="$(date +%Y%m%dT%H%M%S 2>/dev/null || echo manual)"
  dest="${backup_root}/netplan-${stamp}"

  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" 2>/dev/null || $SUDO mkdir -p "$dir"
  fi

  if [[ "${LOCAL_IP_DRY_RUN}" == "1" ]]; then
    mkdir -p "$dest"
    if [[ -d "$dir" ]]; then
      cp -a "$dir"/. "$dest"/ 2>/dev/null || true
    fi
  else
    $SUDO mkdir -p "$dest"
    if compgen -G "${dir}/*" >/dev/null 2>&1; then
      $SUDO cp -a "${dir}/." "$dest/"
    fi
  fi
  LOCAL_IP_LAST_BACKUP="$dest"
  printf '%s\n' "$dest"
}

local_ip_write_static_netplan() {
  local iface="$1" address="$2" prefix="$3" gateway="$4" path tmp
  path="$(local_ip_netplan_path)"
  tmp="$(mktemp /tmp/erpnext-dev-netplan.XXXXXX)"

  cat >"$tmp" <<EOF
# Managed by erpnext-dev local-static-ip-wizard — do not edit by hand unless you know Netplan.
network:
  version: 2
  ethernets:
    ${iface}:
      dhcp4: false
      addresses:
        - ${address}/${prefix}
      routes:
        - to: default
          via: ${gateway}
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
EOF

  if [[ "${LOCAL_IP_DRY_RUN}" == "1" ]]; then
    mkdir -p "$(dirname "$path")"
    cp "$tmp" "$path"
  else
    $SUDO mkdir -p "$(dirname "$path")"
    $SUDO cp "$tmp" "$path"
    $SUDO chmod 600 "$path"
  fi
  rm -f "$tmp"
  printf '%s\n' "$path"
}

local_ip_apply_netplan() {
  if [[ "${LOCAL_IP_DRY_RUN}" == "1" ]]; then
    echo "DRY RUN: skipping netplan apply"
    return 0
  fi
  if ! command -v netplan >/dev/null 2>&1; then
    fail "netplan is not installed on this guest"
  fi
  # Prefer try (auto-rollback on loss of connectivity); fall back to apply.
  if $SUDO netplan try --timeout 30; then
    return 0
  fi
  warn "netplan try failed or was unavailable; attempting netplan apply"
  $SUDO netplan apply
}

run_local_static_ip_wizard() {
  local ip iface gateway prefix backup path site
  require_sudo

  ip="$(local_ip_current_ip)"
  iface="$(local_ip_current_iface)"
  gateway="$(local_ip_current_gateway)"
  site="${SITE_NAME:-erp.test}"

  ui_box_start "Local Static IP Wizard"
  echo "Pins a static IPv4 address inside THIS guest via Netplan."
  echo "Prefer a hypervisor DHCP reservation when available (see $(toolkit_cmd local-ip-plan))."
  echo
  if [[ "$ip" == "unknown" ]] || ! is_usable_vm_ip "$ip" 2>/dev/null; then
    fail "No usable current IP to pin. Fix networking first."
  fi
  if [[ -z "$iface" ]]; then
    fail "Could not detect primary interface (set LOCAL_IP_DETECT_IFACE=... to override)."
  fi
  if [[ -z "$gateway" ]]; then
    fail "Could not detect default gateway (set LOCAL_IP_DETECT_GATEWAY=... to override)."
  fi
  prefix="$(local_ip_prefix_for_iface "$iface")"

  status_line "Interface" "INFO" "$iface"
  status_line "Address" "INFO" "${ip}/${prefix}"
  status_line "Gateway" "INFO" "$gateway"
  status_line "Site" "INFO" "$site"
  status_line "Netplan file" "INFO" "$(local_ip_netplan_path)"
  ui_box_end

  if [[ "${LOCAL_IP_DRY_RUN}" != "1" ]]; then
    if ! confirm "Backup Netplan and apply this static config now?"; then
      echo "Cancelled."
      return 0
    fi
  fi

  # Do not capture via $() — backup helper sets LOCAL_IP_LAST_BACKUP in-process.
  local_ip_backup_netplan >/dev/null
  backup="${LOCAL_IP_LAST_BACKUP:-}"
  status_line "Backup" "OK" "$backup"
  path="$(local_ip_write_static_netplan "$iface" "$ip" "$prefix" "$gateway")"
  status_line "Wrote" "OK" "$path"

  local_ip_apply_netplan
  local_ip_save_mapping

  echo
  echo "Update HOST /etc/hosts if needed:"
  if declare -F print_host_dns_commands_for_site >/dev/null 2>&1; then
    print_host_dns_commands_for_site "$site" "$ip"
  fi
  echo
  echo "Rollback: $(toolkit_cmd local-static-ip-rollback)"
  echo "Docs: docs/LOCAL-VM-STABLE-IP.md"
}

run_local_static_ip_rollback() {
  local backup dest dir
  require_sudo

  backup="$(local_ip_read_state_key NETPLAN_BACKUP 2>/dev/null || true)"
  if [[ -z "$backup" || ! -d "$backup" ]]; then
    # Fall back to newest backup directory.
    dest="$(local_ip_backup_dir)"
    if [[ -d "$dest" ]]; then
      backup="$(find "$dest" -maxdepth 1 -type d -name 'netplan-*' 2>/dev/null | sort | tail -n1 || true)"
    fi
  fi

  ui_box_start "Local Static IP Rollback"
  if [[ -z "$backup" || ! -d "$backup" ]]; then
    status_line "Backup" "FAIL" "no Netplan backup found under $(local_ip_backup_dir)"
    ui_box_end
    return 1
  fi
  status_line "Restore from" "INFO" "$backup"
  dir="$(local_ip_netplan_dir)"

  if [[ "${LOCAL_IP_DRY_RUN}" != "1" ]]; then
    if ! confirm "Restore Netplan from backup and re-apply?"; then
      echo "Cancelled."
      return 0
    fi
  fi

  if [[ "${LOCAL_IP_DRY_RUN}" == "1" ]]; then
    mkdir -p "$dir"
    rm -f "${dir}/${LOCAL_IP_NETPLAN_FILE}" 2>/dev/null || true
    cp -a "$backup"/. "$dir"/ 2>/dev/null || true
  else
    $SUDO mkdir -p "$dir"
    # Remove toolkit drop-in then restore prior files.
    $SUDO rm -f "$(local_ip_netplan_path)" 2>/dev/null || true
    if compgen -G "${backup}/*" >/dev/null 2>&1; then
      $SUDO cp -a "${backup}/." "${dir}/"
    fi
  fi

  local_ip_apply_netplan
  status_line "Netplan" "OK" "restored from backup"
  ui_box_end

  echo "Re-check IP and hosts:"
  echo "  $(toolkit_cmd local-ip-status)"
  echo "  $(toolkit_cmd hosts-command)"
  echo "  $(toolkit_cmd local-ip-save)"
}

show_local_ip_doc_guide() {
  local section="${1:-}"
  ui_box_start "Local VM Stable IP Docs"
  echo "Full guide: docs/LOCAL-VM-STABLE-IP.md"
  if [[ -n "$section" ]]; then
    echo "Section focus: ${section}"
  fi
  echo
  echo "Also available as CLI guides:"
  echo "  $(toolkit_cmd local-fixed-ip-guide)"
  echo "  $(toolkit_cmd kvm-fixed-ip-guide)"
  echo "  $(toolkit_cmd kvm-identify)"
  ui_box_end
  if declare -F show_local_fixed_ip_guide >/dev/null 2>&1; then
    show_local_fixed_ip_guide
  fi
}

show_local_ip_menu() {
  local back_target="${1:-return}"
  local back_label="Main menu"
  while true; do
    ui_submenu_header "Local network / Stable IP" \
      "Keep ${SITE_NAME:-erp.test} working when the guest IP changes"
    menu_location_note "Main menu > Local network" "local-ip-menu"
    echo
    print_two_column_menu \
      "1) IP status" \
      "2) Stable IP plan" \
      "3) Drift check" \
      "4) Save mapping" \
      "5) Hosts command" \
      "6) Static IP wizard" \
      "7) Static IP rollback" \
      "8) Hypervisor guide" \
      "9) KVM identify / reserve" \
      "10) Full docs pointer"
    menu_footer back "$back_label"
    local choice=""
    menu_read_choice choice

    case "$choice" in
      1) show_local_ip_status ;;
      2) show_local_ip_plan ;;
      3) run_local_ip_drift_check || true ;;
      4) local_ip_save_mapping ;;
      5) show_host_hosts_command ;;
      6) run_local_static_ip_wizard ;;
      7) run_local_static_ip_rollback || true ;;
      8) show_local_ip_doc_guide ;;
      9) show_kvm_vm_identification_guide ;;
      10) show_local_ip_doc_guide "overview" ;;
      b|B|"")
        if [[ "$back_target" == "main" ]]; then
          show_menu
          return 0
        fi
        return 0
        ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option" ;;
    esac
  done
}
