# shellcheck shell=bash
# VM firewall, UFW, and Fail2Ban helpers.
[[ -n "${_ERPNEXT_DEV_FIREWALL_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_FIREWALL_LOADED=1

show_production_firewall_plan() {
  local vm_ip domain

  require_sudo

  vm_ip="$(get_vm_ip)"
  domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"

  echo
  echo "============================================================"
  echo "Production Firewall Plan"
  echo "============================================================"
  status_line "Mode" "INFO" "planning only; no firewall changes are applied"
  status_line "VM IP" "INFO" "$vm_ip"
  status_line "Domain" "INFO" "$domain"
  echo
  echo "Current listener summary:"
  for port in 22 80 443 8000 9000 11000 13000; do
    status_line "Port ${port}" "INFO" "$(production_listener_detail "$port")"
  done
  echo
  echo "Recommended cloud/edge firewall for first public test:"
  echo "  22/tcp    allow only your admin IP if possible"
  echo "  80/tcp    allow public, needed for HTTP and Let's Encrypt HTTP-01"
  echo "  443/tcp   allow public, needed for HTTPS"
  echo "  8000/tcp  temporary only; restrict to your admin IP while testing"
  echo
  echo "Recommended long-term production exposure:"
  echo "  22/tcp    restricted to admin IP/VPN"
  echo "  80/tcp    public, redirect/ACME use"
  echo "  443/tcp   public"
  echo "  8000/tcp  closed publicly after Nginx/HTTPS works"
  echo "  9000/tcp  closed publicly"
  echo "  11000/tcp closed publicly"
  echo "  13000/tcp closed publicly"
  echo
  echo "Why:"
  echo "  - 8000 is the Bench web port and should not be the final public entry point."
  echo "  - 9000 is socket.io and should be proxied through Nginx, not opened directly."
  echo "  - 11000/13000 are Redis services and must never be public."
  echo
  echo "Safe check commands:"
  echo "  ss -lntp"
  echo "  $(toolkit_cmd public-vm-readiness)"
  echo "  $(toolkit_cmd production-ssl-plan)"
  echo "============================================================"
}

show_firewall_hardening_status() {
  local vm_ip domain dns_ip active_cert provider proxy_pair proxy_status proxy_detail ssl_pair ssl_status ssl_detail
  local detail pair status message

  require_sudo

  vm_ip="$(get_vm_ip)"
  domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"
  dns_ip="$(resolve_ipv4_first "$domain")"
  active_cert="$(production_nginx_active_cert_path 2>/dev/null || true)"
  provider="$(production_ssl_provider_from_cert_path "$active_cert")"
  proxy_pair="$(production_cloudflare_proxy_hint "$dns_ip" "$vm_ip" "$provider")"
  proxy_status="${proxy_pair%%|*}"
  proxy_detail="${proxy_pair#*|}"
  ssl_pair="$(production_ssl_runtime_detail)"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"

  echo
  echo "============================================================"
  echo "Firewall Hardening Status"
  echo "============================================================"
  status_line "Mode" "INFO" "check only; no firewall changes are applied"
  status_line "Domain" "INFO" "${domain}; DNS=${dns_ip:-unresolved}; VM=${vm_ip}"
  status_line "SSL provider" "$([[ "$provider" != "not configured" ]] && echo OK || echo WARN)" "$provider"
  status_line "HTTPS entrypoint" "$ssl_status" "$ssl_detail"
  status_line "Cloudflare proxy" "$proxy_status" "$proxy_detail"
  echo
  echo "Local listeners inside the VM:"
  echo "  These rows show what services are bound on the server itself."
  echo "  A service may still be blocked externally by the cloud provider firewall."
  for port in 22 80 443 8000 9000 11000 13000; do
    pair="$(production_listener_exposure_label "$port")"
    status="${pair%%|*}"
    detail="${pair#*|}"
    case "$port" in
      22)
        if [[ "$status" == "WARN" ]]; then
          status="INFO"
          message="${detail}; local SSH listener exists. Verify the cloud firewall allows only admin IP/VPN."
        else
          message="$detail"
        fi
        ;;
      80|443)
        if [[ "$status" == "WARN" || "$status" == "INFO" ]]; then
          if [[ "$provider" == "Cloudflare Origin CA" ]]; then
            message="${detail}; expected local Nginx listener. Cloud firewall should allow Cloudflare/public on this port."
          else
            message="${detail}; expected public HTTP/HTTPS entrypoint."
          fi
          status="OK"
        else
          message="$detail"
        fi
        ;;
      8000|9000)
        if [[ "$status" == "WARN" && "$ssl_status" == "OK" ]]; then
          status="INFO"
          message="${detail}; backend listener exists for Nginx/ERPNext. Verify the cloud firewall blocks public access."
        elif [[ "$status" == "WARN" ]]; then
          status="INFO"
          message="${detail}; temporary backend listener. Close/restrict externally after HTTPS works."
        else
          message="$detail"
        fi
        ;;
      11000|13000)
        if [[ "$status" == "WARN" ]]; then
          status="FAIL"
          message="${detail}; Redis must never be publicly reachable. Bind to localhost and block at firewall."
        else
          message="$detail"
        fi
        ;;
      *) message="$detail" ;;
    esac
    status_line "Port ${port}" "$status" "$message"
  done
  echo
  echo "Recommended cloud inbound firewall:"
  echo "  22/tcp     allow only your admin IP or VPN"
  echo "  80/tcp     allow public, or Cloudflare IP ranges if staying proxied"
  echo "  443/tcp    allow public, or Cloudflare IP ranges if staying proxied"
  echo "  8000/tcp   no allow rule; block public access"
  echo "  9000/tcp   no allow rule; block public access"
  echo "  11000/tcp  no allow rule; block public access"
  echo "  13000/tcp  no allow rule; block public access"
  echo
  echo "External validation from your workstation, not from inside the VM:"
  echo "  curl -I https://${domain}"
  echo "  curl -I --connect-timeout 10 http://${vm_ip}:8000"
  echo "  curl -I --connect-timeout 10 http://${vm_ip}:9000"
  echo "Expected: HTTPS returns 200/redirect through Cloudflare/Nginx; 8000/9000 time out or are blocked."
  echo
  echo "Internal validation from this VM:"
  echo "  $(toolkit_cmd firewall-hardening-status)"
  echo "  $(toolkit_cmd public-vm-readiness)"
  echo "============================================================"
}


