# shellcheck shell=bash
# VM firewall, UFW, and Fail2Ban helpers.
[[ -n "${_ERPNEXT_DEV_FIREWALL_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_FIREWALL_LOADED=1

show_production_firewall_plan() {
  local vm_ip domain port
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
  status_line "Engine" "INFO" "$(deployment_engine_label)"
  echo
  echo "Recommended cloud/edge firewall:"
  echo "  22/tcp    allow only your admin IP/VPN"
  echo "  80/tcp    public for HTTP redirect / ACME"
  echo "  443/tcp   public for HTTPS"
  if deployment_engine_is_docker; then
    echo "  ${DOCKER_PUBLISH_PORT}/tcp  closed publicly after production HTTPS"
    echo "  8000/9000 are container-internal Frappe ports and must not be host-published"
  else
    echo "  8000/tcp  closed publicly after Nginx/HTTPS works"
    echo "  9000/tcp  closed publicly"
  fi
  echo "  11000/12000/13000/3306 closed publicly"
  echo
  echo "Host listeners relevant to this engine:"
  for port in 22 80 443 $(production_block_ports | sort -un); do
    status_line "Port ${port}" "INFO" "$(production_listener_detail "$port")"
  done
  echo
  ui_next "$(toolkit_cmd configure-vm-firewall)" "$(toolkit_cmd vm-firewall-status)"
  echo "============================================================"
}

show_firewall_hardening_status() {
  require_sudo
  if deployment_engine_is_docker; then
    echo
    echo "============================================================"
    echo "Firewall Hardening Status (Docker)"
    echo "============================================================"
    status_line "Engine" "OK" "Docker $(docker_mode_label)"
    status_line "Direct frontend port" "INFO" "${DOCKER_PUBLISH_PORT} (local/pre-HTTPS only)"
    if docker_is_production && docker_https_enabled; then
      status_line "Public entry" "OK" "80/443 via Traefik"
      status_line "Direct port policy" "OK" "${DOCKER_PUBLISH_PORT} should be blocked/not published publicly"
    else
      status_line "Public entry" "WARN" "production HTTPS not confirmed"
    fi
    echo "============================================================"
    show_vm_firewall_status
    docker_is_production && docker_production_exposure || true
    return 0
  fi

  local vm_ip domain dns_ip active_cert provider proxy_pair proxy_status proxy_detail ssl_pair ssl_status ssl_detail
  local detail pair status message
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
  for port in 22 80 443 8000 9000 11000 13000; do
    pair="$(production_listener_exposure_label "$port")"
    status="${pair%%|*}"; detail="${pair#*|}"; message="$detail"
    case "$port" in
      22) [[ "$status" == WARN ]] && status=INFO && message="${detail}; restrict at cloud firewall" ;;
      80|443) [[ "$status" != FAIL ]] && status=OK ;;
      8000|9000) [[ "$status" == WARN ]] && status=INFO && message="${detail}; block public access after HTTPS" ;;
      11000|13000) [[ "$status" == WARN ]] && status=FAIL ;;
    esac
    status_line "Port ${port}" "$status" "$message"
  done
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
    if deployment_engine_is_docker; then
      if docker_is_production && docker_https_enabled; then
        ssl_status="OK"
        ssl_detail="Docker $(docker_https_mode) on 80/443 via Traefik"
      else
        ssl_status="WARN"
        ssl_detail="Docker production HTTPS not configured"
      fi
    else
      ssl_pair="$(production_ssl_overall_status 2>/dev/null || echo 'WARN|not configured')"
      ssl_status="${ssl_pair%%|*}"
      ssl_detail="${ssl_pair#*|}"
    fi
    status_line "Production HTTPS" "$ssl_status" "$ssl_detail"
    echo
    echo "Production hardening should run only after the real domain, DNS, install, runtime, and HTTPS path are validated."
  else
    if ssl_is_configured 2>/dev/null; then
      status_line "Local HTTPS" "OK" "configured"
    else
      status_line "Local HTTPS" "INFO" "not configured yet"
    fi
    echo
    if deployment_engine_is_docker; then
      echo "Local Docker hardening keeps port ${DOCKER_PUBLISH_PORT} reachable from private networks; native 8000/9000 are not Docker host entry ports."
    else
      echo "Local VM hardening keeps native dev access on 8000/9000 available from private networks unless Nginx/HTTPS replaces direct access."
    fi
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

