# shellcheck shell=bash
# Production and local SSL/HTTPS helpers.
[[ -n "${_ERPNEXT_DEV_SSL_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_SSL_LOADED=1

local_ssl_paths_for_site() {
  local site="$1" slug
  slug="$(printf '%s' "$site" | tr -c 'A-Za-z0-9._-' '-')"
  printf '%s\n' \
    "${SSL_NGINX_CONF_DIR}/sites-available/erpnext-dev-${slug}.conf" \
    "${SSL_NGINX_CONF_DIR}/sites-enabled/erpnext-dev-${slug}.conf" \
    "${SSL_CERT_DIR}/${site}.crt" \
    "${SSL_CERT_DIR}/${site}.key"
}

show_ssl_roadmap_guide() {
  cat <<EOF_SSL

============================================================
Future SSL / HTTPS Direction
============================================================

SSL is planned, but it should be added carefully because HTTPS changes
access from direct Bench :8000 to a reverse-proxy model.

Local developer SSL target:
  https://${SITE_NAME}

Planned local architecture:
  Browser HTTPS :443
    -> Nginx reverse proxy inside the VM
      -> Bench web on 127.0.0.1:8000
      -> Socket.io on 127.0.0.1:9000

Planned local SSL commands:
  Use /opt/erpnext-dev/erpnext-dev.sh after the one-command quickstart copies the toolkit there.
  /opt/erpnext-dev/erpnext-dev.sh ssl-status
  /opt/erpnext-dev/erpnext-dev.sh local-ssl-guide
  /opt/erpnext-dev/erpnext-dev.sh local-ssl-wizard
  /opt/erpnext-dev/erpnext-dev.sh mkcert-guide
  /opt/erpnext-dev/erpnext-dev.sh verify-local-ssl
  /opt/erpnext-dev/erpnext-dev.sh configure-local-ssl
  /opt/erpnext-dev/erpnext-dev.sh disable-local-ssl

Recommended local certificate direction:
  - Use mkcert or a local CA workflow.
  - Trust the local CA on the HOST browser machine.
  - Keep Redis and internal services private.

Production SSL should be a separate production track, not mixed into the
current developer bench-start workflow.

Future production SSL options:
  1) Let's Encrypt HTTP-01 for public DNS pointing to the server.
  2) Let's Encrypt DNS-01 with Cloudflare for Cloudflare-managed DNS.
  3) Cloudflare Origin CA for Cloudflare-proxied deployments.

Future production architecture should use:
  - Nginx
  - Supervisor or production systemd units
  - Firewall rules
  - Domain/DNS validation
  - SSL renewal checks
  - Backups and restore testing
  - Monitoring and update strategy

Recommended roadmap:
  v0.7.x  VM/networking and hostname foundation
  v0.8.x  Local HTTPS reverse proxy planning/implementation
  v0.9.x  Production planning branch
  v1.x    Stable developer toolkit
  prod    Separate production toolkit track

============================================================
EOF_SSL
}

show_production_ssl_guide() {
  cat <<EOF_PROD_SSL

============================================================
Production SSL Planning
============================================================

Future production SSL options:
  1) Let's Encrypt HTTP-01 for public DNS/server.
  2) Let's Encrypt DNS-01 for Cloudflare-managed DNS.
  3) Cloudflare Origin CA for Cloudflare-proxied sites.
  4) Manual certificate install for private datacenter SSL.

Production needs:
  - real domain
  - Nginx reverse proxy
  - port 80/443 plan
  - renewal checks
  - backup/restore testing

Current local SSL remains separate:
  /opt/erpnext-dev/erpnext-dev.sh configure-local-ssl
============================================================
EOF_PROD_SSL
}


is_private_ipv4() {
  local ip="$1"

  [[ -n "$ip" ]] || return 1
  case "$ip" in
    10.*|192.168.*|127.*|169.254.*) return 0 ;;
    172.16.*|172.17.*|172.18.*|172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|172.29.*|172.30.*|172.31.*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_ipv4_first() {
  local host="$1"

  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$host" 2>/dev/null | awk '{print $1; exit}'
    return 0
  fi

  if command -v dig >/dev/null 2>&1; then
    dig +short A "$host" 2>/dev/null | awk '/^[0-9.]+$/ {print; exit}'
    return 0
  fi

  echo ""
}

production_listener_detail() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -lntH "sport = :${port}" 2>/dev/null | awk 'NR==1 {print $4; found=1} END {if (!found) print "not listening"}'
    return 0
  fi

  if port_listens "$port"; then
    echo "listening"
  else
    echo "not listening"
  fi
}

production_listener_is_public() {
  local port="$1" detail
  detail="$(production_listener_detail "$port")"
  [[ "$detail" == *"0.0.0.0:"* || "$detail" == "*:"* || "$detail" == "*:${port}"* || "$detail" == *"[::]:"* ]]
}

production_listener_is_local_only() {
  local port="$1" detail
  detail="$(production_listener_detail "$port")"
  [[ "$detail" == *"127.0.0.1:"* || "$detail" == *"[::1]:"* ]]
}

production_listener_exposure_label() {
  local port="$1" detail
  detail="$(production_listener_detail "$port")"
  if [[ "$detail" == "not listening" ]]; then
    echo "OK|not listening"
  elif production_listener_is_local_only "$port" && ! production_listener_is_public "$port"; then
    echo "OK|local-only: ${detail}"
  elif production_listener_is_public "$port"; then
    echo "WARN|public interface: ${detail}"
  else
    echo "INFO|${detail}"
  fi
}

production_domain_status_for_provider() {
  local domain="$1" vm_ip="$2" dns_ip="$3" provider="$4"
  if [[ -z "$dns_ip" ]]; then
    echo "WARN|${domain}; DNS=unresolved; VM=${vm_ip}"
  elif [[ "$dns_ip" == "$vm_ip" ]]; then
    echo "OK|${domain}; DNS=${dns_ip}; VM=${vm_ip}"
  elif [[ "$provider" == "Cloudflare Origin CA" ]]; then
    echo "OK|${domain}; DNS=${dns_ip}; VM=${vm_ip}; Cloudflare proxy likely active"
  else
    echo "WARN|${domain}; DNS=${dns_ip}; VM=${vm_ip}"
  fi
}

production_cloudflare_proxy_hint() {
  local dns_ip="$1" vm_ip="$2" provider="$3"
  if [[ "$provider" == "Cloudflare Origin CA" && -n "$dns_ip" && "$dns_ip" != "$vm_ip" ]]; then
    echo "OK|DNS does not resolve directly to origin IP; Cloudflare proxy appears active"
  elif [[ "$provider" == "Cloudflare Origin CA" ]]; then
    echo "INFO|DNS resolves to origin IP; Cloudflare proxy may be DNS-only/grey-cloud"
  elif [[ -n "$dns_ip" && "$dns_ip" != "$vm_ip" ]]; then
    echo "INFO|DNS does not resolve directly to origin IP"
  else
    echo "INFO|DNS resolves directly to origin IP"
  fi
}

production_http_status() {
  local url="$1"
  curl -fsSI --max-time 8 "$url" 2>/dev/null | awk 'NR==1 {print; exit}' || true
}

show_public_vm_readiness() {
  local vm_ip domain dns_ip install_quick runtime service auto nginx_state ssl_pair ssl_status ssl_detail backup_count
  local http_ip http_domain public_note dns_status dns_detail active_provider domain_pair

  require_sudo

  vm_ip="$(get_vm_ip)"
  domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"
  dns_ip=""
  dns_status="WARN"
  dns_detail="set PRODUCTION_DOMAIN or SITE_NAME to the public hostname"
  public_note="private/NAT IP detected; this does not look like a public VM"

  if ! is_private_ipv4 "$vm_ip"; then
    public_note="public-looking IPv4 detected; confirm this is the intended cloud VM IP"
  fi

  active_provider="$(production_ssl_provider_from_cert_path "$(production_nginx_active_cert_path 2>/dev/null || true)")"
  if validate_production_domain_value "$domain" >/dev/null 2>&1; then
    dns_ip="$(resolve_ipv4_first "$domain")"
    domain_pair="$(production_domain_status_for_provider "$domain" "$vm_ip" "$dns_ip" "$active_provider")"
    dns_status="${domain_pair%%|*}"
    dns_detail="${domain_pair#*|}"
  fi

  install_quick="$(production_quick_install_state)"
  runtime="$(runtime_state 2>/dev/null || echo unknown)"
  service="$(service_state 2>/dev/null || echo unknown)"
  auto="$(autostart_state 2>/dev/null || echo unknown)"
  nginx_state="not installed"
  command -v nginx >/dev/null 2>&1 && nginx_state="installed"
  ssl_pair="$(production_ssl_readiness_detail)"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"
  backup_count="$(production_backup_count)"
  http_ip="$(production_http_status "http://${vm_ip}:8000")"
  http_domain="$(production_http_status "http://${domain}:8000")"

  echo
  echo "============================================================"
  echo "Public VM Readiness"
  echo "============================================================"
  status_line "Mode" "INFO" "planning/check only; no firewall or SSL changes are applied"
  status_line "VM IP" "INFO" "${vm_ip}"
  status_line "Network" "INFO" "$public_note"
  status_line "Domain" "$dns_status" "$dns_detail"
  status_line "Install state" "$([[ "$install_quick" == Installed* ]] && echo OK || echo WARN)" "$install_quick"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo WARN)" "$runtime"
  status_line "Service" "INFO" "${service}; autostart=${auto}"
  status_line "Nginx" "$([[ "$nginx_state" == installed ]] && echo OK || echo WARN)" "$nginx_state"
  status_line "Production SSL" "$ssl_status" "$ssl_detail"
  if [[ "$backup_count" =~ ^[0-9]+$ && "$backup_count" -gt 0 ]]; then
    status_line "Backup readiness" "OK" "${backup_count} local backup file(s); off-VM copy still required"
  else
    status_line "Backup readiness" "WARN" "no local backup files detected"
  fi

  echo
  echo "HTTP checks:"
  status_line "Public IP :8000" "$([[ "$http_ip" == HTTP/* ]] && echo OK || echo WARN)" "${http_ip:-no response}"
  status_line "Domain :8000" "$([[ "$http_domain" == HTTP/* ]] && echo OK || echo WARN)" "${http_domain:-no response}"

  echo
  echo "Listener summary:"
  for port in 22 80 443 8000 9000 11000 13000; do
    status_line "Port ${port}" "INFO" "$(production_listener_detail "$port")"
  done

  echo
  echo "Recommended next commands:"
  echo "  $(toolkit_cmd backup-files)"
  echo "  $(toolkit_cmd production-ssl-plan)"
  echo "  $(toolkit_cmd production-ssl-wizard)"
  echo "  $(toolkit_cmd ssl-mode-status)"
  echo "  $(toolkit_cmd setup-effort-guide)"
  echo "  $(toolkit_cmd configure-production-ssl)"
  echo "  $(toolkit_cmd configure-cloudflare-origin-ssl)"
  echo "  $(toolkit_cmd production-ssl-status)"
  echo "  $(toolkit_cmd production-firewall-plan)"
  echo "  $(toolkit_cmd firewall-hardening-status)"
  echo "  $(toolkit_cmd support-bundle)"
  echo "============================================================"
}

show_production_ssl_plan() {
  local vm_ip domain dns_ip dns_state dns_detail nginx_state local_ssl_pair local_ssl_status local_ssl_detail port80 port443

  require_sudo

  vm_ip="$(get_vm_ip)"
  domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"
  dns_ip=""
  dns_state="WARN"
  dns_detail="set PRODUCTION_DOMAIN=erp.company.com before production SSL planning"

  if ! validate_production_domain_value "$domain" >/dev/null 2>&1; then
    domain="erp.company.com"
  else
    dns_ip="$(resolve_ipv4_first "$domain")"
    if [[ -n "$dns_ip" && "$dns_ip" == "$vm_ip" ]]; then
      dns_state="OK"
      dns_detail="${domain} resolves to ${vm_ip}"
    elif [[ -n "$dns_ip" ]]; then
      dns_detail="${domain} resolves to ${dns_ip}, expected ${vm_ip}"
    else
      dns_detail="${domain} did not resolve yet from this VM"
    fi
  fi

  nginx_state="not installed"
  command -v nginx >/dev/null 2>&1 && nginx_state="installed"
  local_ssl_pair="$(production_ssl_readiness_detail)"
  local_ssl_status="${local_ssl_pair%%|*}"
  local_ssl_detail="${local_ssl_pair#*|}"
  port80="$(production_listener_detail 80)"
  port443="$(production_listener_detail 443)"

  echo
  echo "============================================================"
  echo "Production SSL Plan"
  echo "============================================================"
  status_line "Mode" "INFO" "planning only; no certificate or Nginx changes are applied"
  status_line "Domain" "$dns_state" "$dns_detail"
  status_line "VM IP" "INFO" "$vm_ip"
  status_line "Nginx" "$([[ "$nginx_state" == installed ]] && echo OK || echo WARN)" "$nginx_state"
  status_line "Port 80" "INFO" "$port80"
  status_line "Port 443" "INFO" "$port443"
  status_line "Current SSL" "$local_ssl_status" "$local_ssl_detail"
  echo
  echo "Recommended SSL path for this public VM:"
  echo "  1) Keep Cloudflare DNS-only while issuing/testing the certificate."
  echo "  2) Point A record ${domain} -> ${vm_ip}."
  echo "  3) Use Let's Encrypt for https://${domain}."
  echo "  4) Put ERPNext behind Nginx on ports 80/443."
  echo "  5) After HTTPS is working, close/restrict public :8000."
  echo
  echo "Do not use for final production SSL:"
  echo "  - mkcert certificates"
  echo "  - self-signed local certificates"
  echo "  - browser-trusted dev certificates copied from your workstation"
  echo
  echo "Cloudflare choices:"
  echo "  - DNS-only: best for first Let's Encrypt HTTP-01 test."
  echo "  - Proxied/orange-cloud: useful later; requires SSL mode planning."
  echo "  - Cloudflare Origin CA: only valid when Cloudflare proxy stays enabled."
  echo
  echo "Manual validation commands:"
  echo "  curl -I http://${domain}:8000"
  echo "  curl -I http://${domain}"
  echo "  curl -Ik https://${domain}"
  echo
  echo "Related commands:"
  echo "  $(toolkit_cmd production-ssl-wizard)"
  echo "  $(toolkit_cmd configure-production-ssl)"
  echo "  $(toolkit_cmd configure-cloudflare-origin-ssl)"
  echo "  $(toolkit_cmd production-ssl-status)"
  echo "  $(toolkit_cmd production-firewall-plan)"
  echo "  $(toolkit_cmd public-vm-readiness)"
  echo "  $(toolkit_cmd production-ssl-guide)"
  echo "============================================================"
}