security_environment_label() {
  if is_public_vm_workflow; then
    printf '%s\n' "production"
  else
    printf '%s\n' "local"
  fi
}

security_mode_status() {
  local env domain vm_ip ssl_pair ssl_status ssl_detail ufw_state install_state_value runtime

  require_sudo
  env="$(security_environment_label)"
  domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  install_state_value="$(install_state 2>/dev/null || echo 'Not installed')"
  runtime="$(runtime_state 2>/dev/null || echo 'Stopped')"

  echo
  echo "============================================================"
  echo "Security Mode Status"
  echo "============================================================"
  status_line "Detected profile" "INFO" "$env"
  status_line "Deployment mode" "INFO" "${DEPLOYMENT_MODE:-development}"
  status_line "Site/domain" "INFO" "$domain"
  status_line "VM IP" "INFO" "$vm_ip"
  status_line "Install" "$([[ "$install_state_value" == "Installed" ]] && echo OK || echo WARN)" "$install_state_value"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"

  if [[ "$env" == "production" ]]; then
    ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured')"
    ssl_status="${ssl_pair%%|*}"
    ssl_detail="${ssl_pair#*|}"
    status_line "Production HTTPS" "$ssl_status" "$ssl_detail"
    echo
    echo "Production hardening should run only after the real domain, DNS, install, service, and HTTPS path are validated."
  else
    if ssl_is_configured 2>/dev/null; then
      status_line "Local HTTPS" "OK" "configured"
    else
      status_line "Local HTTPS" "INFO" "not configured yet"
    fi
    echo
    echo "Local VM hardening keeps dev access available from private networks. It must not block 8000/9000 unless Nginx/HTTPS is fully replacing direct Bench access."
  fi

  if ufw_is_active; then
    ufw_state="active"
  else
    ufw_state="inactive or not installed"
  fi
  status_line "UFW" "$([[ "$ufw_state" == active ]] && echo OK || echo INFO)" "$ufw_state"
  echo "============================================================"
}