local_dev_direct_ports() {
  if deployment_engine_is_docker; then
    printf '%s\n' "${DOCKER_PUBLISH_PORT:-8080}"
  else
    printf '%s\n' 8000 9000
  fi
}

production_block_ports() {
  printf '%s\n' 8000 9000 11000 12000 13000 3306
  if deployment_engine_is_docker; then
    case "${DOCKER_PUBLISH_PORT:-8080}" in
      80|443) ;;
      *) printf '%s\n' "${DOCKER_PUBLISH_PORT:-8080}" ;;
    esac
  fi
}

production_https_firewall_status() {
  if deployment_engine_is_docker; then
    if docker_is_production && docker_https_enabled; then
      printf 'OK|Docker Traefik HTTPS enabled for %s\n' "$(docker_public_domain)"
    else
      printf 'WARN|Docker production HTTPS is not enabled; run %s\n' "$(toolkit_cmd docker-https-wizard)"
    fi
  else
    production_ssl_overall_status 2>/dev/null || printf 'WARN|not configured\n'
  fi
}


# Docker-published ports are forwarded before normal UFW INPUT rules, so local
# Docker hardening needs a Docker-aware filter in addition to the host UFW
# profile. Docker's iptables backend provides DOCKER-USER specifically for rules
# that must run before Docker's own forwarding accepts published traffic.
docker_local_firewall_script_path() {
  printf '%s\n' "${DOCKER_LOCAL_FIREWALL_SCRIPT:-/usr/local/lib/erpnext-dev/docker-local-firewall.sh}"
}

docker_local_firewall_service_path() {
  printf '%s\n' "${DOCKER_LOCAL_FIREWALL_SERVICE_PATH:-/etc/systemd/system/erpnext-dev-docker-firewall.service}"
}

docker_local_firewall_chain() {
  printf '%s\n' "ERPNEXT-DEV-LOCAL"
}

docker_local_firewall_filter_supported() {
  command -v iptables >/dev/null 2>&1 || return 1
  $SUDO iptables -nL DOCKER-USER >/dev/null 2>&1
}