production_ssl_domain() {
  local domain="${PRODUCTION_DOMAIN:-$SITE_NAME}"
  if validate_production_domain_value "$domain" >/dev/null 2>&1; then
    printf '%s\n' "$domain"
    return 0
  fi
  return 1
}

production_ssl_site_slug() {
  local domain
  domain="$(production_ssl_domain 2>/dev/null || echo "$SITE_NAME")"
  printf '%s' "$domain" | tr -c 'A-Za-z0-9._-' '-'
}

production_nginx_site_name() {
  echo "erpnext-production-$(production_ssl_site_slug)"
}

production_nginx_available_path() {
  echo "/etc/nginx/sites-available/$(production_nginx_site_name).conf"
}

production_nginx_enabled_path() {
  echo "/etc/nginx/sites-enabled/$(production_nginx_site_name).conf"
}

production_letsencrypt_live_dir() {
  local domain
  domain="$(production_ssl_domain)" || return 1
  echo "/etc/letsencrypt/live/${domain}"
}

production_letsencrypt_fullchain_path() {
  echo "$(production_letsencrypt_live_dir)/fullchain.pem"
}

production_letsencrypt_key_path() {
  echo "$(production_letsencrypt_live_dir)/privkey.pem"
}


cloudflare_origin_dir() {
  echo "$CLOUDFLARE_ORIGIN_DIR"
}

cloudflare_origin_cert_path() {
  local domain
  domain="$(production_ssl_domain)" || return 1
  echo "$(cloudflare_origin_dir)/${domain}.pem"
}

cloudflare_origin_key_path() {
  local domain
  domain="$(production_ssl_domain)" || return 1
  echo "$(cloudflare_origin_dir)/${domain}.key"
}

production_nginx_active_cert_path() {
  local enabled_path
  enabled_path="$(production_nginx_enabled_path)"
  [[ -r "$enabled_path" ]] || return 1
  awk '/^[[:space:]]*ssl_certificate[[:space:]]+/ && $1 == "ssl_certificate" {gsub(";", "", $2); print $2; exit}' "$enabled_path" 2>/dev/null
}

production_nginx_active_key_path() {
  local enabled_path
  enabled_path="$(production_nginx_enabled_path)"
  [[ -r "$enabled_path" ]] || return 1
  awk '/^[[:space:]]*ssl_certificate_key[[:space:]]+/ {gsub(";", "", $2); print $2; exit}' "$enabled_path" 2>/dev/null
}