firewall_backup_snapshot() {
  local stamp target
  require_sudo
  stamp="$(date +%Y%m%d-%H%M%S)"
  target="${FIREWALL_BACKUP_DIR}/${stamp}"
  $SUDO mkdir -p "$target"
  $SUDO chmod 700 "${FIREWALL_BACKUP_DIR}" "$target" 2>/dev/null || true

  if command -v ufw >/dev/null 2>&1; then
    ufw_status_raw | $SUDO tee "${target}/ufw-status.txt" >/dev/null || true
    $SUDO cp -a /etc/ufw/user.rules "${target}/user.rules" 2>/dev/null || true
    $SUDO cp -a /etc/ufw/user6.rules "${target}/user6.rules" 2>/dev/null || true
    $SUDO cp -a /etc/ufw/before.rules "${target}/before.rules" 2>/dev/null || true
    $SUDO cp -a /etc/ufw/before6.rules "${target}/before6.rules" 2>/dev/null || true
  else
    printf 'UFW not installed at snapshot time.\n' | $SUDO tee "${target}/ufw-status.txt" >/dev/null || true
  fi

  ok "Firewall rollback snapshot saved: ${target}"
}

show_firewall_rollback_snapshots() {
  require_sudo
  echo
  echo "============================================================"
  echo "Firewall Rollback Snapshots"
  echo "============================================================"
  if [[ ! -d "${FIREWALL_BACKUP_DIR}" ]]; then
    status_line "Snapshots" "INFO" "none yet"
  else
    $SUDO find "${FIREWALL_BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -printf '%TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort -r | head -10 | sed 's/^/  /' || true
  fi
  echo
  echo "Rollback guidance: these snapshots preserve UFW rule files before toolkit changes. If access breaks, use the provider console and inspect the latest folder."
  echo "============================================================"
}

private_network_allow_sources() {
  printf '%s\n' "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16"
}

current_ssh_client_ip() {
  if [[ -n "${SSH_CLIENT:-}" ]]; then
    printf '%s\n' "${SSH_CLIENT%% *}"
  fi
}

allow_local_dev_ports() {
  local source current_ip

  # SSH is intentionally kept broadly allowed at the VM firewall layer to avoid lockout.
  # Restrict SSH at the host/router/cloud layer when needed.
  $SUDO ufw allow 22/tcp
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp

  while read -r source; do
    [[ -n "$source" ]] || continue
    $SUDO ufw allow from "$source" to any port 8000 proto tcp
    $SUDO ufw allow from "$source" to any port 9000 proto tcp
  done < <(private_network_allow_sources)

  current_ip="$(current_ssh_client_ip || true)"
  if [[ -n "$current_ip" ]]; then
    $SUDO ufw allow from "$current_ip" to any port 22 proto tcp || true
    $SUDO ufw allow from "$current_ip" to any port 8000 proto tcp || true
    $SUDO ufw allow from "$current_ip" to any port 9000 proto tcp || true
  fi
}