write_docker_local_firewall_filter() {
  require_sudo
  local script service chain port admin_ip admin_rule=""
  script="$(docker_local_firewall_script_path)"
  service="$(docker_local_firewall_service_path)"
  chain="$(docker_local_firewall_chain)"
  port="${DOCKER_PUBLISH_PORT:-8080}"
  admin_ip="$(current_ssh_client_ip || true)"
  if [[ -n "$admin_ip" && "$admin_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    admin_rule="iptables -w -A \"\$CHAIN\" -p tcp -m conntrack --ctorigdstport \"\$PORT\" -s ${admin_ip}/32 -j RETURN"
  fi

  $SUDO mkdir -p "$(dirname "$script")" "$(dirname "$service")"
  $SUDO tee "$script" >/dev/null <<EOF_DOCKER_LOCAL_FW
#!/usr/bin/env bash
set -Eeuo pipefail
CHAIN="${chain}"
PORT="${port}"

command -v iptables >/dev/null 2>&1 || exit 1
iptables -w -nL DOCKER-USER >/dev/null 2>&1 || exit 1
iptables -w -N "\$CHAIN" 2>/dev/null || true
iptables -w -F "\$CHAIN"
iptables -w -A "\$CHAIN" -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
iptables -w -A "\$CHAIN" -p tcp -m conntrack --ctorigdstport "\$PORT" -s 127.0.0.0/8 -j RETURN
iptables -w -A "\$CHAIN" -p tcp -m conntrack --ctorigdstport "\$PORT" -s 10.0.0.0/8 -j RETURN
iptables -w -A "\$CHAIN" -p tcp -m conntrack --ctorigdstport "\$PORT" -s 172.16.0.0/12 -j RETURN
iptables -w -A "\$CHAIN" -p tcp -m conntrack --ctorigdstport "\$PORT" -s 192.168.0.0/16 -j RETURN
${admin_rule}
iptables -w -A "\$CHAIN" -p tcp -m conntrack --ctorigdstport "\$PORT" -j DROP
iptables -w -A "\$CHAIN" -j RETURN
while iptables -w -C DOCKER-USER -j "\$CHAIN" >/dev/null 2>&1; do
  iptables -w -D DOCKER-USER -j "\$CHAIN"
done
iptables -w -I DOCKER-USER 1 -j "\$CHAIN"

# Mirror the policy for Docker IPv6 forwarding when that backend is active.
# If Docker IPv6 is disabled, no ip6tables DOCKER-USER chain exists and this
# section is intentionally skipped.
if command -v ip6tables >/dev/null 2>&1 && ip6tables -w -nL DOCKER-USER >/dev/null 2>&1; then
  CHAIN6="${chain}6"
  ip6tables -w -N "\$CHAIN6" 2>/dev/null || true
  ip6tables -w -F "\$CHAIN6"
  ip6tables -w -A "\$CHAIN6" -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
  ip6tables -w -A "\$CHAIN6" -p tcp -m conntrack --ctorigdstport "\$PORT" -s ::1/128 -j RETURN
  ip6tables -w -A "\$CHAIN6" -p tcp -m conntrack --ctorigdstport "\$PORT" -s fc00::/7 -j RETURN
  ip6tables -w -A "\$CHAIN6" -p tcp -m conntrack --ctorigdstport "\$PORT" -s fe80::/10 -j RETURN
  ip6tables -w -A "\$CHAIN6" -p tcp -m conntrack --ctorigdstport "\$PORT" -j DROP
  ip6tables -w -A "\$CHAIN6" -j RETURN
  while ip6tables -w -C DOCKER-USER -j "\$CHAIN6" >/dev/null 2>&1; do
    ip6tables -w -D DOCKER-USER -j "\$CHAIN6"
  done
  ip6tables -w -I DOCKER-USER 1 -j "\$CHAIN6"
fi
EOF_DOCKER_LOCAL_FW
  $SUDO chmod 755 "$script"
  $SUDO chown root:root "$script" 2>/dev/null || true

  $SUDO tee "$service" >/dev/null <<EOF_DOCKER_LOCAL_FW_SERVICE
[Unit]
Description=ERPNext Developer Toolkit Docker local published-port filter
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=${script}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_DOCKER_LOCAL_FW_SERVICE
  $SUDO chmod 644 "$service"
  $SUDO chown root:root "$service" 2>/dev/null || true
}

configure_docker_local_firewall_filter() {
  require_sudo
  deployment_engine_is_docker || return 0
  if ! docker_local_firewall_filter_supported; then
    warn "Docker's DOCKER-USER iptables chain is unavailable. UFW alone does not filter Docker-published ports."
    echo "Keep port ${DOCKER_PUBLISH_PORT:-8080} limited by the VM/hypervisor or cloud firewall, or use Docker's supported firewall backend policy."
    return 1
  fi

  write_docker_local_firewall_filter
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now erpnext-dev-docker-firewall.service >/dev/null 2>&1 || return 1
  docker_local_firewall_filter_status >/dev/null 2>&1
}

docker_local_ipv6_publish_active() {
  command -v docker >/dev/null 2>&1 || return 1
  ${SUDO:-} docker ps \
    --filter "label=com.docker.compose.project=${DOCKER_PROJECT_NAME}" \
    --format '{{.Ports}}' 2>/dev/null | \
    grep -qE "(\[::\]|::):${DOCKER_PUBLISH_PORT:-8080}->8080"
}

docker_local_firewall_filter_status() {
  deployment_engine_is_docker || return 0
  local chain port chain6
  chain="$(docker_local_firewall_chain)"
  chain6="${chain}6"
  port="${DOCKER_PUBLISH_PORT:-8080}"
  command -v iptables >/dev/null 2>&1 || return 1
  $SUDO iptables -nL DOCKER-USER >/dev/null 2>&1 || return 1
  $SUDO iptables -S DOCKER-USER 2>/dev/null | grep -Fq -- "-j ${chain}" || return 1
  $SUDO iptables -S "$chain" 2>/dev/null | grep -F -- "--ctorigdstport ${port}" | grep -q -- '-j DROP' || return 1

  # A host that actually publishes the frontend on IPv6 must have the mirrored
  # IPv6 forwarding filter as well; otherwise the IPv4 policy would be bypassed.
  if docker_local_ipv6_publish_active; then
    command -v ip6tables >/dev/null 2>&1 || return 1
    $SUDO ip6tables -nL DOCKER-USER >/dev/null 2>&1 || return 1
    $SUDO ip6tables -S DOCKER-USER 2>/dev/null | grep -Fq -- "-j ${chain6}" || return 1
    $SUDO ip6tables -S "$chain6" 2>/dev/null | grep -F -- "--ctorigdstport ${port}" | grep -q -- '-j DROP' || return 1
  fi
}

allow_local_dev_ports() {
  local source current_ip port
  $SUDO ufw allow 22/tcp
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp

  # Native Bench listens on host ports, so UFW is authoritative for 8000/9000.
  # Docker-published ports are handled separately in DOCKER-USER because normal
  # UFW INPUT rules are not a reliable control point for Docker forwarding.
  if ! deployment_engine_is_docker; then
    while read -r source; do
      [[ -n "$source" ]] || continue
      while read -r port; do
        [[ -n "$port" ]] || continue
        $SUDO ufw allow from "$source" to any port "$port" proto tcp
      done < <(local_dev_direct_ports)
    done < <(private_network_allow_sources)
  fi

  current_ip="$(current_ssh_client_ip || true)"
  if [[ -n "$current_ip" ]]; then
    $SUDO ufw allow from "$current_ip" to any port 22 proto tcp || true
    if ! deployment_engine_is_docker; then
      while read -r port; do
        [[ -n "$port" ]] || continue
        $SUDO ufw allow from "$current_ip" to any port "$port" proto tcp || true
      done < <(local_dev_direct_ports)
    fi
  fi
}

configure_local_vm_firewall() {
  require_sudo
  local direct_label docker_filter_rc=0 port
  if deployment_engine_is_docker; then
    direct_label="${DOCKER_PUBLISH_PORT}/tcp from private networks for Docker frontend access"
  else
    direct_label="8000/tcp and 9000/tcp from private networks for native Bench access"
  fi

  echo
  echo "============================================================"
  echo "Apply Local VM Firewall Profile"
  echo "============================================================"
  echo "Allowed: 22/tcp, 80/tcp, 443/tcp, and ${direct_label}."
  echo "Internal database/Redis ports remain closed externally."
  if deployment_engine_is_docker; then
    echo "Docker note: published container ports bypass normal UFW INPUT rules, so the toolkit also installs a DOCKER-USER filter for port ${DOCKER_PUBLISH_PORT}."
  fi
  echo
  if is_public_vm_workflow; then
    warn "This VM is marked public/production. Use the Production Firewall Profile unless intentionally switching to local dev."
  fi
  confirm "Apply Local VM firewall profile now?" || return 1

  firewall_backup_snapshot
  $SUDO apt-get update
  $SUDO apt-get install -y ufw
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing
  allow_local_dev_ports

  for port in 11000 12000 13000 3306; do
    $SUDO ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    $SUDO ufw delete allow "$port" >/dev/null 2>&1 || true
  done
  $SUDO ufw --force enable

  if deployment_engine_is_docker; then
    configure_docker_local_firewall_filter || docker_filter_rc=1
  fi

  ui_box_start "Result Summary"
  status_line "Profile" "OK" "Local VM / $(deployment_engine_label)"
  if deployment_engine_is_docker; then
    if [[ "$docker_filter_rc" -eq 0 ]]; then
      status_line "Docker published port" "OK" "${DOCKER_PUBLISH_PORT} limited to private networks by DOCKER-USER"
    else
      status_line "Docker published port" "WARN" "UFW cannot enforce Docker forwarding; use VM/cloud edge filtering"
    fi
  else
    status_line "Direct app access" "OK" "$direct_label"
  fi
  status_line "HTTP/HTTPS" "OK" "80/443 allowed at the host firewall"
  status_line "Rollback snapshot" "OK" "${FIREWALL_BACKUP_DIR}"
  ui_box_end
  verify_local_firewall_profile || true
  ui_next "$(toolkit_cmd verify-access)" "$(toolkit_cmd vm-firewall-status)"
  [[ "$docker_filter_rc" -eq 0 ]]
}

configure_production_vm_firewall() {
  local ssl_pair ssl_status ssl_detail port
  require_sudo

  echo
  echo "============================================================"
  echo "Apply Production Firewall Profile"
  echo "============================================================"
  echo "This profile allows only SSH plus public HTTP/HTTPS and blocks direct application/data ports."
  echo
  if ! is_public_vm_workflow; then
    err "This VM is currently detected as local/development."
    return 1
  fi
  if [[ -z "${PRODUCTION_DOMAIN:-}" ]] || ! validate_production_domain_value "${PRODUCTION_DOMAIN:-}" >/dev/null 2>&1; then
    err "A valid production domain is required before production firewall hardening."
    echo "Run: $(toolkit_cmd set-domain)"
    return 1
  fi

  ssl_pair="$(production_https_firewall_status)"
  ssl_status="${ssl_pair%%|*}"; ssl_detail="${ssl_pair#*|}"
  status_line "Production HTTPS" "$ssl_status" "$ssl_detail"
  if [[ "$ssl_status" != "OK" ]]; then
    warn "HTTPS is not confirmed. Blocking the direct application port may remove the current browser access path."
    confirm "Continue anyway and apply production firewall profile?" || return 1
  else
    confirm "Apply production firewall profile now?" || return 1
  fi

  firewall_backup_snapshot
  $SUDO apt-get update
  $SUDO apt-get install -y ufw
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing
  $SUDO ufw allow 22/tcp
  $SUDO ufw allow 80/tcp
  $SUDO ufw allow 443/tcp

  while read -r port; do
    [[ -n "$port" ]] || continue
    $SUDO ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
    $SUDO ufw delete allow "$port" >/dev/null 2>&1 || true
    $SUDO ufw deny "${port}/tcp" >/dev/null 2>&1 || true
  done < <(production_block_ports | sort -un)

  $SUDO ufw --force enable

  ui_box_start "Result Summary"
  status_line "Profile" "OK" "Production / $(deployment_engine_label)"
  status_line "Public entry" "OK" "80/443 allowed"
  if deployment_engine_is_docker; then
    status_line "Direct Docker port" "OK" "production Compose keeps ${DOCKER_PUBLISH_PORT} loopback-only before HTTPS and unpublishes it after HTTPS"
    status_line "Container backend" "OK" "8000/9000 remain container-internal; UFW denies are defense-in-depth for accidental host binds"
  else
    status_line "Backend ports" "OK" "8000/9000 blocked at UFW layer"
  fi
  status_line "Rollback snapshot" "OK" "${FIREWALL_BACKUP_DIR}"
  ui_box_end
  show_vm_firewall_status
}

verify_local_firewall_profile() {
  require_sudo
  local port
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
  for port in 22 80 443; do
    if ufw_port_has_allow "$port"; then
      status_line "Port ${port}" "OK" "host UFW allow rule present"
    else
      status_line "Port ${port}" "WARN" "no host UFW allow rule detected"
    fi
  done
  if deployment_engine_is_docker; then
    if docker_local_firewall_filter_status; then
      status_line "Docker port ${DOCKER_PUBLISH_PORT}" "OK" "DOCKER-USER private-network filter active"
    else
      status_line "Docker port ${DOCKER_PUBLISH_PORT}" "WARN" "Docker-aware filter not confirmed; UFW alone is insufficient"
    fi
  else
    for port in 8000 9000; do
      if ufw_port_has_allow "$port"; then
        status_line "Port ${port}" "OK" "allow rule present"
      else
        status_line "Port ${port}" "WARN" "no allow rule detected"
      fi
    done
  fi
  echo
  echo "Host-side tests:"
  print_host_dns_tests_for_site "$SITE_NAME" "$(get_vm_ip 2>/dev/null || echo unknown)"
  echo "============================================================"
}

repair_local_access() {
  require_sudo
  local port_label
  port_label="$(local_dev_direct_ports | paste -sd / -)"
  echo
  echo "============================================================"
  echo "Repair Local VM Access"
  echo "============================================================"
  echo "This restores local development access for the active deployment engine."
  status_line "Engine" "INFO" "$(deployment_engine_label)"
  status_line "Direct port(s)" "INFO" "$port_label"
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
  if deployment_engine_is_docker; then
    configure_docker_local_firewall_filter || warn "Docker published-port filter could not be confirmed."
  fi

  ui_box_start "Result Summary"
  if deployment_engine_is_docker; then
    status_line "Local access" "OK" "22/80/443 host rules plus Docker private-source forwarding filter restored"
  else
    status_line "Local access" "OK" "22/80/443 plus private ${port_label} rules restored"
  fi
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
  status_line "VM IP" "INFO" "$vm_ip"
  status_line "Domain" "INFO" "$domain"
  status_line "Engine" "INFO" "$(deployment_engine_label)"
  echo "Safe default: deny incoming; allow outgoing; allow 22/80/443."
  if is_public_vm_workflow; then
    if deployment_engine_is_docker; then
      echo "Production Docker: keep ${DOCKER_PUBLISH_PORT} loopback-only before HTTPS and unpublished after HTTPS; keep 8000/9000 container-internal."
    else
      echo "Production native: block direct 8000/9000 and internal Redis/database ports."
    fi
  else
    echo "Local development direct port(s): $(local_dev_direct_ports | paste -sd ', ' -) from private networks."
  fi
  ui_next "$(toolkit_cmd configure-vm-firewall)" "$(toolkit_cmd vm-firewall-status)"
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
  local status default_line port detail state
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
  status_line "Engine" "INFO" "$(deployment_engine_label)"
  if deployment_engine_is_docker; then
    if ! is_public_vm_workflow; then
      if docker_local_firewall_filter_status; then
        status_line "Docker forwarding filter" "OK" "DOCKER-USER restricts published port ${DOCKER_PUBLISH_PORT} to private sources"
      else
        status_line "Docker forwarding filter" "WARN" "not confirmed; Docker-published ports can bypass UFW"
      fi
    else
      status_line "Docker exposure policy" "INFO" "validated by Compose bindings / docker-production-exposure, not UFW alone"
    fi
  fi

  echo
  while IFS= read -r port; do
    [[ -n "$port" ]] || continue
    case "$port" in
      22|80|443)
        if ufw_port_has_allow "$port"; then
          state=OK
          detail="allow rule present"
        else
          state=WARN
          detail="no allow rule detected"
        fi
        ;;
      *)
        if is_public_vm_workflow; then
          if ufw_port_has_allow "$port"; then
            state=WARN
            detail="ALLOW rule present; should be blocked for production"
          elif ufw_port_has_deny "$port"; then
            state=OK
            detail="explicit deny rule present"
          else
            state=OK
            detail="not allowed; covered by default deny"
          fi
        else
          if ufw_port_has_allow "$port"; then
            state=OK
            detail="local/private access rule present"
          else
            state=WARN
            detail="no local access allow rule detected"
          fi
        fi
        ;;
    esac
    status_line "Port ${port}" "$state" "$detail"
  done < <(
    if is_public_vm_workflow; then
      printf '%s\n' 22 80 443
      # UFW rows describe host-network policy only. Docker's published frontend
      # port is reported above through the Compose exposure policy because UFW
      # is not authoritative for Docker forwarding.
      while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        if deployment_engine_is_docker && [[ "$port" == "${DOCKER_PUBLISH_PORT:-8080}" ]]; then
          continue
        fi
        printf '%s\n' "$port"
      done < <(production_block_ports)
    else
      printf '%s\n' 22 80 443
      if ! deployment_engine_is_docker; then
        local_dev_direct_ports
      fi
    fi | sort -un
  )

  echo
  echo "Raw UFW status:"
  ufw_status_raw | sed 's/^/  /'
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