production_ssl_provider_from_cert_path() {
  local cert_path="${1:-}"
  case "$cert_path" in
    /etc/letsencrypt/live/*) echo "Let's Encrypt" ;;
    /etc/ssl/cloudflare-origin/*|*cloudflare-origin*) echo "Cloudflare Origin CA" ;;
    "") echo "not configured" ;;
    *) echo "custom/origin certificate" ;;
  esac
}

active_production_ssl_provider() {
  local active_cert
  active_cert="$(production_nginx_active_cert_path 2>/dev/null || true)"
  production_ssl_provider_from_cert_path "$active_cert"
}

production_ssl_overall_status() {
  production_ssl_runtime_detail
}

certificate_issuer_for_file() {
  local cert_path="$1"
  [[ -n "$cert_path" && -f "$cert_path" ]] || return 1
  openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null | sed 's/^issuer=//' || return 1
}

certificate_subject_for_file() {
  local cert_path="$1"
  [[ -n "$cert_path" && -f "$cert_path" ]] || return 1
  openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed 's/^subject=//' || return 1
}

certificate_dates_for_file() {
  local cert_path="$1"
  [[ -n "$cert_path" && -f "$cert_path" ]] || return 1
  openssl x509 -in "$cert_path" -noout -dates 2>/dev/null | paste -sd '; ' - || return 1
}

certificate_detail_for_file() {
  local cert_path="$1" provider issuer dates subject
  provider="$(production_ssl_provider_from_cert_path "$cert_path")"
  issuer="$(certificate_issuer_for_file "$cert_path" 2>/dev/null || true)"
  subject="$(certificate_subject_for_file "$cert_path" 2>/dev/null || true)"
  dates="$(certificate_dates_for_file "$cert_path" 2>/dev/null || true)"
  if [[ -z "$issuer" ]]; then
    echo "missing or unreadable"
  elif [[ "$issuer" == *STAGING* || "$issuer" == *staging* ]]; then
    echo "${provider}; STAGING certificate; issuer=${issuer}; subject=${subject}; ${dates}"
  else
    echo "${provider}; issuer=${issuer}; subject=${subject}; ${dates}"
  fi
}

certificate_file_is_staging() {
  local cert_path="$1" issuer
  issuer="$(certificate_issuer_for_file "$cert_path" 2>/dev/null || true)"
  [[ "$issuer" == *STAGING* || "$issuer" == *staging* ]]
}

validate_certificate_and_key_pair() {
  local cert_path="$1" key_path="$2" cert_pub key_pub
  openssl x509 -in "$cert_path" -noout >/dev/null 2>&1 || return 1
  openssl pkey -in "$key_path" -noout >/dev/null 2>&1 || return 1
  cert_pub="$(openssl x509 -in "$cert_path" -pubkey -noout 2>/dev/null | openssl sha256 2>/dev/null | awk '{print $2}')"
  key_pub="$(openssl pkey -in "$key_path" -pubout 2>/dev/null | openssl sha256 2>/dev/null | awk '{print $2}')"
  [[ -n "$cert_pub" && -n "$key_pub" && "$cert_pub" == "$key_pub" ]]
}

read_pem_block_to_file() {
  local label="$1" begin_regex="$2" end_regex="$3" output_file="$4" begin_hint="${5:-$2}" end_hint="${6:-$3}"
  local line had_tty=0 in_block=0 found_begin=0 found_end=0

  echo
  echo "Paste the ${label} PEM block now."
  echo "The toolkit will stop reading automatically when it sees the real PEM ending line."
  echo "Input is hidden while you paste. Nothing is printed to the toolkit log."
  echo
  echo "Expected first line: ${begin_hint}"
  echo "Expected ending:     ${end_hint}"

  : > "$output_file"
  chmod 600 "$output_file" 2>/dev/null || true

  if [[ -t 0 ]]; then
    had_tty=1
    stty -echo 2>/dev/null || true
  fi

  while IFS= read -r line; do
    line="${line%$'
'}"

    if [[ "$in_block" -eq 0 ]]; then
      if [[ "$line" =~ $begin_regex ]]; then
        in_block=1
        found_begin=1
        printf '%s
' "$line" >> "$output_file"
      fi
      continue
    fi

    printf '%s
' "$line" >> "$output_file"

    if [[ "$line" =~ $end_regex ]]; then
      found_end=1
      break
    fi
  done

  if [[ "$had_tty" -eq 1 ]]; then
    stty echo 2>/dev/null || true
    echo
  fi

  if [[ "$found_begin" -ne 1 ]]; then
    rm -f "$output_file"
    fail "Did not detect the beginning of the ${label} PEM block."
  fi

  if [[ "$found_end" -ne 1 ]]; then
    rm -f "$output_file"
    fail "Did not detect the ending line of the ${label} PEM block."
  fi
}


production_https_status() {
  local domain="$1"
  curl -fsSI --max-time 10 "https://${domain}/" 2>/dev/null | awk 'NR==1 {print; exit}' || true
}

production_http_status_plain() {
  local domain="$1"
  curl -fsSI --max-time 10 "http://${domain}/" 2>/dev/null | awk 'NR==1 {print; exit}' || true
}

production_certificate_issuer() {
  local fullchain
  fullchain="$(production_letsencrypt_fullchain_path 2>/dev/null || true)"
  certificate_issuer_for_file "$fullchain"
}

production_certificate_dates() {
  local fullchain
  fullchain="$(production_letsencrypt_fullchain_path 2>/dev/null || true)"
  certificate_dates_for_file "$fullchain"
}

production_certificate_is_staging() {
  local issuer
  issuer="$(production_certificate_issuer 2>/dev/null || true)"
  [[ "$issuer" == *STAGING* || "$issuer" == *staging* ]]
}

production_certificate_detail() {
  local issuer dates
  issuer="$(production_certificate_issuer 2>/dev/null || true)"
  dates="$(production_certificate_dates 2>/dev/null || true)"
  if [[ -z "$issuer" ]]; then
    echo "missing or unreadable"
  elif [[ "$issuer" == *STAGING* || "$issuer" == *staging* ]]; then
    echo "STAGING certificate; issuer=${issuer}; ${dates}"
  else
    echo "production/trusted issuer likely; issuer=${issuer}; ${dates}"
  fi
}

production_ssl_runtime_detail() {
  local domain active_cert active_key fullchain enabled_path https_head provider
  domain="$(production_ssl_domain 2>/dev/null || true)"
  if [[ -z "$domain" ]]; then
    echo "WARN|no valid production domain set"
    return 0
  fi

  fullchain="$(production_letsencrypt_fullchain_path 2>/dev/null || true)"
  enabled_path="$(production_nginx_enabled_path)"
  active_cert="$(production_nginx_active_cert_path 2>/dev/null || true)"
  active_key="$(production_nginx_active_key_path 2>/dev/null || true)"
  provider="$(production_ssl_provider_from_cert_path "$active_cert")"

  if [[ -n "$active_cert" && -n "$active_key" && -f "$active_cert" && -f "$active_key" && ( -L "$enabled_path" || -f "$enabled_path" ) ]]; then
    if certificate_file_is_staging "$active_cert"; then
      echo "WARN|${provider} staging certificate is installed; replace with production certificate before trusting HTTPS"
      return 0
    fi
    https_head="$(production_https_status "$domain")"
    if [[ "$https_head" == HTTP/* ]]; then
      echo "OK|${provider}/Nginx HTTPS responding: ${https_head}"
    elif [[ "$provider" == "Cloudflare Origin CA" ]]; then
      echo "WARN|Cloudflare Origin CA is installed, but trusted HTTPS did not respond. If DNS is grey-cloud/DNS-only, this is expected; switch Cloudflare proxy on and use Full (strict)."
    else
      echo "WARN|certificate/config present, but HTTPS did not respond"
    fi
  elif [[ -f "$fullchain" ]]; then
    echo "WARN|Let's Encrypt certificate exists, but production Nginx site is not enabled"
  elif command -v nginx >/dev/null 2>&1; then
    echo "WARN|Nginx installed, but no production HTTPS certificate is configured"
  else
    echo "WARN|not configured for production"
  fi
}

write_production_nginx_config() {
  local mode="$1" domain available_path webroot fullchain key cert_provider ssl_block redirect_block
  domain="$(production_ssl_domain)" || return 1
  available_path="$(production_nginx_available_path)"
  webroot="$PRODUCTION_SSL_WEBROOT"
  fullchain="${2:-$(production_letsencrypt_fullchain_path)}"
  key="${3:-$(production_letsencrypt_key_path)}"
  cert_provider="${4:-}"
  [[ -n "$cert_provider" ]] || cert_provider="Let's Encrypt"

  $SUDO mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled "$webroot/.well-known/acme-challenge"
  $SUDO chown -R root:root "$webroot"
  $SUDO chmod -R 755 "$webroot"

  if [[ "$mode" == "https" ]]; then
    ssl_block="
server {
    listen 443 ssl;
    server_name ${domain};

    ssl_certificate     ${fullchain};
    ssl_certificate_key ${key};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    client_max_body_size 100m;

    proxy_read_timeout 120s;
    proxy_send_timeout 120s;

    location /socket.io {
        proxy_pass http://127.0.0.1:9000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;
    }
}
"
    redirect_block="return 301 https://\$host\$request_uri;"
  else
    ssl_block=""
    redirect_block="proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;"
  fi

  $SUDO tee "$available_path" >/dev/null <<EOF_PROD_NGINX
# Managed by ERPNext Developer Toolkit.
# Production HTTPS reverse proxy for ${domain}.
# Certificate provider: ${cert_provider}.
# ERPNext Bench remains on localhost :8000/:9000 behind Nginx.

server {
    listen 80;
    server_name ${domain};

    location ^~ /.well-known/acme-challenge/ {
        root ${webroot};
        default_type "text/plain";
        try_files \$uri =404;
    }

    location /socket.io {
        proxy_pass http://127.0.0.1:9000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }

    location / {
        ${redirect_block}
    }
}
${ssl_block}
EOF_PROD_NGINX
}

show_production_ssl_status() {
  local domain vm_ip dns_ip nginx_state certbot_state cert_state cert_detail cert_line_status enabled_state http_head https_head ssl_pair ssl_status ssl_detail
  local active_cert active_key provider

  require_sudo
  vm_ip="$(get_vm_ip)"
  domain="$(production_ssl_domain 2>/dev/null || echo "${PRODUCTION_DOMAIN:-$SITE_NAME}")"
  dns_ip="$(resolve_ipv4_first "$domain")"
  nginx_state="not installed"
  command -v nginx >/dev/null 2>&1 && nginx_state="installed: $(nginx -v 2>&1 | sed 's/^nginx version: //')"
  certbot_state="not installed"
  command -v certbot >/dev/null 2>&1 && certbot_state="installed: $(certbot --version 2>&1 | head -n 1)"
  active_cert="$(production_nginx_active_cert_path 2>/dev/null || true)"
  active_key="$(production_nginx_active_key_path 2>/dev/null || true)"
  provider="$(production_ssl_provider_from_cert_path "$active_cert")"
  cert_state="missing"
  cert_detail="missing"
  cert_line_status="WARN"
  if [[ -n "$active_cert" && -f "$active_cert" ]]; then
    cert_state="active: ${active_cert}"
    cert_detail="$(certificate_detail_for_file "$active_cert" 2>/dev/null || echo 'present, but issuer could not be read')"
    if certificate_file_is_staging "$active_cert"; then
      cert_line_status="WARN"
    else
      cert_line_status="OK"
    fi
  elif production_ssl_domain >/dev/null 2>&1 && [[ -f "$(production_letsencrypt_fullchain_path 2>/dev/null || true)" ]]; then
    cert_state="present: $(production_letsencrypt_fullchain_path)"
    cert_detail="$(production_certificate_detail 2>/dev/null || echo 'present, but issuer could not be read')"
    if production_certificate_is_staging; then cert_line_status="WARN"; else cert_line_status="OK"; fi
  fi
  enabled_state="not enabled"
  if [[ -L "$(production_nginx_enabled_path)" || -f "$(production_nginx_enabled_path)" ]]; then
    enabled_state="enabled: $(production_nginx_enabled_path)"
  fi
  http_head="$(production_http_status_plain "$domain")"
  https_head="$(production_https_status "$domain")"
  ssl_pair="$(production_ssl_runtime_detail)"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"

  echo
  echo "============================================================"
  echo "Production SSL Status"
  echo "============================================================"
  local domain_pair domain_status domain_detail
  domain_pair="$(production_domain_status_for_provider "$domain" "$vm_ip" "$dns_ip" "$provider")"
  domain_status="${domain_pair%%|*}"
  domain_detail="${domain_pair#*|}"
  status_line "Domain" "$domain_status" "$domain_detail"
  status_line "Provider" "$([[ "$provider" != "not configured" ]] && echo OK || echo WARN)" "$provider"
  status_line "Nginx" "$([[ "$nginx_state" == installed* ]] && echo OK || echo WARN)" "$nginx_state"
  status_line "Certbot" "$([[ "$certbot_state" == installed* ]] && echo OK || echo INFO)" "$certbot_state"
  status_line "Certificate" "$cert_line_status" "$cert_state"
  status_line "Certificate issuer" "$cert_line_status" "$cert_detail"
  status_line "Certificate key" "$([[ -n "$active_key" && -f "$active_key" ]] && echo OK || echo WARN)" "${active_key:-missing}"
  status_line "Nginx site" "$([[ "$enabled_state" == enabled* ]] && echo OK || echo WARN)" "$enabled_state"
  status_line "Port 80" "INFO" "$(production_listener_detail 80)"
  status_line "Port 443" "INFO" "$(production_listener_detail 443)"
  status_line "HTTP" "$([[ "$http_head" == HTTP/* ]] && echo OK || echo WARN)" "${http_head:-no response}"
  status_line "HTTPS" "$([[ "$https_head" == HTTP/* ]] && echo OK || echo WARN)" "${https_head:-no response}"
  status_line "Overall" "$ssl_status" "$ssl_detail"
  echo
  echo "Useful tests:"
  echo "  curl -I http://${domain}"
  echo "  curl -I https://${domain}"
  echo "  $(toolkit_cmd public-vm-readiness)"
  echo "============================================================"
}

configure_production_ssl() {
  require_erpnext_vm_context "configure-production-ssl" || return 1
  require_sudo

  local domain vm_ip dns_ip install_quick runtime backup_count email_args staging_args force_renewal_args http_head https_head existing_cert_detail
  domain="$(production_ssl_domain 2>/dev/null || true)"
  [[ -n "$domain" ]] || fail "Set a valid PRODUCTION_DOMAIN or SITE_NAME, for example: $(toolkit_cmd_env "PRODUCTION_DOMAIN=erp.flowmaya.com SITE_NAME=erp.flowmaya.com" configure-production-ssl)"

  vm_ip="$(get_vm_ip)"
  dns_ip="$(resolve_ipv4_first "$domain")"
  install_quick="$(production_quick_install_state)"
  runtime="$(runtime_state 2>/dev/null || echo Stopped)"
  backup_count="$(production_backup_count)"

  echo
  echo "============================================================"
  echo "Configure Production HTTPS / Let's Encrypt"
  echo "============================================================"
  echo "This configures Nginx + Let's Encrypt for: https://${domain}"
  echo "It does not change cloud firewall rules and does not stop the ERPNext service."
  echo
  status_line "Domain" "$([[ -n "$dns_ip" && "$dns_ip" == "$vm_ip" ]] && echo OK || echo FAIL)" "${domain}; DNS=${dns_ip:-unresolved}; VM=${vm_ip}"
  status_line "Install state" "$([[ "$install_quick" == Installed* ]] && echo OK || echo FAIL)" "$install_quick"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo FAIL)" "$runtime"
  if [[ "$backup_count" =~ ^[0-9]+$ && "$backup_count" -gt 0 ]]; then
    status_line "Backup" "OK" "${backup_count} local backup file(s) found; off-VM copy still recommended"
  else
    status_line "Backup" "WARN" "no local backup detected; create one before production changes"
  fi
  status_line "Port 80" "INFO" "$(production_listener_detail 80)"
  status_line "Port 443" "INFO" "$(production_listener_detail 443)"
  if [[ -f "$(production_letsencrypt_fullchain_path 2>/dev/null || true)" ]]; then
    existing_cert_detail="$(production_certificate_detail 2>/dev/null || echo 'present, but issuer could not be read')"
    if production_certificate_is_staging; then
      status_line "Existing cert" "WARN" "$existing_cert_detail"
    else
      status_line "Existing cert" "OK" "$existing_cert_detail"
    fi
  else
    status_line "Existing cert" "INFO" "none"
  fi
  echo

  [[ -n "$dns_ip" && "$dns_ip" == "$vm_ip" ]] || fail "DNS for ${domain} must resolve to ${vm_ip} before issuing Let's Encrypt. Use DNS-only first if behind Cloudflare."
  [[ "$install_quick" == Installed* ]] || fail "ERPNext is not fully installed. Run guided setup first."
  [[ "$runtime" == Running* ]] || fail "ERPNext is not running. Start it first: $(toolkit_cmd start)"

  if [[ "$backup_count" =~ ^[0-9]+$ && "$backup_count" -eq 0 ]]; then
    warn "No local backup detected. Recommended: $(toolkit_cmd backup-files)"
  fi

  if [[ "$ASSUME_YES" -ne 1 ]]; then
    echo "Before continuing, confirm you already took a snapshot or are ready to change Nginx/SSL."
    confirm "Configure production HTTPS for ${domain} now?" || return 1
  fi

  log "Installing Nginx and Certbot"
  $SUDO apt-get update
  $SUDO apt-get install -y nginx certbot

  # Disable the default site to avoid accidental default landing pages on the production domain.
  if [[ -L /etc/nginx/sites-enabled/default || -f /etc/nginx/sites-enabled/default ]]; then
    $SUDO rm -f /etc/nginx/sites-enabled/default
  fi

  log "Writing temporary HTTP reverse proxy for ACME challenge"
  write_production_nginx_config http
  $SUDO ln -sfn "$(production_nginx_available_path)" "$(production_nginx_enabled_path)"

  log "Testing and starting Nginx"
  $SUDO nginx -t || fail "Nginx config test failed before certificate issuance."
  $SUDO systemctl enable --now nginx
  $SUDO systemctl reload nginx

  http_head="$(production_http_status_plain "$domain")"
  if [[ "$http_head" != HTTP/* ]]; then
    warn "HTTP check did not return a response before ACME: ${http_head:-no response}"
    warn "If port 80 is blocked at the cloud firewall, Let's Encrypt HTTP-01 will fail."
  fi

  email_args=(--register-unsafely-without-email)
  if [[ -n "$LETSENCRYPT_EMAIL" ]]; then
    email_args=(--email "$LETSENCRYPT_EMAIL")
  fi
  staging_args=()
  force_renewal_args=()
  if [[ "$LETSENCRYPT_STAGING" == "true" ]]; then
    staging_args=(--staging)
  elif production_certificate_is_staging; then
    warn "Existing Let's Encrypt staging certificate detected. Forcing replacement with a production certificate."
    force_renewal_args=(--force-renewal)
  fi

  log "Requesting Let's Encrypt certificate"
  $SUDO certbot certonly \
    --non-interactive \
    --agree-tos \
    "${email_args[@]}" \
    "${staging_args[@]}" \
    "${force_renewal_args[@]}" \
    --webroot \
    -w "$PRODUCTION_SSL_WEBROOT" \
    -d "$domain" || fail "Let's Encrypt certificate request failed. Check DNS, Cloudflare DNS-only/proxy status, and port 80 firewall."

  if [[ "$LETSENCRYPT_STAGING" != "true" ]] && production_certificate_is_staging; then
    fail "A staging certificate is still installed after the production request. Check /var/log/letsencrypt/letsencrypt.log and rerun with --force-renewal manually if needed."
  fi

  log "Writing HTTPS reverse proxy config"
  write_production_nginx_config https

  log "Testing and reloading Nginx"
  $SUDO nginx -t || fail "Nginx config test failed after certificate issuance."
  $SUDO systemctl reload nginx

  https_head="$(production_https_status "$domain")"
  if [[ "$https_head" == HTTP/* ]]; then
    ok "Production HTTPS is responding: ${https_head}"
  else
    warn "Certificate and Nginx config were installed, but HTTPS did not respond from this VM."
  fi

  echo
  echo "Next steps:"
  echo "  curl -I https://${domain}"
  echo "  $(toolkit_cmd production-ssl-status)"
  echo "  $(toolkit_cmd production-firewall-plan)"
  echo
  echo "After HTTPS works, restrict/close public :8000 and :9000 at the cloud firewall."
  echo "============================================================"
}


show_cloudflare_origin_guide() {
  local domain vm_ip
  vm_ip="$(get_vm_ip)"
  domain="$(production_ssl_domain 2>/dev/null || echo "${PRODUCTION_DOMAIN:-$SITE_NAME}")"
  echo
  echo "============================================================"
  echo "Cloudflare Origin CA Guide"
  echo "============================================================"
  echo "Use this path when Cloudflare will stay proxied/orange-cloud."
  echo
  echo "Cloudflare dashboard steps:"
  echo "  1) SSL/TLS -> Origin Server -> Create Certificate."
  echo "  2) Hostname: ${domain}"
  echo "  3) Key type: RSA or ECC."
  echo "  4) Save both the Origin Certificate and Private Key. Cloudflare shows the private key only once."
  echo "     Certificate must include -----BEGIN CERTIFICATE----- through -----END CERTIFICATE-----."
  echo "     Private key must include -----BEGIN PRIVATE KEY----- through -----END PRIVATE KEY-----."
  echo "  5) Keep DNS record ${domain} pointed to ${vm_ip}."
  echo "  6) After installing the origin cert here, turn proxy ON/orange-cloud."
  echo "  7) Set SSL/TLS encryption mode to Full (strict)."
  echo
  echo "Toolkit commands:"
  echo "  $(toolkit_cmd production-ssl-wizard)"
  echo "  $(toolkit_cmd configure-cloudflare-origin-ssl)"
  echo "  $(toolkit_cmd cloudflare-origin-ssl-status)"
  echo
  echo "Important: Cloudflare Origin CA certificates are trusted by Cloudflare, not by browsers directly."
  echo "With DNS-only/grey-cloud, direct curl/browser checks may show a certificate trust warning."
  echo "============================================================"
}

install_cloudflare_origin_material() {
  local domain tmp_dir tmp_cert tmp_key src_cert src_key dest_dir dest_cert dest_key cert_status key_status
  domain="$(production_ssl_domain)" || return 1
  tmp_dir="$(mktemp -d)"
  tmp_cert="${tmp_dir}/cloudflare-origin.pem"
  tmp_key="${tmp_dir}/cloudflare-origin.key"

  if [[ -n "$CLOUDFLARE_ORIGIN_CERT_FILE" && -n "$CLOUDFLARE_ORIGIN_KEY_FILE" ]]; then
    src_cert="$CLOUDFLARE_ORIGIN_CERT_FILE"
    src_key="$CLOUDFLARE_ORIGIN_KEY_FILE"
    [[ -f "$src_cert" ]] || fail "CLOUDFLARE_ORIGIN_CERT_FILE not found: ${src_cert}"
    [[ -f "$src_key" ]] || fail "CLOUDFLARE_ORIGIN_KEY_FILE not found: ${src_key}"
    cp "$src_cert" "$tmp_cert"
    cp "$src_key" "$tmp_key"
  else
    echo
    echo "Cloudflare should have shown you two PEM blocks:"
    echo "  - Origin Certificate"
    echo "  - Private Key"
    echo
    confirm "Have you generated and copied both values from Cloudflare Origin Server?" || return 1
    read_pem_block_to_file "Cloudflare Origin Certificate" '^-----BEGIN CERTIFICATE-----$' '^-----END CERTIFICATE-----$' "$tmp_cert" '-----BEGIN CERTIFICATE-----' '-----END CERTIFICATE-----'
    read_pem_block_to_file "Cloudflare Origin Private Key" '^-----BEGIN (RSA |EC )?PRIVATE KEY-----$' '^-----END (RSA |EC )?PRIVATE KEY-----$' "$tmp_key" '-----BEGIN PRIVATE KEY-----' '-----END PRIVATE KEY-----'
  fi

  validate_certificate_and_key_pair "$tmp_cert" "$tmp_key" || fail "Cloudflare origin certificate/key validation failed. Confirm the private key matches the certificate."

  dest_dir="$(cloudflare_origin_dir)"
  dest_cert="$(cloudflare_origin_cert_path)"
  dest_key="$(cloudflare_origin_key_path)"
  $SUDO mkdir -p "$dest_dir"
  $SUDO install -m 0644 -o root -g root "$tmp_cert" "$dest_cert"
  $SUDO install -m 0600 -o root -g root "$tmp_key" "$dest_key"
  rm -rf "$tmp_dir"

  cert_status="$(certificate_detail_for_file "$dest_cert" 2>/dev/null || echo 'installed')"
  key_status="private key installed with mode 0600"
  ok "Cloudflare Origin certificate installed: ${dest_cert}"
  ok "${key_status}"
  status_line "Certificate detail" "INFO" "$cert_status"
}

configure_cloudflare_origin_ssl() {
  require_erpnext_vm_context "configure-cloudflare-origin-ssl" || return 1
  require_sudo

  local domain vm_ip dns_ip install_quick runtime backup_count available_path backup_path https_head provider cert_path key_path
  domain="$(production_ssl_domain 2>/dev/null || true)"
  [[ -n "$domain" ]] || fail "Set PRODUCTION_DOMAIN and SITE_NAME, for example: $(toolkit_cmd_env "SITE_NAME=erp.flowmaya.com PRODUCTION_DOMAIN=erp.flowmaya.com" configure-cloudflare-origin-ssl)"
  vm_ip="$(get_vm_ip)"
  dns_ip="$(resolve_ipv4_first "$domain")"
  install_quick="$(production_quick_install_state)"
  runtime="$(runtime_state 2>/dev/null || echo Stopped)"
  backup_count="$(production_backup_count)"

  echo
  echo "============================================================"
  echo "Configure Cloudflare Origin CA HTTPS"
  echo "============================================================"
  echo "This installs a Cloudflare Origin CA certificate and configures Nginx for ${domain}."
  echo "It does not change Cloudflare DNS/proxy settings and does not change cloud firewall rules."
  echo
  status_line "Domain" "$([[ -n "$dns_ip" ]] && echo OK || echo WARN)" "${domain}; DNS=${dns_ip:-unresolved}; VM=${vm_ip}"
  status_line "Install state" "$([[ "$install_quick" == Installed* ]] && echo OK || echo FAIL)" "$install_quick"
  status_line "Runtime" "$([[ "$runtime" == Running* ]] && echo OK || echo FAIL)" "$runtime"
  if [[ "$backup_count" =~ ^[0-9]+$ && "$backup_count" -gt 0 ]]; then
    status_line "Backup" "OK" "${backup_count} local backup file(s) found; off-VM copy still recommended"
  else
    status_line "Backup" "WARN" "no local backup detected; create one before production changes"
  fi
  status_line "Current SSL" "INFO" "$(production_ssl_runtime_detail | cut -d'|' -f2-)"
  echo
  echo "Recommended Cloudflare settings after this command succeeds:"
  echo "  DNS record ${domain}: Proxied / orange-cloud"
  echo "  SSL/TLS encryption mode: Full (strict)"
  echo

  [[ "$install_quick" == Installed* ]] || fail "ERPNext is not fully installed. Run guided setup first."
  [[ "$runtime" == Running* ]] || fail "ERPNext is not running. Start it first: $(toolkit_cmd start)"

  if [[ "$ASSUME_YES" -ne 1 ]]; then
    echo "Before continuing, confirm you have a snapshot and the Cloudflare Origin certificate/private key."
    confirm "Configure Cloudflare Origin CA SSL for ${domain} now?" || return 1
  fi

  log "Installing Nginx if needed"
  $SUDO apt-get update
  $SUDO apt-get install -y nginx

  install_cloudflare_origin_material
  cert_path="$(cloudflare_origin_cert_path)"
  key_path="$(cloudflare_origin_key_path)"

  available_path="$(production_nginx_available_path)"
  if [[ -f "$available_path" ]]; then
    backup_path="${available_path}.bak-$(date +%Y%m%d-%H%M%S)"
    $SUDO cp -a "$available_path" "$backup_path"
    ok "Existing production Nginx config backed up: ${backup_path}"
  fi

  if [[ -L /etc/nginx/sites-enabled/default || -f /etc/nginx/sites-enabled/default ]]; then
    $SUDO rm -f /etc/nginx/sites-enabled/default
  fi

  log "Writing Cloudflare Origin CA Nginx config"
  write_production_nginx_config https "$cert_path" "$key_path" "Cloudflare Origin CA"
  $SUDO ln -sfn "$(production_nginx_available_path)" "$(production_nginx_enabled_path)"

  log "Testing and reloading Nginx"
  $SUDO nginx -t || fail "Nginx config test failed. The previous config backup is available if needed."
  $SUDO systemctl enable --now nginx
  $SUDO systemctl reload nginx

  # shellcheck disable=SC2034 # PRODUCTION_SSL_MODE is a shared global persisted by write_dev_config_file / config.sh
  PRODUCTION_SSL_MODE="cloudflare-origin-ca"
  write_dev_config_file >/dev/null || true

  provider="$(production_ssl_provider_from_cert_path "$cert_path")"
  https_head="$(production_https_status "$domain")"
  if [[ "$https_head" == HTTP/* ]]; then
    ok "${provider} HTTPS path is responding through the current DNS route: ${https_head}"
  else
    warn "Cloudflare Origin CA is installed. Direct curl may fail until Cloudflare proxy is ON and SSL/TLS mode is Full (strict)."
  fi

  echo
  echo "Next steps in Cloudflare:"
  echo "  1) Set ${domain} DNS record to Proxied / orange-cloud."
  echo "  2) Set SSL/TLS mode to Full (strict)."
  echo "  3) Test: curl -I https://${domain}"
  echo "  4) Run: $(toolkit_cmd cloudflare-origin-ssl-status)"
  echo "============================================================"
}

show_cloudflare_origin_ssl_status() {
  local domain vm_ip dns_ip cert_path key_path enabled_path provider https_head ssl_pair ssl_status ssl_detail proxied_note
  require_sudo
  domain="$(production_ssl_domain 2>/dev/null || echo "${PRODUCTION_DOMAIN:-$SITE_NAME}")"
  vm_ip="$(get_vm_ip)"
  dns_ip="$(resolve_ipv4_first "$domain")"
  cert_path="$(cloudflare_origin_cert_path 2>/dev/null || true)"
  key_path="$(cloudflare_origin_key_path 2>/dev/null || true)"
  enabled_path="$(production_nginx_enabled_path)"
  provider="$(production_ssl_provider_from_cert_path "$(production_nginx_active_cert_path 2>/dev/null || true)")"
  https_head="$(production_https_status "$domain")"
  ssl_pair="$(production_ssl_runtime_detail)"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"
  proxied_note="DNS resolves to origin IP; Cloudflare proxy may be DNS-only/grey-cloud"
  if [[ -n "$dns_ip" && "$dns_ip" != "$vm_ip" ]]; then
    proxied_note="DNS does not resolve directly to origin IP; Cloudflare proxy may be ON"
  fi

  echo
  echo "============================================================"
  echo "Cloudflare Origin SSL Status"
  echo "============================================================"
  status_line "Domain" "$([[ -n "$dns_ip" ]] && echo OK || echo WARN)" "${domain}; DNS=${dns_ip:-unresolved}; VM=${vm_ip}"
  status_line "Cloudflare proxy hint" "INFO" "$proxied_note"
  status_line "Active provider" "$([[ "$provider" == "Cloudflare Origin CA" ]] && echo OK || echo WARN)" "$provider"
  status_line "Origin certificate" "$([[ -f "$cert_path" ]] && echo OK || echo WARN)" "${cert_path:-missing}"
  status_line "Origin private key" "$([[ -f "$key_path" ]] && echo OK || echo WARN)" "${key_path:-missing}"
  if [[ -f "$cert_path" ]]; then
    status_line "Origin cert detail" "INFO" "$(certificate_detail_for_file "$cert_path")"
  fi
  status_line "Nginx site" "$([[ -L "$enabled_path" || -f "$enabled_path" ]] && echo OK || echo WARN)" "$enabled_path"
  status_line "HTTPS" "$([[ "$https_head" == HTTP/* ]] && echo OK || echo WARN)" "${https_head:-no response/trust warning}"
  status_line "Overall" "$ssl_status" "$ssl_detail"
  echo
  echo "Cloudflare dashboard target: DNS Proxied/orange-cloud + SSL/TLS Full (strict)."
  echo "============================================================"
}


ssl_mode_context() {
  local vm_ip domain dns_ip provider recommendation detail
  vm_ip="$(get_vm_ip 2>/dev/null || echo unknown)"
  domain="${PRODUCTION_DOMAIN:-}"
  provider="$(active_production_ssl_provider 2>/dev/null || echo "not configured")"
  dns_ip=""
  recommendation="local-dev"
  detail="Use local self-signed/mkcert SSL or plain HTTP for a dev VM."

  if [[ -n "$domain" ]] && validate_production_domain_value "$domain" >/dev/null 2>&1; then
    dns_ip="$(resolve_ipv4_first "$domain")"
    if [[ "$provider" == "Cloudflare Origin CA" ]]; then
      recommendation="cloudflare-origin-ca"
      detail="Cloudflare Origin CA is active. Keep DNS proxied and Cloudflare SSL/TLS on Full (strict)."
    elif [[ -n "$dns_ip" && "$dns_ip" == "$vm_ip" ]]; then
      recommendation="letsencrypt"
      detail="DNS resolves directly to this VM. Let's Encrypt HTTP-01 is the recommended public SSL path."
    elif [[ -n "$dns_ip" && "$dns_ip" != "$vm_ip" ]]; then
      recommendation="cloudflare-origin-ca"
      detail="DNS does not resolve to the origin IP. If this is Cloudflare proxy, use Cloudflare Origin CA."
    else
      recommendation="public-domain-pending"
      detail="Domain is set but DNS is unresolved. Configure DNS before production SSL."
    fi
  elif [[ "$SITE_NAME" == *.test || "$SITE_NAME" == *.local || "${DEPLOYMENT_MODE:-development}" == "development" ]]; then
    recommendation="local-dev"
    detail="Local/dev site detected. Use local self-signed/mkcert SSL; do not use public SSL providers."
  fi

  printf '%s|%s|%s|%s|%s\n' "$recommendation" "$detail" "$provider" "${dns_ip:-unresolved}" "$vm_ip"
}

show_ssl_mode_status() {
  require_sudo
  local ctx mode detail provider dns_ip vm_ip prod_pair prod_status prod_detail local_state
  ctx="$(ssl_mode_context)"
  mode="${ctx%%|*}"; ctx="${ctx#*|}"
  detail="${ctx%%|*}"; ctx="${ctx#*|}"
  provider="${ctx%%|*}"; ctx="${ctx#*|}"
  dns_ip="${ctx%%|*}"; ctx="${ctx#*|}"
  vm_ip="$ctx"
  prod_pair="$(production_ssl_readiness_detail 2>/dev/null || echo 'WARN|not configured')"
  prod_status="${prod_pair%%|*}"
  prod_detail="${prod_pair#*|}"
  if ssl_is_configured 2>/dev/null; then
    local_state="configured"
  else
    local_state="not configured"
  fi

  ui_box_start "SSL Mode Status"
  status_line "Site" "INFO" "$SITE_NAME"
  status_line "Production domain" "$([[ -n "${PRODUCTION_DOMAIN:-}" ]] && echo OK || echo INFO)" "${PRODUCTION_DOMAIN:-not set}"
  status_line "Deployment mode" "INFO" "${DEPLOYMENT_MODE:-development}"
  status_line "VM IP" "INFO" "$vm_ip"
  status_line "DNS result" "INFO" "$dns_ip"
  status_line "Active provider" "INFO" "$provider"
  status_line "Production SSL" "$prod_status" "$prod_detail"
  status_line "Local SSL" "INFO" "$local_state"
  status_line "Recommended mode" "OK" "$mode"
  ui_box_end
  echo "Reason: $detail"
  ui_next "$(toolkit_cmd ssl-mode-guide)" "$(toolkit_cmd production-ssl-wizard)"
}

show_ssl_mode_guide() {
  ui_box_start "SSL Mode Guide"
  echo "Use the SSL mode that matches the deployment path."
  echo
  printf '  %-24s %-18s %s\n' "Mode" "Best for" "Requirement"
  printf '  %-24s %-18s %s\n' "------------------------" "------------------" "------------------------------"
  printf '  %-24s %-18s %s\n' "local self-signed/mkcert" "Local VM" ".test/.local or internal dev hostname"
  printf '  %-24s %-18s %s\n' "Let's Encrypt" "Public VM" "DNS A record points directly to VM; 80 open"
  printf '  %-24s %-18s %s\n' "Cloudflare Origin CA" "Cloudflare VM" "DNS proxied; Cloudflare SSL/TLS Full (strict)"
  ui_box_end
  echo "Rules:"
  echo "  - Local VM: use local SSL only."
  echo "  - Public DNS-only VM: use Let's Encrypt."
  echo "  - Cloudflare proxied VM: use Cloudflare Origin CA."
  echo "  - Do not use Cloudflare Origin CA for direct browser-to-origin access."
  echo
  echo "Commands:"
  echo "  $(toolkit_cmd ssl-mode-status)"
  echo "  $(toolkit_cmd production-ssl-wizard)"
  echo "  $(toolkit_cmd local-ssl-wizard)"
}

show_setup_effort_guide() {
  ui_box_start "Setup Effort / Step Count"
  echo "The goal is one shell command, then guided menu inputs."
  echo
  printf '  %-28s %-12s %-18s %s\n' "Case" "Commands" "Required inputs" "Notes"
  printf '  %-28s %-12s %-18s %s\n' "----------------------------" "------------" "------------------" "------------------------------"
  printf '  %-28s %-12s %-18s %s\n' "Local VM, HTTP" "1" "1-2" "Use local-dev-quickstart"
  printf '  %-28s %-12s %-18s %s\n' "Local VM, local SSL" "1" "2-4" "Add local-ssl-wizard"
  printf '  %-28s %-12s %-18s %s\n' "Public VM, Let's Encrypt" "1" "6-8" "Domain, install, SSL, hardening"
  printf '  %-28s %-12s %-18s %s\n' "Public VM, Cloudflare" "1" "9-11" "Includes cert/key paste"
  printf '  %-28s %-12s %-18s %s\n' "Existing install" "1" "1-3" "Use production-ops-wizard/status"
  ui_box_end
  echo "Verified release public VM entry point:"
  echo "  VERSION=\"v${SCRIPT_VERSION}\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/erpnext-dev.sh\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/SHA256SUMS\"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh public-vm-quickstart"
  echo
  echo "Verified release local VM entry point:"
  echo "  VERSION=\"v${SCRIPT_VERSION}\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/erpnext-dev.sh\"; curl -fsSLO \"https://raw.githubusercontent.com/ReyadWeb/erpnext-dev-installer/\${VERSION}/SHA256SUMS\"; sha256sum -c SHA256SUMS; chmod +x erpnext-dev.sh; sudo ./erpnext-dev.sh local-dev-quickstart"
  echo
  echo "Interpretation: commands are shell commands typed by the user. Inputs are menu choices, confirmations, domain/email, and certificate paste steps."
}

production_ssl_wizard() {
  local choice ctx mode detail provider dns_ip vm_ip
  ctx="$(ssl_mode_context)"
  mode="${ctx%%|*}"; ctx="${ctx#*|}"
  detail="${ctx%%|*}"; ctx="${ctx#*|}"
  provider="${ctx%%|*}"; ctx="${ctx#*|}"
  dns_ip="${ctx%%|*}"; ctx="${ctx#*|}"
  vm_ip="$ctx"
  echo
  echo "============================================================"
  echo "Production SSL Provider Wizard"
  echo "============================================================"
  echo "Choose how this public ERPNext VM should handle HTTPS."
  echo
  status_line "Recommended mode" "INFO" "$mode"
  status_line "Active provider" "INFO" "$provider"
  status_line "DNS / VM" "INFO" "DNS=${dns_ip}; VM=${vm_ip}"
  echo "Reason: $detail"
  echo
  echo "1) Let's Encrypt certificate directly on this VM"
  echo "2) Cloudflare Origin CA certificate for Cloudflare Full (strict)"
  echo "3) Show current production SSL status"
  echo "4) Show Cloudflare Origin CA guide"
  echo "5) Show SSL mode guide/status"
  menu_footer
  menu_read_choice choice
  case "$choice" in
    1) configure_production_ssl ;;
    2) configure_cloudflare_origin_ssl ;;
    3) show_production_ssl_status ;;
    4) show_cloudflare_origin_guide ;;
    5) show_ssl_mode_status; show_ssl_mode_guide ;;
    b|B|"") return 0 ;;
    q|Q) exit 0 ;;
    *) warn "Invalid option: ${choice}" ; return 1 ;;
  esac
}

disable_production_ssl() {
  require_erpnext_vm_context "disable-production-ssl" || return 1
  require_sudo

  local enabled_path available_path domain
  domain="$(production_ssl_domain 2>/dev/null || echo "${PRODUCTION_DOMAIN:-$SITE_NAME}")"
  enabled_path="$(production_nginx_enabled_path)"
  available_path="$(production_nginx_available_path)"

  echo
  echo "============================================================"
  echo "Disable Production HTTPS Reverse Proxy"
  echo "============================================================"
  echo "This disables the managed production Nginx site for ${domain}."
  echo "It does not delete Let's Encrypt certificate files and does not stop ERPNext :8000."
  echo

  if [[ "$ASSUME_YES" -ne 1 ]]; then
    confirm "Disable production HTTPS Nginx site now?" || return 1
  fi

  $SUDO rm -f "$enabled_path"
  if command -v nginx >/dev/null 2>&1; then
    $SUDO nginx -t || warn "Nginx config test failed after disabling the production site."
    $SUDO systemctl reload nginx || true
  fi

  ok "Production HTTPS site disabled"
  echo "Config file kept for review: ${available_path}"
  echo "Certificate files, if present, are kept under: /etc/letsencrypt/live/${domain}"
  echo "============================================================"
}

production_cpu_count() {
  nproc 2>/dev/null || echo 0
}

production_memory_mb() {
  awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0
}

production_root_total_gb() {
  df -BG / 2>/dev/null | awk 'NR==2 {gsub("G", "", $2); print $2+0}' || echo 0
}

production_root_free_gb() {
  df -BG / 2>/dev/null | awk 'NR==2 {gsub("G", "", $4); print $4+0}' || echo 0
}

production_quick_install_state() {
  local state

  # Use the same sudo-aware install detector as doctor/status.
  # Direct [[ -d ... ]] checks can produce false "Incomplete" results when
  # the caller cannot traverse /home/${FRAPPE_USER} without sudo.
  state="$(install_state 2>/dev/null || echo "unknown")"

  case "$state" in
    Installed*) echo "Installed" ;;
    Incomplete) echo "Incomplete" ;;
    "Not installed") echo "Not installed" ;;
    *) echo "$state" ;;
  esac
}

production_backup_count() {
  local bench_dir backup_dir
  bench_dir="$(active_bench_dir 2>/dev/null || echo "$BENCH_DIR")"
  backup_dir="${bench_dir}/sites/${SITE_NAME}/private/backups"

  if ! path_is_dir "$backup_dir"; then
    echo "0"
    return 0
  fi

  if [[ "${SUDO:-}" == "sudo" ]]; then
    $SUDO find "$backup_dir" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.tgz' -o -name '*.tar' -o -name '*.tar.gz' \) 2>/dev/null | wc -l | awk '{print $1+0}'
  else
    find "$backup_dir" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.tgz' -o -name '*.tar' -o -name '*.tar.gz' \) 2>/dev/null | wc -l | awk '{print $1+0}'
  fi
}

production_domain_readiness_status() {
  if [[ -z "$PRODUCTION_DOMAIN" ]]; then
    echo "WARN|not set"
  elif validate_production_domain_value "$PRODUCTION_DOMAIN" >/dev/null 2>&1; then
    echo "OK|$PRODUCTION_DOMAIN"
  else
    echo "WARN|invalid: $PRODUCTION_DOMAIN"
  fi
}

production_ssl_readiness_detail() {
  local prod_pair cert_path

  if prod_pair="$(production_ssl_runtime_detail 2>/dev/null)" && [[ "$prod_pair" == OK\|* ]]; then
    echo "$prod_pair"
    return 0
  fi

  cert_path="$(ssl_cert_path 2>/dev/null || true)"

  if ssl_is_configured 2>/dev/null; then
    if [[ -n "$cert_path" && -f "$cert_path" ]] && ssl_cert_is_self_signed "$cert_path" 2>/dev/null; then
      echo "WARN|local self-signed SSL only; not production SSL"
    else
      echo "INFO|local HTTPS configured; still verify production certificate plan"
    fi
  elif [[ -n "${prod_pair:-}" ]]; then
    echo "$prod_pair"
  else
    echo "WARN|not configured for production"
  fi
}

production_ssl_ok_detail() {
  local pair
  pair="$(production_ssl_readiness_detail 2>/dev/null || true)"
  if [[ "$pair" == OK\|* ]]; then
    echo "${pair#*|}"
    return 0
  fi
  return 1
}

production_classification() {
  local install_state="$1"
  local cpu_count="$2"
  local mem_mb="$3"
  local free_gb="$4"
  local domain_state="$5"
  local backup_count="$6"

  if [[ "$install_state" != Installed* ]]; then
    echo "Not recommended|core ERPNext install is incomplete"
    return 0
  fi

  if [[ "$cpu_count" =~ ^[0-9]+$ && "$cpu_count" -lt 2 ]]; then
    echo "Not recommended|CPU is below the practical minimum"
    return 0
  fi

  if [[ "$mem_mb" =~ ^[0-9]+$ && "$mem_mb" -lt 4096 ]]; then
    echo "Not recommended|RAM is below the practical minimum"
    return 0
  fi

  if [[ "$free_gb" =~ ^[0-9]+$ && "$free_gb" -lt 20 ]]; then
    echo "Not recommended|root filesystem free space is low"
    return 0
  fi

  if [[ "$domain_state" != "OK" ]]; then
    echo "Dev-only|no valid production domain is configured"
    return 0
  fi

  if [[ "$backup_count" == "0" || "$backup_count" == "unknown" ]]; then
    echo "Dev-only|backup readiness is not confirmed"
    return 0
  fi

  echo "Production candidate|resources and basic planning inputs look usable; hardening still required"
}

show_production_readiness() {
  local bench_dir install_quick runtime service auto cpu_count mem_mb total_gb free_gb nginx_state backup_count

  require_sudo
  local domain_pair domain_status domain_state ssl_pair ssl_status ssl_detail class_pair class_name class_reason

  bench_dir="$(active_bench_dir 2>/dev/null || echo "$BENCH_DIR")"
  install_quick="$(production_quick_install_state)"
  runtime="$(runtime_state 2>/dev/null || echo unknown)"
  service="$(service_state 2>/dev/null || echo unknown)"
  auto="$(autostart_state 2>/dev/null || echo unknown)"
  cpu_count="$(production_cpu_count)"
  mem_mb="$(production_memory_mb)"
  total_gb="$(production_root_total_gb)"
  free_gb="$(production_root_free_gb)"
  backup_count="$(production_backup_count)"
  nginx_state="not installed"

  if command -v nginx >/dev/null 2>&1; then
    nginx_state="installed"
  fi

  domain_pair="$(production_domain_readiness_status)"
  domain_status="${domain_pair%%|*}"
  domain_state="${domain_pair#*|}"

  ssl_pair="$(production_ssl_readiness_detail)"
  ssl_status="${ssl_pair%%|*}"
  ssl_detail="${ssl_pair#*|}"

  class_pair="$(production_classification "$install_quick" "$cpu_count" "$mem_mb" "$free_gb" "$domain_status" "$backup_count")"
  class_name="${class_pair%%|*}"
  class_reason="${class_pair#*|}"

  echo
  echo "============================================================"
  echo "Production Readiness / Planning"
  echo "============================================================"
  status_line "Classification" "INFO" "$class_name — $class_reason"
  status_line "Automation mode" "INFO" "planning only; no production changes are applied"
  status_line "Local site" "INFO" "${SITE_NAME} (${SITE_NAME_SOURCE})"
  status_line "Bench" "INFO" "$bench_dir"
  if [[ "$install_quick" == Installed* ]]; then
    status_line "Install state" "OK" "$install_quick"
  else
    status_line "Install state" "WARN" "$install_quick"
  fi
  if [[ "$runtime" == Running* ]]; then
    status_line "Runtime" "OK" "$runtime"
  else
    status_line "Runtime" "WARN" "$runtime"
  fi
  status_line "Service" "INFO" "$service; autostart=${auto}"

  if [[ "$cpu_count" =~ ^[0-9]+$ && "$cpu_count" -ge 2 ]]; then
    status_line "CPU" "OK" "${cpu_count} vCPU"
  else
    status_line "CPU" "WARN" "${cpu_count} vCPU; recommended minimum is 2+"
  fi

  if [[ "$mem_mb" =~ ^[0-9]+$ && "$mem_mb" -ge 8192 ]]; then
    status_line "RAM" "OK" "${mem_mb} MB"
  elif [[ "$mem_mb" =~ ^[0-9]+$ && "$mem_mb" -ge 4096 ]]; then
    status_line "RAM" "WARN" "${mem_mb} MB; usable for dev/small testing, 8192+ MB preferred"
  else
    status_line "RAM" "FAIL" "${mem_mb} MB; recommended minimum is 4096 MB"
  fi

  if [[ "$free_gb" =~ ^[0-9]+$ && "$free_gb" -ge 60 ]]; then
    status_line "Root disk" "OK" "${free_gb}G free of ${total_gb}G"
  elif [[ "$free_gb" =~ ^[0-9]+$ && "$free_gb" -ge 20 ]]; then
    status_line "Root disk" "WARN" "${free_gb}G free of ${total_gb}G; 60G+ free preferred"
  else
    status_line "Root disk" "FAIL" "${free_gb}G free of ${total_gb}G; too low for safe growth/backups"
  fi

  status_line "Production domain" "$domain_status" "$domain_state"
  status_line "Nginx" "INFO" "$nginx_state"
  status_line "Production SSL" "$ssl_status" "$ssl_detail"

  if [[ "$backup_count" =~ ^[0-9]+$ && "$backup_count" -gt 0 ]]; then
    status_line "Backup readiness" "OK" "${backup_count} local backup file(s) found; off-VM backups still recommended"
  elif [[ "$backup_count" == "unknown" ]]; then
    status_line "Backup readiness" "WARN" "backup folder not readable from current user"
  else
    status_line "Backup readiness" "WARN" "no local backup files detected"
  fi

  echo
  echo "Recommended next commands:"
  echo "  $(toolkit_cmd production-plan)"
  echo "  $(toolkit_cmd production-domain-plan)"
  echo "  $(toolkit_cmd public-vm-readiness)"
  echo "  $(toolkit_cmd production-ssl-plan)"
  echo "  $(toolkit_cmd production-firewall-plan)"
  echo "============================================================"
}

show_production_plan() {
  local domain_hint="${PRODUCTION_DOMAIN:-erp.company.com}"

  echo
  echo "============================================================"
  echo "Production Planning Checklist"
  echo "============================================================"
  echo
  echo "This command is planning-only. It does not convert the dev VM into production."
  echo
  echo "1) Decide the target architecture"
  echo "   - Keep this VM as development only, or migrate/harden a separate production VM."
  echo "   - Production should not rely on a casual bench start workflow."
  echo
  echo "2) Confirm production domain"
  echo "   - Current local site: ${SITE_NAME}"
  echo "   - Planned production domain: ${domain_hint}"
  echo "   - Use a real DNS name such as erp.company.com, not .test or .local."
  echo
  echo "3) Confirm DNS and network path"
  echo "   - A/AAAA record points to the production server."
  echo "   - Ports 80 and 443 are reachable where required."
  echo "   - Do not change MX/email DNS records unless ERPNext email routing requires it."
  echo
  echo "4) Confirm SSL approach"
  echo "   - Local mkcert/self-signed SSL is for development only."
  echo "   - Production should use Let's Encrypt, Cloudflare Origin CA, or a business-approved certificate."
  echo
  echo "5) Confirm backup and restore readiness"
  echo "   - Create database + files backup."
  echo "   - Store a copy off the VM."
  echo "   - Test restore before trusting the environment."
  echo
  echo "6) Confirm hardening before go-live"
  echo "   - Firewall policy"
  echo "   - Service supervision"
  echo "   - Update strategy"
  echo "   - Monitoring/log review"
  echo "   - Admin password and credential handling"
  echo
  echo "Useful commands now:"
  echo "  $(toolkit_cmd production-readiness)"
  echo "  $(toolkit_cmd production-domain-plan)"
  echo "  $(toolkit_cmd public-vm-readiness)"
  echo "  $(toolkit_cmd production-ssl-plan)"
  echo "  $(toolkit_cmd production-firewall-plan)"
  echo "  $(toolkit_cmd backup-files)"
  echo "  $(toolkit_cmd support-bundle)"
  echo "============================================================"
}

ssl_site_slug() {
  printf '%s' "$SITE_NAME" | tr -c 'A-Za-z0-9._-' '-'
}

ssl_nginx_site_name() {
  echo "erpnext-dev-$(ssl_site_slug)"
}

ssl_cert_path() {
  echo "${SSL_CERT_PATH:-${SSL_CERT_DIR}/${SITE_NAME}.crt}"
}

ssl_key_path() {
  echo "${SSL_KEY_PATH:-${SSL_CERT_DIR}/${SITE_NAME}.key}"
}

ssl_nginx_available_path() {
  echo "${SSL_NGINX_CONF_DIR}/sites-available/$(ssl_nginx_site_name).conf"
}

ssl_nginx_enabled_path() {
  echo "${SSL_NGINX_CONF_DIR}/sites-enabled/$(ssl_nginx_site_name).conf"
}

show_local_ssl_guide() {
  local vm_ip cert_path key_path escaped_site vm_ssh_user cmd_self cmd_mkcert cmd_configure cmd_status cmd_verify cmd_disable
  vm_ip="$(get_vm_ip)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  escaped_site="${SITE_NAME//./\.}"
  vm_ssh_user="$(suggested_vm_ssh_user)"
  cmd_self="${INSTALLER_CANONICAL_PATH} create-self-signed-local-cert"
  cmd_mkcert="${INSTALLER_CANONICAL_PATH} mkcert-guide"
  cmd_configure="${INSTALLER_CANONICAL_PATH} configure-local-ssl"
  cmd_status="${INSTALLER_CANONICAL_PATH} ssl-status"
  cmd_verify="${INSTALLER_CANONICAL_PATH} verify-local-ssl"
  cmd_disable="${INSTALLER_CANONICAL_PATH} disable-local-ssl"

  cat <<EOF_LOCAL_SSL

============================================================
Local SSL / HTTPS Guide
============================================================

Goal:
  https://${SITE_NAME}

The local SSL feature uses Nginx inside the VM as a reverse proxy:

  Browser HTTPS :443
    -> Nginx inside the VM
      -> Bench web on 127.0.0.1:8000
      -> Socket.io on 127.0.0.1:9000

Direct Bench access remains available:
  http://${SITE_NAME}:8000
  http://${vm_ip}:8000

Reusable toolkit path inside the VM:
  ${INSTALLER_CANONICAL_PATH}

Expected certificate paths inside the VM:
  Certificate: ${cert_path}
  Private key: ${key_path}

Option 1: Quick self-signed test certificate
  Fastest way to confirm the reverse proxy works.
  Browser warnings are expected because the cert is not trusted by the host browser.

  Inside the VM, run:
    ${cmd_self}
    ${cmd_configure}
    ${cmd_status}

  From the HOST, test:
    curl -kI https://${SITE_NAME}

Option 2: Trusted local certificate with mkcert
  Best browser experience for local testing.

  Follow this checklist:
    1) On the HOST, install mkcert and trust the local CA.
    2) On the HOST, generate ${SITE_NAME}.crt and ${SITE_NAME}.key.
    3) On the HOST, copy both files into this VM.
    4) Inside the VM, install the files and enable local HTTPS.
    5) On the HOST, confirm /etc/hosts and test HTTPS.

  Full checklist:
    ${cmd_mkcert}

  HOST commands:
    mkcert -install
    mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} ${vm_ip} localhost 127.0.0.1
    scp ${SITE_NAME}.crt ${SITE_NAME}.key ${vm_ssh_user}@${vm_ip}:/tmp/

  VM commands:
    sudo mkdir -p ${SSL_CERT_DIR}
    sudo cp /tmp/${SITE_NAME}.crt ${cert_path}
    sudo cp /tmp/${SITE_NAME}.key ${key_path}
    sudo chown root:root ${cert_path} ${key_path}
    sudo chmod 644 ${cert_path}
    sudo chmod 600 ${key_path}
    ${cmd_configure}
    ${cmd_status}
    ${cmd_verify}

Host /etc/hosts still needs to map ${SITE_NAME} to this VM IP:
  VM_IP="${vm_ip}"
  LOCAL_DOMAIN="${SITE_NAME}"
  sudo cp /etc/hosts "/etc/hosts.bak.\$(date +%Y%m%d-%H%M%S)"
  sudo sed -i "/[[:space:]]${escaped_site}\([[:space:]]\|$\)/d" /etc/hosts
  echo "\${VM_IP} \${LOCAL_DOMAIN}" | sudo tee -a /etc/hosts

Host tests:
  getent hosts ${SITE_NAME}
  curl -I http://${vm_ip}:8000
  curl -I http://${SITE_NAME}:8000
  curl -kI https://${SITE_NAME}
  curl -I http://${SITE_NAME}:8000

Expected behavior after local SSL is configured:
  http://${SITE_NAME}       -> 301 redirect to https://${SITE_NAME}/
  https://${SITE_NAME}      -> ERPNext login page through Nginx
  http://${SITE_NAME}:8000  -> direct Bench fallback still works

Rollback:
  ${cmd_disable}
  ${INSTALLER_CANONICAL_PATH} ssl-rollback-guide

============================================================
EOF_LOCAL_SSL
}

# Print the HOST commands to install mkcert + its trust dependencies for the
# operator's host OS. `mkcert -install` itself is cross-platform and trusts the
# right store per OS (Keychain on macOS, cert store on Windows, NSS on Linux).
# shellcheck disable=SC2120  # arg is optional; most callers rely on the default
host_mkcert_install_hint() {
  local os="${1:-$(effective_host_os)}"
  case "$os" in
    macos)
      echo "  brew install mkcert nss        # nss also adds Firefox trust"
      ;;
    windows|windows-wsl)
      echo "  choco install mkcert           # or: scoop bucket add extras; scoop install mkcert"
      ;;
    *)
      echo "  sudo apt update && sudo apt install -y libnss3-tools"
      echo "  # then install mkcert from your package manager or the official release binary"
      ;;
  esac
}

show_mkcert_local_ssl_guide() {
  local vm_ip cert_path key_path escaped_site vm_ssh_user cmd_install cmd_configure cmd_verify cmd_disable cmd_env
  local host_label mkcert_deps host_dns_cmds host_dns_tests
  vm_ip="$(get_vm_ip)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  escaped_site="${SITE_NAME//./\.}"
  vm_ssh_user="$(suggested_vm_ssh_user)"
  cmd_install="${INSTALLER_CANONICAL_PATH} install-local-ssl-cert"
  cmd_configure="${INSTALLER_CANONICAL_PATH} configure-local-ssl"
  cmd_verify="${INSTALLER_CANONICAL_PATH} verify-local-ssl"
  cmd_disable="${INSTALLER_CANONICAL_PATH} disable-local-ssl"
  cmd_env="${INSTALLER_CANONICAL_PATH} environment-check"
  host_label="$(host_os_label)"
  mkcert_deps="$(host_mkcert_install_hint)"
  host_dns_cmds="$(print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip")"
  host_dns_tests="$(print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip")"

  cat <<EOF_MKCERT

============================================================
Trusted Local SSL with mkcert
============================================================

Goal:
  Use https://${SITE_NAME} without browser warnings on the HOST machine.

Important:
  - Run mkcert on the HOST where the browser runs.
  - Run toolkit SSL commands inside the ERPNext VM.
  - The reusable toolkit path inside the VM is: ${INSTALLER_CANONICAL_PATH}
  - If unsure which machine you are on, run: ${cmd_env}
  - Host OS: ${host_label} (change with ${INSTALLER_CANONICAL_PATH} set-host-os)

Checklist:

1) On the ${host_label} HOST, install mkcert dependencies:

${mkcert_deps}

2) On the HOST, trust the local CA:

  mkcert -install

3) On the HOST, generate the certificate and key:

  mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} ${vm_ip} localhost 127.0.0.1

4) On the HOST, copy the cert/key into the VM:

  scp ${SITE_NAME}.crt ${SITE_NAME}.key ${vm_ssh_user}@${vm_ip}:/tmp/

  If your VM uses a different SSH user, replace '${vm_ssh_user}' with that user.

5) Inside the VM, install the cert/key safely:

  ${cmd_install}

  This copies from:
    /tmp/${SITE_NAME}.crt
    /tmp/${SITE_NAME}.key

  To:
    ${cert_path}
    ${key_path}

  Existing cert/key files are backed up first, and permissions are enforced.

6) Inside the VM, enable/reload the HTTPS reverse proxy:

  ${cmd_configure}
  ${cmd_verify}

7) On the ${host_label} HOST, confirm DNS/hosts and HTTPS:

${host_dns_cmds}

  Then test:
${host_dns_tests}

Expected:
  http://${SITE_NAME}       -> 301 redirect to https://${SITE_NAME}/
  https://${SITE_NAME}      -> 200 OK without using curl -k
  http://${SITE_NAME}:8000  -> direct Bench fallback still works

Rollback:
  ${cmd_disable}
  ${INSTALLER_CANONICAL_PATH} ssl-rollback-guide

============================================================
EOF_MKCERT
}


run_trusted_mkcert_setup() {
  require_erpnext_vm_context "trusted-mkcert-setup" || return 1

  local vm_ip src_cert src_key reply ssh_user host_label host_os
  vm_ip="$(get_vm_ip)"
  src_cert="${LOCAL_SSL_CERT_SOURCE:-/tmp/${SITE_NAME}.crt}"
  src_key="${LOCAL_SSL_KEY_SOURCE:-/tmp/${SITE_NAME}.key}"
  ssh_user="$(suggested_vm_ssh_user)"
  host_os="$(effective_host_os)"
  host_label="$(host_os_label)"

  echo
  echo "============================================================"
  echo "Trusted mkcert Local HTTPS Setup"
  echo "============================================================"
  echo "This path uses mkcert on the HOST machine so the HOST browser trusts https://${SITE_NAME}."
  echo
  echo "Important machine split:"
  echo "  HOST machine ($(host_os_label)): hosts file, mkcert -install, generate cert, scp to VM"
  echo "  ERPNext VM:   wait here, then install the copied cert and enable HTTPS"
  echo
  status_line "Local domain" "INFO" "${SITE_NAME}"
  status_line "Detected VM IP" "OK" "${vm_ip}"
  status_line "Host OS" "INFO" "$(host_os_label) (change with $(toolkit_cmd set-host-os))"
  status_line "Expected cert source" "INFO" "${src_cert}"
  status_line "Expected key source" "INFO" "${src_key}"

  # Step 0: HOST /etc/hosts must map the friendly name before HTTPS is useful.
  echo
  echo "------------------------------------------------------------"
  echo "Step 0 — HOST /etc/hosts (required before friendly HTTP/HTTPS)"
  echo "------------------------------------------------------------"
  echo "Run on the HOST machine (not inside this VM):"
  print_host_dns_commands_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Then test from the HOST:"
  echo "  curl -I http://${SITE_NAME}:8000"
  echo "  # Prefer http://${SITE_NAME}:8000 — raw IP often shows an unstyled page."
  echo
  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    if ! confirm "HOST /etc/hosts already maps ${SITE_NAME} to ${vm_ip}?"; then
      warn "Apply the HOST /etc/hosts commands above, then re-run this setup."
      echo "  $(toolkit_cmd trusted-mkcert-setup)"
      echo "============================================================"
      return 0
    fi
  fi

  # Step 1: HOST mkcert + scp
  echo
  echo "------------------------------------------------------------"
  echo "Step 1 — HOST: install CA, generate cert, copy into the VM"
  echo "------------------------------------------------------------"
  echo "Run these on the ${host_label} HOST machine:"
  echo "  0. Install mkcert (one time):"
  host_mkcert_install_hint | sed 's/^  /     /'
  echo "  1. mkcert -install"
  echo "  2. mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} ${vm_ip} localhost 127.0.0.1"
  echo "  3. scp ${SITE_NAME}.crt ${SITE_NAME}.key ${ssh_user}@${vm_ip}:/tmp/"
  if [[ "$host_os" == "windows" || "$host_os" == "windows-wsl" ]]; then
    echo "     (Windows 10+ ships scp via OpenSSH; run from PowerShell. WSL2: run from the WSL shell.)"
  fi
  echo
  echo "Stay in this wizard. After scp finishes, press Enter here to continue."
  echo "Detailed guide: $(toolkit_cmd mkcert-guide)"

  # Step 2: wait/recheck for /tmp certs instead of forcing a menu exit.
  while true; do
    if [[ -f "$src_cert" && -f "$src_key" ]]; then
      status_line "Copied certificate" "OK" "$src_cert"
      status_line "Copied private key" "OK" "$src_key"
      break
    fi
    if [[ -f "$src_cert" ]]; then
      status_line "Copied certificate" "OK" "$src_cert"
    else
      status_line "Copied certificate" "WARN" "not found yet: ${src_cert}"
    fi
    if [[ -f "$src_key" ]]; then
      status_line "Copied private key" "OK" "$src_key"
    else
      status_line "Copied private key" "WARN" "not found yet: ${src_key}"
    fi
    echo
    if [[ ! -t 0 || "${ASSUME_YES:-0}" -eq 1 ]]; then
      warn "Cert/key not in /tmp yet. Non-interactive session cannot wait."
      echo "Copy the files, then re-run: $(toolkit_cmd trusted-mkcert-setup)"
      echo "============================================================"
      return 0
    fi
    read -r -p "Press Enter after scp (or type skip / guide): " reply || reply="skip"
    reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
    case "$reply" in
      skip|s|q|quit)
        warn "Leaving without installing. Re-run when the files are in /tmp:"
        echo "  $(toolkit_cmd trusted-mkcert-setup)"
        echo "============================================================"
        return 0
        ;;
      guide|g|help|h)
        show_mkcert_local_ssl_guide || true
        ;;
      *)
        ;;
    esac
  done

  # Step 3: install + configure + verify inside the VM.
  echo
  echo "------------------------------------------------------------"
  echo "Step 2 — VM: install cert, enable Nginx HTTPS, verify"
  echo "------------------------------------------------------------"
  if [[ -t 0 && "${ASSUME_YES:-0}" -ne 1 ]]; then
    if ! confirm "Install the copied mkcert certificate and enable local HTTPS now?"; then
      warn "mkcert files found, but install was skipped."
      echo "Run later:"
      echo "  $(toolkit_cmd install-local-ssl-cert)"
      echo "  $(toolkit_cmd configure-local-ssl)"
      echo "  $(toolkit_cmd verify-local-ssl)"
      echo "============================================================"
      return 0
    fi
  fi

  install_local_ssl_cert
  configure_local_ssl
  verify_local_ssl || true

  echo
  ok "Trusted local HTTPS should now be ready."
  echo "Open from the HOST browser (only recommended URL):"
  echo "  https://${SITE_NAME}"
  echo "  https://${SITE_NAME}/app"
  echo "  https://${SITE_NAME}/login"
  echo "============================================================"
}

create_self_signed_local_cert() {
  require_erpnext_vm_context "create-self-signed-local-cert" || return 1
  require_sudo

  local cert_path key_path vm_ip
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Create Self-Signed Local SSL Certificate"
  echo "============================================================"
  echo "This creates a quick local test certificate for ${SITE_NAME}."
  echo "Browsers will show a certificate warning unless you use mkcert/trusted CA."
  echo
  echo "Certificate: ${cert_path}"
  echo "Private key: ${key_path}"
  echo

  if ! command -v openssl >/dev/null 2>&1; then
    log "Installing openssl"
    $SUDO apt-get update
    $SUDO apt-get install -y openssl
  fi

  $SUDO mkdir -p "$SSL_CERT_DIR"

  if [[ -f "$cert_path" || -f "$key_path" ]]; then
    local stamp
    stamp="$(date +%Y%m%d_%H%M%S)"
    warn "Existing certificate/key found. Backing them up first."
    [[ -f "$cert_path" ]] && $SUDO cp "$cert_path" "${cert_path}.bak.${stamp}"
    [[ -f "$key_path" ]] && $SUDO cp "$key_path" "${key_path}.bak.${stamp}"
  fi

  $SUDO openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "$key_path" \
    -out "$cert_path" \
    -subj "/CN=${SITE_NAME}" \
    -addext "subjectAltName=DNS:${SITE_NAME},IP:${vm_ip},DNS:localhost,IP:127.0.0.1"

  $SUDO chown root:root "$cert_path" "$key_path"
  $SUDO chmod 644 "$cert_path"
  $SUDO chmod 600 "$key_path"

  ok "Self-signed local certificate created"
  echo
  echo "Next steps:"
  echo "  $(toolkit_cmd configure-local-ssl)"
  echo "  $(toolkit_cmd ssl-status)"
  echo
  echo "Host test:"
  echo "  curl -kI https://${SITE_NAME}"
  echo "============================================================"
}

write_local_ssl_nginx_config() {
  local available_path cert_path key_path redirect_block
  available_path="$(ssl_nginx_available_path)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"

  if [[ "$SSL_REDIRECT_HTTP" == "true" ]]; then
    redirect_block="return 301 https://\$host\$request_uri;"
  else
    redirect_block="proxy_pass http://127.0.0.1:8000;\n    proxy_set_header Host \$host;\n    proxy_set_header X-Forwarded-Host \$host;\n    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n    proxy_set_header X-Forwarded-Proto http;\n    proxy_set_header X-Real-IP \$remote_addr;\n    proxy_redirect off;"
  fi

  $SUDO mkdir -p "${SSL_NGINX_CONF_DIR}/sites-available" "${SSL_NGINX_CONF_DIR}/sites-enabled"

  $SUDO tee "$available_path" >/dev/null <<EOF_NGINX
# Managed by ERPNext Developer Toolkit.
# Local development reverse proxy for ${SITE_NAME}.
# Direct Bench access remains available on :8000.

server {
    listen 80;
    server_name ${SITE_NAME};

    ${redirect_block}
}

server {
    listen 443 ssl http2;
    server_name ${SITE_NAME};

    ssl_certificate     ${cert_path};
    ssl_certificate_key ${key_path};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    client_max_body_size 100m;

    proxy_read_timeout 120s;
    proxy_send_timeout 120s;

    location /socket.io {
        proxy_pass http://127.0.0.1:9000/socket.io;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;
    }
}
EOF_NGINX
}


local_vm_firewall_profile_is_active() {
  command -v ufw >/dev/null 2>&1 || return 1
  ufw_is_active || return 1

  ufw_port_has_allow 22 || return 1
  ufw_port_has_allow 80 || return 1
  ufw_port_has_allow 443 || return 1
  ufw_port_has_allow 8000 || return 1
  ufw_port_has_allow 9000 || return 1

  return 0
}

print_local_https_success_next_steps() {
  echo
  echo "Recommended next steps after local HTTPS is working:"
  echo "  1) Confirm access:"
  echo "     $(toolkit_cmd verify-access)"
  echo "     $(toolkit_cmd local-access-doctor)"
  echo
  if local_vm_firewall_profile_is_active 2>/dev/null; then
    echo "  2) Local VM security profile: already active"
    echo "     Optional status check: $(toolkit_cmd vm-firewall-status)"
  elif ufw_is_active 2>/dev/null; then
    echo "  2) Local firewall: UFW is active"
    echo "     No firewall change is required just because local HTTPS is working."
    echo "     Optional status check: $(toolkit_cmd vm-firewall-status)"
    echo "     Reapply the Local VM profile only if local access ports are not behaving as expected:"
    echo "       $(toolkit_cmd local-firewall-profile)"
  else
    echo "  2) Apply the Local VM security profile:"
    echo "     $(toolkit_cmd security-hardening-wizard)"
    echo "     Choose: 2) Local VM firewall profile"
  fi
  echo
  echo "  3) Install optional apps only after the site remains healthy:"
  echo "     $(toolkit_cmd app-install-wizard)"
  echo
  echo "Important: for local/dev VMs, use the Local VM firewall profile, not the Production profile."
}

configure_local_ssl() {
  require_erpnext_vm_context "configure-local-ssl" || return 1
  require_sudo

  local cert_path key_path available_path enabled_path vm_ip
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  available_path="$(ssl_nginx_available_path)"
  enabled_path="$(ssl_nginx_enabled_path)"
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Configure Local SSL / HTTPS"
  echo "============================================================"
  echo "This configures Nginx as a local HTTPS reverse proxy."
  echo "It does not replace the ERPNext dev service and does not remove :8000 access."
  echo
  echo "Expected certificate: ${cert_path}"
  echo "Expected key:         ${key_path}"
  echo

  if [[ ! -f "$cert_path" || ! -f "$key_path" ]]; then
    $SUDO mkdir -p "$SSL_CERT_DIR"
    warn "Certificate or key is missing."
    echo
    echo "Create/copy the certificate files first, then rerun this command."
    echo "For instructions, run: $(toolkit_cmd local-ssl-guide)"
    echo
    echo "Quick target paths:"
    echo "  ${cert_path}"
    echo "  ${key_path}"
    echo "============================================================"
    return 1
  fi

  log "Installing Nginx if needed"
  $SUDO apt-get update
  $SUDO apt-get install -y nginx

  log "Writing local SSL reverse proxy config"
  write_local_ssl_nginx_config

  log "Enabling local SSL Nginx site"
  $SUDO ln -sfn "$available_path" "$enabled_path"

  log "Testing Nginx configuration"
  if ! $SUDO nginx -t; then
    err "Nginx configuration test failed. Disabling the new SSL site."
    $SUDO rm -f "$enabled_path"
    fail "Local SSL configuration failed. Existing ERPNext :8000 access was not changed."
  fi

  log "Starting/reloading Nginx"
  $SUDO systemctl enable --now nginx
  $SUDO systemctl reload nginx

  ok "Local HTTPS reverse proxy configured"
  echo
  echo "Test from the host:"
  echo "  curl -kI https://${SITE_NAME}"
  echo
  echo "Open in browser:"
  echo "  https://${SITE_NAME}"
  echo
  echo "Direct Bench access still works:"
  echo "  http://${SITE_NAME}:8000"
  echo "  http://${vm_ip}:8000"
  echo "============================================================"
}

disable_local_ssl() {
  require_erpnext_vm_context "disable-local-ssl" || return 1
  require_sudo

  local enabled_path available_path
  enabled_path="$(ssl_nginx_enabled_path)"
  available_path="$(ssl_nginx_available_path)"

  echo
  echo "============================================================"
  echo "Disable Local SSL / HTTPS"
  echo "============================================================"
  echo "This disables the Nginx site symlink only."
  echo "It keeps certificate files and the saved Nginx config for later reuse."
  echo

  if [[ -L "$enabled_path" || -f "$enabled_path" ]]; then
    $SUDO rm -f "$enabled_path"
    ok "Disabled local SSL site: $enabled_path"
  else
    warn "Local SSL site was not enabled."
  fi

  if command -v nginx >/dev/null 2>&1; then
    if $SUDO nginx -t; then
      $SUDO systemctl reload nginx || true
      ok "Nginx reloaded"
    else
      warn "Nginx config test failed after disabling. Check manually: sudo nginx -t"
    fi
  fi

  echo
  echo "Saved config: ${available_path}"
  echo "Direct Bench access remains available on :8000."
  echo "============================================================"
}


ssl_is_configured() {
  local cert_path key_path enabled_path available_path
  cert_path="$(ssl_cert_path 2>/dev/null || true)"
  key_path="$(ssl_key_path 2>/dev/null || true)"
  enabled_path="$(ssl_nginx_enabled_path 2>/dev/null || true)"
  available_path="$(ssl_nginx_available_path 2>/dev/null || true)"

  [[ -n "$cert_path" && -f "$cert_path" ]] || return 1
  [[ -n "$key_path" && -f "$key_path" ]] || return 1
  [[ -n "$enabled_path" && ( -L "$enabled_path" || -f "$enabled_path" ) ]] || return 1
  [[ -n "$available_path" && -f "$available_path" ]] || return 1
  return 0
}

ssl_cert_is_self_signed() {
  local cert_path="$1" issuer subject
  [[ -n "$cert_path" && -f "$cert_path" ]] || return 1
  issuer="$(openssl x509 -in "$cert_path" -noout -issuer 2>/dev/null | sed 's/^issuer=//' || true)"
  subject="$(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null | sed 's/^subject=//' || true)"
  [[ -n "$issuer" && -n "$subject" && "$issuer" == "$subject" ]]
}

show_ssl_status() {
  local cert_path key_path available_path enabled_path vm_ip https_head direct_head issuer subject dates nginx_state cert_state key_state site_state port443_state cert_type
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  available_path="$(ssl_nginx_available_path)"
  enabled_path="$(ssl_nginx_enabled_path)"
  vm_ip="$(get_vm_ip)"

  echo
  echo "============================================================"
  echo "Local SSL / HTTPS Status"
  echo "============================================================"
  echo "Scope: local VM HTTPS only. Production HTTPS has a separate menu."
  echo

  if [[ -f "$cert_path" ]]; then
    cert_state="present: ${cert_path}"
  else
    cert_state="missing: ${cert_path}"
  fi
  if [[ -f "$key_path" ]]; then
    key_state="present: ${key_path}"
  else
    key_state="missing: ${key_path}"
  fi
  if [[ -f "$available_path" ]]; then
    status_line "Nginx local config" "OK" "$available_path"
  else
    status_line "Nginx local config" "INFO" "not created yet"
  fi
  if [[ -L "$enabled_path" || -f "$enabled_path" ]]; then
    site_state="enabled: ${enabled_path}"
  else
    site_state="disabled/not enabled"
  fi

  [[ -f "$cert_path" ]] && status_line "Certificate" "OK" "$cert_state" || status_line "Certificate" "WARN" "$cert_state"
  [[ -f "$key_path" ]] && status_line "Private key" "OK" "$key_state" || status_line "Private key" "WARN" "$key_state"
  [[ -L "$enabled_path" || -f "$enabled_path" ]] && status_line "Local HTTPS site" "OK" "$site_state" || status_line "Local HTTPS site" "INFO" "$site_state"

  if command -v nginx >/dev/null 2>&1; then
    nginx_state="installed"
    if systemctl is-active --quiet nginx 2>/dev/null; then
      nginx_state="installed/running"
    fi
    status_line "Nginx" "OK" "$nginx_state"
  else
    status_line "Nginx" "INFO" "not installed yet"
  fi

  if port_listens 443; then
    port443_state="listening"
    https_head="$(curl_head_status "https://${SITE_NAME}/" "$SITE_NAME" 443 "127.0.0.1" || true)"
    if [[ "$https_head" == HTTP/* ]]; then
      status_line "HTTPS response" "OK" "$https_head"
    else
      status_line "HTTPS response" "WARN" "port 443 listens, but local HTTPS did not respond cleanly"
    fi
  else
    port443_state="not listening"
    status_line "Port 443" "INFO" "$port443_state"
  fi

  direct_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  if [[ "$direct_head" == HTTP/* ]]; then
    status_line "Bench fallback" "OK" "http://127.0.0.1:8000 -> ${direct_head}"
  else
    status_line "Bench fallback" "WARN" "no direct Bench response on 127.0.0.1:8000"
  fi

  if [[ -f "$cert_path" ]]; then
    issuer="$(certificate_issuer_for_file "$cert_path" 2>/dev/null || true)"
    subject="$(certificate_subject_for_file "$cert_path" 2>/dev/null || true)"
    dates="$(certificate_dates_for_file "$cert_path" 2>/dev/null || true)"
    if ssl_cert_is_self_signed "$cert_path" 2>/dev/null; then
      cert_type="self-signed/local test certificate"
    else
      cert_type="custom/trusted local certificate"
    fi
    status_line "Certificate type" "INFO" "$cert_type"
    [[ -n "$subject" ]] && status_line "Certificate subject" "INFO" "$subject"
    [[ -n "$issuer" ]] && status_line "Certificate issuer" "INFO" "$issuer"
    [[ -n "$dates" ]] && status_line "Certificate dates" "INFO" "$dates"
  fi

  echo
  echo "Useful commands:"
  echo "  $(toolkit_cmd local-ssl-wizard)"
  echo "  $(toolkit_cmd verify-local-ssl)"
  echo "  $(toolkit_cmd disable-local-ssl)"
  echo
  echo "Host tests:"
  echo "  curl -kI https://${SITE_NAME}"
  echo "  curl -I http://${SITE_NAME}:8000"
  echo "============================================================"
}

install_local_ssl_cert() {
  require_erpnext_vm_context "install-local-ssl-cert" || return 1
  require_sudo

  local cert_path key_path src_cert src_key stamp
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  src_cert="${LOCAL_SSL_CERT_SOURCE:-/tmp/${SITE_NAME}.crt}"
  src_key="${LOCAL_SSL_KEY_SOURCE:-/tmp/${SITE_NAME}.key}"

  echo
  echo "============================================================"
  echo "Install / Replace Local SSL Certificate"
  echo "============================================================"
  echo "Source certificate: ${src_cert}"
  echo "Source private key: ${src_key}"
  echo "Target certificate: ${cert_path}"
  echo "Target private key: ${key_path}"
  echo

  if [[ ! -f "$src_cert" || ! -f "$src_key" ]]; then
    warn "Source certificate/key not found."
    echo
    echo "For trusted local SSL, generate the files on the HOST using mkcert, then copy them into the VM:"
    echo "  mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} $(get_vm_ip) localhost 127.0.0.1"
    echo "  scp ${SITE_NAME}.crt ${SITE_NAME}.key $(suggested_vm_ssh_user)@$(get_vm_ip):/tmp/"
    echo
    echo "Then rerun:"
    echo "  $(toolkit_cmd install-local-ssl-cert)"
    echo
    echo "For a fast untrusted test certificate, run:"
    echo "  $(toolkit_cmd create-self-signed-local-cert)"
    echo "============================================================"
    return 1
  fi

  if ! validate_certificate_and_key_pair "$src_cert" "$src_key"; then
    fail "The source certificate and key are invalid or do not match."
  fi

  $SUDO mkdir -p "$SSL_CERT_DIR"
  stamp="$(date +%Y%m%d_%H%M%S)"
  [[ -f "$cert_path" ]] && $SUDO cp "$cert_path" "${cert_path}.bak.${stamp}"
  [[ -f "$key_path" ]] && $SUDO cp "$key_path" "${key_path}.bak.${stamp}"

  $SUDO cp "$src_cert" "$cert_path"
  $SUDO cp "$src_key" "$key_path"
  $SUDO chown root:root "$cert_path" "$key_path"
  $SUDO chmod 644 "$cert_path"
  $SUDO chmod 600 "$key_path"

  ok "Local SSL certificate installed"
  echo
  echo "Next steps:"
  echo "  $(toolkit_cmd configure-local-ssl)"
  echo "  $(toolkit_cmd verify-local-ssl)"
  echo "============================================================"
}

verify_local_ssl() {
  require_sudo
  local vm_ip cert_path key_path enabled_path http_head https_head direct_head failed=0
  vm_ip="$(get_vm_ip)"
  cert_path="$(ssl_cert_path)"
  key_path="$(ssl_key_path)"
  enabled_path="$(ssl_nginx_enabled_path)"

  echo
  echo "============================================================"
  echo "Verify Local SSL / HTTPS"
  echo "============================================================"
  echo

  [[ -f "$cert_path" ]] && status_line "Certificate" "OK" "$cert_path" || { status_line "Certificate" "FAIL" "missing: $cert_path"; failed=1; }
  [[ -f "$key_path" ]] && status_line "Private key" "OK" "$key_path" || { status_line "Private key" "FAIL" "missing: $key_path"; failed=1; }
  [[ -L "$enabled_path" || -f "$enabled_path" ]] && status_line "Nginx site enabled" "OK" "$enabled_path" || { status_line "Nginx site enabled" "FAIL" "missing: $enabled_path"; failed=1; }

  if command -v nginx >/dev/null 2>&1; then
    if sudo -n nginx -t >/dev/null 2>&1; then
      status_line "Nginx config" "OK" "nginx -t passed"
    elif [[ "${EUID:-$(id -u)}" -eq 0 ]] && nginx -t >/dev/null 2>&1; then
      status_line "Nginx config" "OK" "nginx -t passed"
    else
      status_line "Nginx config" "WARN" "could not verify without sudo, or nginx -t failed"
    fi
  else
    status_line "Nginx" "FAIL" "not installed"
    failed=1
  fi

  if port_listens 443; then
    status_line "Port 443" "OK" "listening"
  else
    status_line "Port 443" "FAIL" "not listening"
    failed=1
  fi

  direct_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  [[ "$direct_head" == HTTP/* ]] && status_line "Bench backend" "OK" "$direct_head" || status_line "Bench backend" "WARN" "no response on 127.0.0.1:8000"

  http_head="$(curl_head_status "http://${SITE_NAME}/" "$SITE_NAME" 80 "127.0.0.1" || true)"
  https_head="$(curl_head_status "https://${SITE_NAME}/" "$SITE_NAME" 443 "127.0.0.1" || true)"

  [[ "$http_head" == HTTP/* ]] && status_line "Local HTTP entry" "OK" "$http_head" || status_line "Local HTTP entry" "WARN" "no HTTP response through Nginx"
  if [[ "$https_head" == HTTP/* ]]; then
    status_line "Local HTTPS entry" "OK" "$https_head"
  else
    status_line "Local HTTPS entry" "FAIL" "no HTTPS response through Nginx"
    failed=1
  fi

  echo
  echo "Host-side checks ($(host_os_label)):"
  print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip"
  echo
  echo "Expected host mapping:"
  echo "  $(host_mapping_ip "$vm_ip") ${SITE_NAME}"
  if (( failed == 0 )); then
    print_local_https_success_next_steps
  fi
  echo "============================================================"
  return "$failed"
}

show_browser_trust_check_guide() {
  local vm_ip host_label host_dns_tests mkcert_deps map_ip
  vm_ip="$(get_vm_ip)"
  host_label="$(host_os_label)"
  host_dns_tests="$(print_host_dns_tests_for_site "$SITE_NAME" "$vm_ip")"
  mkcert_deps="$(host_mkcert_install_hint)"
  map_ip="$(host_mapping_ip "$vm_ip")"
  cat <<EOF_BROWSER_TRUST

============================================================
Browser Trust Check Guide
============================================================

Local HTTPS has two possible trust modes:

1) Self-signed certificate
   - Good for confirming that Nginx/HTTPS works.
   - Browser warning is expected.
   - curl requires -k:
     curl -kI https://${SITE_NAME}

2) mkcert trusted certificate
   - Best local developer experience.
   - The certificate is trusted by the HOST browser because mkcert installs a local CA on the HOST.
   - curl/browser should work without a certificate warning after the host trusts the CA.

Host checklist (${host_label}):
${host_dns_tests}

Expected host mapping entry:
  ${map_ip} ${SITE_NAME}

For trusted SSL, run on the ${host_label} HOST:
${mkcert_deps}
  mkcert -install
  mkcert -cert-file ${SITE_NAME}.crt -key-file ${SITE_NAME}.key ${SITE_NAME} ${vm_ip} localhost 127.0.0.1
  scp ${SITE_NAME}.crt ${SITE_NAME}.key $(suggested_vm_ssh_user)@${vm_ip}:/tmp/

Then run inside this VM:
  $(toolkit_cmd install-local-ssl-cert)
  $(toolkit_cmd configure-local-ssl)
  $(toolkit_cmd verify-local-ssl)

============================================================
EOF_BROWSER_TRUST
}

show_ssl_rollback_guide() {
  cat <<EOF_SSL_ROLLBACK

============================================================
Local SSL Rollback Guide
============================================================

Local SSL rollback is safe because the toolkit uses Nginx as a reverse proxy.
It does not remove the ERPNext bench service and does not remove direct :8000 access.

Recommended rollback:
  $(toolkit_cmd disable-local-ssl)
  $(toolkit_cmd verify-ssl-rollback)

What rollback does:
  - Removes/disables the local Nginx site symlink.
  - Keeps certificate files for reuse.
  - Keeps direct Bench access on port 8000.

After rollback, use:
  http://${SITE_NAME}:8000
  http://$(get_vm_ip):8000

If Nginx still listens on 443 because another site uses it, that is not necessarily an ERPNext local SSL issue.
Check enabled Nginx sites:
  ls -la /etc/nginx/sites-enabled/

============================================================
EOF_SSL_ROLLBACK
}

verify_ssl_rollback() {
  local enabled_path direct_head failed=0
  enabled_path="$(ssl_nginx_enabled_path)"

  echo
  echo "============================================================"
  echo "Verify Local SSL Rollback"
  echo "============================================================"
  echo

  if [[ -L "$enabled_path" || -f "$enabled_path" ]]; then
    status_line "Local SSL site" "FAIL" "still enabled: ${enabled_path}"
    failed=1
  else
    status_line "Local SSL site" "OK" "disabled"
  fi

  direct_head="$(curl_head_status "http://127.0.0.1:8000/" "" "" "" || true)"
  if [[ "$direct_head" == HTTP/* ]]; then
    status_line "Bench fallback" "OK" "$direct_head"
  else
    status_line "Bench fallback" "WARN" "no direct Bench response on 127.0.0.1:8000"
  fi

  if command -v nginx >/dev/null 2>&1; then
    if sudo -n nginx -t >/dev/null 2>&1 || { [[ "${EUID:-$(id -u)}" -eq 0 ]] && nginx -t >/dev/null 2>&1; }; then
      status_line "Nginx config" "OK" "nginx -t passed"
    else
      status_line "Nginx config" "WARN" "could not verify without sudo, or nginx -t failed"
    fi
  fi

  echo
  echo "Use after rollback:"
  echo "  http://${SITE_NAME}:8000"
  echo "  http://$(get_vm_ip):8000"
  echo "============================================================"
  return "$failed"
}

# shellcheck disable=SC2120 # back_target is an optional caller override with a default
run_local_ssl_wizard() {
  local back_target="${1:-return}"
  local back_label="Local VM HTTPS / SSL"
  if [[ "$back_target" == "main" ]]; then
    back_label="Main menu"
  fi
  while true; do
    echo
    echo "============================================================"
    echo "Local SSL Wizard"
    echo "============================================================"
    menu_location_note "Main menu > 8) Local VM HTTPS / SSL > 1) Local SSL Wizard" "local-ssl-wizard"
    echo "Use this only for local VM domains such as ${SITE_NAME}."
    echo "For public domains, use: $(toolkit_cmd production-ssl-menu)"
    echo "Already finished a step? Re-run the same option — completed work is detected where possible."
    echo
    print_two_column_menu \
      "1) Quick self-signed setup" \
      "2) Trusted mkcert setup" \
      "3) Install/replace cert" \
      "4) Configure/reload HTTPS" \
      "5) Verify local HTTPS" \
      "6) Local SSL status" \
      "7) Browser trust guide" \
      "8) Disable local HTTPS" \
      "9) Local security profile"
    menu_footer back "$back_label"
    local wizard_choice=""
    menu_read_choice wizard_choice

    case "$wizard_choice" in
      1)
        create_self_signed_local_cert
        configure_local_ssl
        verify_local_ssl || true
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      2)
        run_trusted_mkcert_setup
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      3)
        install_local_ssl_cert
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      4)
        configure_local_ssl
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      5)
        verify_local_ssl
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      6)
        show_ssl_status
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      7)
        show_browser_trust_check_guide
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      8)
        disable_local_ssl
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      9)
        configure_local_vm_firewall
        pause_after_screen "Press Enter to return to Local SSL Wizard..."
        ;;
      b|B|"")
        if [[ "$back_target" == "main" ]]; then
          show_menu
          return 0
        fi
        return 0
        ;;
      q|Q) exit 0 ;;
      *) warn "Invalid option"; pause_after_screen "Press Enter to continue..." ;;
    esac
  done
}

show_production_ssl_menu() {
  local back_target="${1:-return}"
  local back_label="Main menu"
  while true; do
    echo
    echo "============================================================"
    echo "Production HTTPS / SSL"
    echo "============================================================"
    menu_location_note "Main menu > 9) Production HTTPS / SSL" "production-ssl-menu"
    echo "Use this only for public domains. For local .test HTTPS, use Main menu > 8) Local VM HTTPS / SSL."
    echo
    print_two_column_menu \
      "1) Production SSL Wizard" \
      "2) Production SSL Status" \
      "3) Production SSL Plan" \
      "4) Production SSL Guide" \
      "5) Production Domain Guide" \
      "6) Public VM Readiness" \
      "7) Configure Let's Encrypt SSL" \
      "8) Cloudflare Origin SSL" \
      "9) Cloudflare Origin Status" \
      "10) SSL Mode Status" \
      "11) SSL Mode Guide" \
      "12) Disable Production SSL"
    menu_footer back "$back_label"
    local prod_ssl_choice=""
    menu_read_choice prod_ssl_choice

    case "$prod_ssl_choice" in
      1) production_ssl_wizard ;;
      2) show_production_ssl_status ;;
      3) show_production_ssl_plan ;;
      4) show_production_ssl_guide ;;
      5) show_production_domain_guide ;;
      6) show_public_vm_readiness ;;
      7) configure_production_ssl ;;
      8) configure_cloudflare_origin_ssl ;;
      9) show_cloudflare_origin_ssl_status ;;
      10) show_ssl_mode_status ;;
      11) show_ssl_mode_guide ;;
      12) disable_production_ssl ;;
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

show_local_ssl_menu() {
  local back_target="${1:-return}"
  local back_label="Main menu"
  while true; do
    echo
    echo "============================================================"
    echo "Local VM HTTPS / SSL"
    echo "============================================================"
    menu_location_note "Main menu > 8) Local VM HTTPS / SSL" "local-ssl-menu"
    echo "Use this for local VM domains such as ${SITE_NAME}."
    echo "Day-to-day setup: choose 1) Local SSL Wizard (same as: $(toolkit_cmd local-ssl-wizard))."
    echo "For public domains, use Main menu > 9) Production HTTPS / SSL."
    echo
    print_two_column_menu       "1) Local SSL Wizard"       "2) Local SSL Status"       "3) Local SSL Guide"       "4) Trusted mkcert Guide"       "5) Browser Trust Check"       "6) Install/Replace Cert"       "7) Verify Local SSL"       "8) Create Self-Signed Cert"       "9) Configure Local SSL"       "10) Disable Local SSL"       "11) Verify SSL Rollback"       "12) Change Local Domain"       "13) Local Domain / Host DNS Status"       "14) Local Access Doctor"       "15) Print Host /etc/hosts Command"       "16) SSL/HTTPS Roadmap"       "17) Local Security Profile"
    menu_footer back "$back_label"
    local ssl_choice=""
    menu_read_choice ssl_choice

    case "$ssl_choice" in
      1) run_local_ssl_wizard ;;
      2) show_ssl_status ;;
      3) show_local_ssl_guide ;;
      4) show_mkcert_local_ssl_guide ;;
      5) show_browser_trust_check_guide ;;
      6) install_local_ssl_cert ;;
      7) verify_local_ssl ;;
      8) create_self_signed_local_cert ;;
      9) configure_local_ssl ;;
      10) disable_local_ssl ;;
      11) verify_ssl_rollback ;;
      12) change_local_domain_wizard ;;
      13) show_local_domain_status ;;
      14) local_access_doctor ;;
      15) show_host_hosts_command ;;
      16) show_ssl_roadmap_guide ;;
      17) configure_local_vm_firewall ;;
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