configure_local_vm_firewall() {
  require_sudo

  echo
  echo "============================================================"
  echo "Apply Local VM Firewall Profile"
  echo "============================================================"
  echo "This profile is for local .test development VMs. It keeps direct Bench access available."
  echo
  echo "Allowed:"
  echo "  - 22/tcp for SSH"
  echo "  - 80/tcp and 443/tcp for local Nginx/SSL"
  echo "  - 8000/tcp and 9000/tcp from private RFC1918 networks for local Bench access"
  echo
  echo "Blocked by default: public/non-private inbound traffic and internal service ports."
  echo
  if is_public_vm_workflow; then
    warn "This VM is currently marked as public/production. Use the Production Firewall Profile unless you are intentionally switching back to local dev."
  fi
  confirm "Apply Local VM firewall profile now?" || return 1

  firewall_backup_snapshot
  log "Installing UFW"
  $SUDO apt-get update
  $SUDO apt-get install -y ufw

  log "Applying Local VM UFW profile"
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing
  allow_local_dev_ports

  # Keep Redis/MariaDB-style internal ports closed externally.
  for port in 11000 12000 13000 3306; do
    $SUDO ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    $SUDO ufw delete allow "$port" >/dev/null 2>&1 || true
  done

  $SUDO ufw --force enable

  ui_box_start "Result Summary"
  status_line "Profile" "OK" "Local VM"
  status_line "Dev access" "OK" "8000/9000 allowed from private networks"
  status_line "HTTP/HTTPS" "OK" "80/443 allowed"
  status_line "Rollback snapshot" "OK" "${FIREWALL_BACKUP_DIR}"
  ui_box_end
  verify_local_firewall_profile || true
  ui_next "$(toolkit_cmd verify-access)" "$(toolkit_cmd vm-firewall-status)"
}

configure_production_vm_firewall() {
  local ssl_pair ssl_status ssl_detail
  require_sudo

  echo
  echo "============================================================"
  echo "Apply Production Firewall Profile"
  echo "============================================================"
  echo "This profile is for a public VM behind Nginx/HTTPS. It blocks direct backend ports."
  echo
  if ! is_public_vm_workflow; then
    err "This VM is currently detected as local/development."
    status_line "Deployment mode" "WARN" "${DEPLOYMENT_MODE:-development}"
    status_line "Site" "WARN" "$SITE_NAME"
    echo
    echo "Set a real production domain first with: $(toolkit_cmd set-domain)"
    echo "Or use the Local VM Firewall Profile instead."
    return 1
  fi

  if [[ -z "${PRODUCTION_DOMAIN:-}" ]] || ! validate_production_domain_value "${PRODUCTION_DOMAIN:-}" >/dev/null 2>&1; then
    err "A valid production domain is required before production firewall hardening."
    echo "Run: $(toolkit_cmd set-domain)"
    return 1
  fi

  ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured')"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"
  status_line "Production HTTPS" "$ssl_status" "$ssl_detail"
  if [[ "$ssl_status" != "OK" ]]; then
    warn "Production HTTPS is not confirmed. Blocking backend ports now may remove your only working browser access path."
    confirm "Continue anyway and apply production firewall profile?" || return 1
  else
    confirm "Apply production firewall profile now?" || return 1
  fi

  firewall_backup_snapshot
  log "Installing UFW"
  $SUDO apt-get update
  $SUDO apt-get install -y ufw

  log "Applying Production UFW profile"
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing
  $SUDO ufw allow 22/tcp
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp

  for port in 8000 9000 11000 12000 13000 3306; do
    $SUDO ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    $SUDO ufw delete allow "$port" >/dev/null 2>&1 || true
    $SUDO ufw deny "${port}/tcp" >/dev/null 2>&1 || true
  done

  $SUDO ufw --force enable

  ui_box_start "Result Summary"
  status_line "Profile" "OK" "Production"
  status_line "Public entry" "OK" "80/443 allowed"
  status_line "Backend ports" "OK" "8000/9000 blocked at UFW layer"
  status_line "Rollback snapshot" "OK" "${FIREWALL_BACKUP_DIR}"
  ui_box_end
  show_vm_firewall_status
}

verify_local_firewall_profile() {
  require_sudo
  echo
  echo "============================================================"
  echo "Local Firewall Access Check"
  echo "============================================================"
  if ! command -v ufw >/dev/null 2>&1; then
    status_line "UFW" "WARN" "not installed"
    echo "============================================================"
    return 1
  fi
  ufw_is_active && status_line "UFW" "OK" "active" || status_line "UFW" "WARN" "inactive"
  for port in 22 80 443 8000 9000; do
    if ufw_port_has_allow "$port"; then
      status_line "Port ${port}" "OK" "allow rule present"
    else
      status_line "Port ${port}" "WARN" "no allow rule detected"
    fi
  done
  echo
  echo "Host-side tests to run from your $(host_os_label) host machine:"
  print_host_dns_tests_for_site "$SITE_NAME" "$(get_vm_ip 2>/dev/null || echo unknown)"
  echo "============================================================"
}

repair_local_access() {
  require_sudo

  echo
  echo "============================================================"
  echo "Repair Local VM Access"
  echo "============================================================"
  echo "This restores the local development access profile after hardening blocks erp.test or port 8000."
  echo
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "VM IP" "INFO" "$(get_vm_ip 2>/dev/null || echo unknown)"
  echo
  confirm "Restore local firewall access now?" || return 1

  firewall_backup_snapshot
  $SUDO apt-get update
  $SUDO apt-get install -y ufw
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing
  allow_local_dev_ports
  $SUDO ufw --force enable

  ui_box_start "Result Summary"
  status_line "Local access" "OK" "22/80/443 and private 8000/9000 rules restored"
  status_line "Rollback snapshot" "OK" "${FIREWALL_BACKUP_DIR}"
  ui_box_end
  verify_local_firewall_profile || true
  verify_access || true
}


vm_firewall_plan() {
  local vm_ip domain

  require_sudo
  vm_ip="$(get_vm_ip)"
  domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"

  echo
  echo "============================================================"
  echo "VM Firewall / UFW Plan"
  echo "============================================================"
  status_line "Mode" "INFO" "planning only; no firewall changes are applied"
  status_line "VM IP" "INFO" "$vm_ip"
  status_line "Domain" "INFO" "$domain"
  echo
  echo "Safe default UFW profile:"
  echo "  - Default incoming: deny"
  echo "  - Default outgoing: allow"
  echo "  - Allow 22/tcp from any source at UFW layer to avoid dynamic-IP lockout"
  echo "  - Allow 80/tcp for Nginx / Cloudflare / redirects"
  echo "  - Allow 443/tcp for Nginx / Cloudflare HTTPS"
  echo "  - Do not allow 8000, 9000, 11000, or 13000"
  echo
  echo "Why SSH stays open in UFW by default:"
  echo "  - Your admin IP may change. Restrict SSH at the cloud provider firewall first."
  echo "  - UFW can be made stricter later with: $(toolkit_cmd ufw-ssh-admin-only)"
  echo "  - That advanced SSH restriction can lock you out if the wrong IP is used."
  echo
  echo "Recommended layering:"
  echo "  Layer 1: ERPNext/Nginx service listeners"
  echo "  Layer 2: UFW inside this VM"
  echo "  Layer 3: Cloud provider firewall"
  echo "  Layer 4: Cloudflare proxy/WAF/CDN"
  echo
  echo "Commands:"
  echo "  $(toolkit_cmd configure-vm-firewall)"
  echo "  $(toolkit_cmd configure-fail2ban)"
  echo "  $(toolkit_cmd vm-firewall-status)"
  echo "  $(toolkit_cmd fail2ban-status)"
  echo "  $(toolkit_cmd security-hardening-wizard)"
  echo "============================================================"
}

ufw_status_raw() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 1
  fi
  $SUDO ufw status verbose 2>/dev/null || true
}

ufw_is_active() {
  command -v ufw >/dev/null 2>&1 || return 1
  $SUDO ufw status 2>/dev/null | grep -qi '^Status:[[:space:]]*active'
}

ufw_port_lines() {
  local port="$1"
  command -v ufw >/dev/null 2>&1 || return 0
  $SUDO ufw status 2>/dev/null | grep -E "(^|[[:space:]])${port}(/tcp)?([[:space:]]|$)" || true
}

ufw_port_allow_lines() {
  local port="$1"
  ufw_port_lines "$port" | grep -E '[[:space:]]ALLOW([[:space:]]|$)' || true
}

ufw_port_deny_lines() {
  local port="$1"
  ufw_port_lines "$port" | grep -E '[[:space:]](DENY|REJECT)([[:space:]]|$)' || true
}

ufw_port_has_allow() {
  [[ -n "$(ufw_port_allow_lines "$1")" ]]
}

ufw_port_has_deny() {
  [[ -n "$(ufw_port_deny_lines "$1")" ]]
}

show_vm_firewall_status() {
  local status default_line port lines state detail

  require_sudo

  echo
  echo "============================================================"
  echo "VM Firewall / UFW Status"
  echo "============================================================"
  if ! command -v ufw >/dev/null 2>&1; then
    status_line "UFW" "WARN" "not installed"
    echo "Run: $(toolkit_cmd configure-vm-firewall)"
    echo "============================================================"
    return 0
  fi

  status="inactive"
  ufw_is_active && status="active"
  status_line "UFW" "$([[ "$status" == active ]] && echo OK || echo WARN)" "$status"
  default_line="$(ufw_status_raw | awk '/^Default:/ {print; exit}')"
  status_line "Default policy" "INFO" "${default_line:-unknown}"
  echo
  echo "Expected safe default UFW rules:"
  for port in 22 80 443 8000 9000 11000 13000; do
    lines="$(ufw_port_lines "$port" | paste -sd ';' -)"
    case "$port" in
      22)
        if ufw_port_has_allow 22; then
          state="OK"
          detail="allowed at UFW layer to avoid lockout; restrict SSH at cloud firewall"
        else
          state="WARN"
          detail="no UFW allow rule detected; SSH could be blocked if UFW is active"
        fi
        ;;
      80|443)
        if ufw_port_has_allow "$port"; then
          state="OK"
          detail="allowed for Nginx/Cloudflare HTTPS path"
        else
          state="WARN"
          detail="no UFW allow rule detected; Cloudflare/Nginx may be blocked"
        fi
        ;;
      8000|9000)
        if ufw_port_has_allow "$port"; then
          if is_public_vm_workflow; then
            state="WARN"
            detail="explicit UFW ALLOW rule found; remove it for production after HTTPS works"
          else
            state="OK"
            detail="allowed for local VM direct Bench access"
          fi
        elif ufw_port_has_deny "$port"; then
          if is_public_vm_workflow; then
            state="OK"
            detail="explicit UFW DENY rule present; backend is blocked at the VM layer"
          else
            state="WARN"
            detail="explicit UFW DENY rule present; local erp.test:${port} may be blocked"
          fi
        else
          if is_public_vm_workflow; then
            state="OK"
            detail="no UFW allow rule; backend should be blocked by default deny and the cloud firewall"
          else
            state="WARN"
            detail="no allow rule detected; local erp.test:${port} may be blocked"
          fi
        fi
        ;;
      11000|13000)
        if ufw_port_has_allow "$port"; then
          state="WARN"
          detail="explicit UFW ALLOW rule found; remove it unless you intentionally need this"
        elif ufw_port_has_deny "$port"; then
          state="OK"
          detail="explicit UFW DENY rule present"
        else
          state="OK"
          detail="no UFW allow rule; should be blocked externally by UFW/default deny"
        fi
        ;;
    esac
    [[ -n "$lines" ]] && detail+="; rule(s): ${lines}"
    status_line "Port ${port}" "$state" "$detail"
  done
  echo
  echo "Raw UFW status:"
  ufw_status_raw | sed 's/^/  /'
  echo
  echo "Note: UFW protects the VM itself. The cloud provider firewall should still restrict SSH and block backend ports at the edge."
  echo "============================================================"
}


configure_vm_firewall() {
  require_sudo

  echo
  echo "============================================================"
  echo "Configure VM Firewall / UFW"
  echo "============================================================"
  echo "This command is now environment-aware. It will choose a Local VM or Production profile based on saved config."
  echo
  security_mode_status
  echo

  if is_public_vm_workflow; then
    echo "Detected production/public VM workflow."
    configure_production_vm_firewall
  else
    echo "Detected local/development VM workflow."
    configure_local_vm_firewall
  fi
}

configure_ufw_ssh_admin_only() {
  local detected_ip admin_ip

  require_sudo
  command -v ufw >/dev/null 2>&1 || fail "UFW is not installed. Run configure-vm-firewall first."

  detected_ip="${ADMIN_SSH_SOURCE_IP:-}"
  if [[ -z "$detected_ip" && -n "${SSH_CLIENT:-}" ]]; then
    detected_ip="${SSH_CLIENT%% *}"
  fi

  echo
  echo "============================================================"
  echo "Advanced UFW SSH Restriction"
  echo "============================================================"
  warn "This can lock you out if your IP changes or is entered incorrectly."
  echo "Recommended default: restrict SSH in the cloud provider firewall, not in UFW."
  echo "Keep a second SSH session open and confirm provider console/rescue access before continuing."
  echo
  echo "Detected current SSH client IP: ${detected_ip:-unknown}"
  if [[ -n "${ADMIN_SSH_SOURCE_IP:-}" ]]; then
    admin_ip="$ADMIN_SSH_SOURCE_IP"
  else
    read -r -p "Admin public IPv4 to allow for SSH [${detected_ip:-}]: " admin_ip
    admin_ip="${admin_ip:-$detected_ip}"
  fi

  [[ -n "$admin_ip" ]] || fail "Admin IP is required."
  if ! [[ "$admin_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
    fail "Only IPv4/CIDR is supported by this helper. Example: 68.144.2.171/32"
  fi
  [[ "$admin_ip" == */* ]] || admin_ip="${admin_ip}/32"

  status_line "New SSH source" "INFO" "$admin_ip"
  confirm "Apply UFW SSH restriction to ${admin_ip}?" || return 1
  confirm "Final confirmation: keep a second SSH session open. Continue?" || return 1

  log "Restricting UFW SSH to ${admin_ip}"
  $SUDO ufw allow from "$admin_ip" to any port 22 proto tcp
  $SUDO ufw delete allow 22/tcp >/dev/null 2>&1 || true
  $SUDO ufw delete allow ssh >/dev/null 2>&1 || true
  $SUDO ufw --force enable

  ui_box_start "Result Summary"
  status_line "UFW SSH" "OK" "restricted to ${admin_ip}"
  status_line "Lockout safety" "WARN" "test a second SSH session before closing this one"
  ui_box_end
  ui_next "ssh root@$(get_vm_ip 2>/dev/null || echo VM_IP)" "$(toolkit_cmd vm-firewall-status)"
}

show_fail2ban_status() {
  require_sudo

  echo
  echo "============================================================"
  echo "Fail2Ban Status"
  echo "============================================================"
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    status_line "Fail2Ban" "WARN" "not installed"
    echo "Run: $(toolkit_cmd configure-fail2ban)"
    echo "============================================================"
    return 0
  fi

  if $SUDO systemctl is-active --quiet fail2ban; then
    status_line "Fail2Ban service" "OK" "running"
  else
    status_line "Fail2Ban service" "WARN" "not running"
  fi

  if $SUDO fail2ban-client status sshd >/tmp/erpnext-dev-fail2ban-sshd-status.$$ 2>/dev/null; then
    status_line "sshd jail" "OK" "enabled"
    sed 's/^/  /' /tmp/erpnext-dev-fail2ban-sshd-status.$$ || true
    rm -f /tmp/erpnext-dev-fail2ban-sshd-status.$$
  else
    rm -f /tmp/erpnext-dev-fail2ban-sshd-status.$$
    status_line "sshd jail" "WARN" "not active or not found"
  fi
  echo "============================================================"
}

configure_fail2ban() {
  local bantime findtime maxretry jail_file

  require_sudo
  bantime="${FAIL2BAN_SSH_BANTIME:-1h}"
  findtime="${FAIL2BAN_SSH_FINDTIME:-10m}"
  maxretry="${FAIL2BAN_SSH_MAXRETRY:-5}"
  jail_file="/etc/fail2ban/jail.d/erpnext-dev-sshd.conf"

  echo
  echo "============================================================"
  echo "Configure Fail2Ban for SSH"
  echo "============================================================"
  status_line "bantime" "INFO" "$bantime"
  status_line "findtime" "INFO" "$findtime"
  status_line "maxretry" "INFO" "$maxretry"
  echo
  echo "This enables the sshd jail to reduce repeated unauthorized SSH login attempts."
  confirm "Install/configure Fail2Ban sshd jail now?" || return 1

  log "Installing Fail2Ban"
  $SUDO apt-get update
  $SUDO apt-get install -y fail2ban

  log "Writing Fail2Ban sshd jail"
  $SUDO mkdir -p /etc/fail2ban/jail.d
  $SUDO tee "$jail_file" >/dev/null <<EOF
[sshd]
enabled = true
backend = systemd
port = ssh
filter = sshd
bantime = ${bantime}
findtime = ${findtime}
maxretry = ${maxretry}
EOF

  $SUDO systemctl enable --now fail2ban
  $SUDO systemctl restart fail2ban

  ui_box_start "Result Summary"
  status_line "Fail2Ban" "OK" "service enabled and restarted"
  status_line "sshd jail" "OK" "enabled"
  status_line "bantime" "INFO" "$bantime"
  status_line "findtime" "INFO" "$findtime"
  status_line "maxretry" "INFO" "$maxretry"
  ui_box_end
  ui_next "$(toolkit_cmd fail2ban-status)" "$(toolkit_cmd security-hardening-wizard)"
}


security_hardening_wizard() {
  local choice

  require_sudo
  while true; do
    ui_submenu_header "Security Hardening" \
      "Local VM profile for erp.test · Production only after domain + HTTPS"
    security_mode_status
    echo
    print_two_column_menu \
      "1) Security mode status" \
      "2) Local VM firewall profile" \
      "3) Production firewall profile" \
      "4) Environment-aware firewall" \
      "5) Repair local VM access" \
      "6) UFW status" \
      "7) Apply Fail2Ban for SSH" \
      "8) Fail2Ban status" \
      "9) Public firewall status" \
      "10) Firewall rollback snapshots" \
      "11) Advanced: restrict SSH in UFW"
    menu_footer
    menu_read_choice choice
    case "$choice" in
      1) security_mode_status; pause_after_screen "Press Enter to return to Security..." ;;
      2) configure_local_vm_firewall; pause_after_screen "Press Enter to return to Security..." ;;
      3) configure_production_vm_firewall; pause_after_screen "Press Enter to return to Security..." ;;
      4) configure_vm_firewall; pause_after_screen "Press Enter to return to Security..." ;;
      5) repair_local_access; pause_after_screen "Press Enter to return to Security..." ;;
      6) show_vm_firewall_status; pause_after_screen "Press Enter to return to Security..." ;;
      7) configure_fail2ban; pause_after_screen "Press Enter to return to Security..." ;;
      8) show_fail2ban_status; pause_after_screen "Press Enter to return to Security..." ;;
      9) show_firewall_hardening_status; pause_after_screen "Press Enter to return to Security..." ;;
      10) show_firewall_rollback_snapshots; pause_after_screen "Press Enter to return to Security..." ;;
      11) configure_ufw_ssh_admin_only; pause_after_screen "Press Enter to return to Security..." ;;
      b|B|"") return 0 ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option." ;;
    esac
  done
}
