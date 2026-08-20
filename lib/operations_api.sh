# shellcheck shell=bash
[[ -n "${_ERPNEXT_DEV_OPERATIONS_API_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_OPERATIONS_API_LOADED=1

operations_api_require_access() {
  if (( EUID != 0 )) && [[ "${ERPNEXT_DEV_OPERATIONS_TEST_ALLOW_NONROOT:-0}" != "1" ]]; then
    api_fail "$1" "$ERPNEXT_DEV_API_EXIT_PERMISSION" permission_denied \
      "Protected operational evidence requires root access."
    return $?
  fi
}

operations_api_valid_args() {
  [[ "$STABLE_API_JSON" -eq 1 && "$STABLE_API_INVALID_ARGUMENTS" -eq 0 \
    && -z "${ACTION_ARG:-}" && -z "${ACTION_ARG2:-}" ]]
}

operations_api_snapshot_data() {
  command python3 - "${SCRIPT_VERSION}" <<'PY'
import json, os, re, sys
toolkit_version=sys.argv[1]
S={"HEALTHY","DEGRADED","CRITICAL","UNKNOWN"}
def status(name):
    value=os.environ.get(name,"UNKNOWN").upper()
    return value if value in S else "UNKNOWN"
def text(name):
    value=os.environ.get(name,"")
    value=re.sub(r"[\x00-\x1f\x7f\x1b]", " ", value)
    value=re.sub(r"https?://\S+", "[endpoint]", value)
    value=re.sub(r"/[^ ]+", "[path]", value)
    value=" ".join(value.split())[:240]
    return value or None
def number(name, floating=False):
    value=os.environ.get(name,"")
    try: return float(value) if floating else int(value)
    except (ValueError,TypeError): return None
def csv(name):
    return sorted(set(filter(None, os.environ.get(name,"").split(","))))
checks={
 "disk":("SNAPSHOT_DISK_STATUS","SNAPSHOT_DISK_DETAIL"), "inodes":("SNAPSHOT_INODE_STATUS","SNAPSHOT_INODE_DETAIL"),
 "memory":("SNAPSHOT_MEM_STATUS","SNAPSHOT_MEM_DETAIL"), "swap":("SNAPSHOT_SWAP_STATUS","SNAPSHOT_SWAP_DETAIL"),
 "load":("SNAPSHOT_LOAD_STATUS","SNAPSHOT_LOAD_DETAIL"), "cpu":("SNAPSHOT_CPU_STATUS","SNAPSHOT_CPU_DETAIL"),
 "http":("SNAPSHOT_HTTP_STATUS","SNAPSHOT_HTTP_DETAIL"), "database":("SNAPSHOT_DB_STATUS","SNAPSHOT_DB_DETAIL"),
 "redis":("SNAPSHOT_REDIS_STATUS","SNAPSHOT_REDIS_DETAIL"), "workers":("SNAPSHOT_WORKERS_STATUS","SNAPSHOT_WORKERS_DETAIL"),
 "scheduler":("SNAPSHOT_SCHEDULER_STATUS","SNAPSHOT_SCHEDULER_DETAIL"), "queue":("SNAPSHOT_QUEUE_STATUS","SNAPSHOT_QUEUE_DETAIL"),
 "https":("SNAPSHOT_HTTPS_STATUS","SNAPSHOT_HTTPS_DETAIL"), "firewall":("SNAPSHOT_FIREWALL_STATUS","SNAPSHOT_FIREWALL_DETAIL"),
 "fail2ban":("SNAPSHOT_FAIL2BAN_STATUS","SNAPSHOT_FAIL2BAN_DETAIL"), "integrity":("SNAPSHOT_INTEGRITY_STATUS","SNAPSHOT_INTEGRITY_DETAIL")}
issues=sorted("%s_%s"%(k,status(v[0]).lower()) for k,v in checks.items() if status(v[0])!="HEALTHY")
data={
 "toolkit_version":toolkit_version, "observed_at":os.environ.get("SNAPSHOT_GENERATED_AT"),
 "deployment":{"engine":os.environ.get("SNAPSHOT_ENGINE") if os.environ.get("SNAPSHOT_ENGINE") in ("native","docker") else None,
   "site":text("SNAPSHOT_SITE"), "installation_profile":os.environ.get("SNAPSHOT_PROFILE") or None,
   "reconciliation":os.environ.get("SNAPSHOT_RECONCILIATION") or None},
 "overall_status":status("SNAPSHOT_OVERALL"),
 "resources":{"status":status("SNAPSHOT_HOST_STATUS"),"disk_used_percent":number("SNAPSHOT_DISK_PERCENT"),
   "inode_used_percent":number("SNAPSHOT_INODE_PERCENT"),"memory_available_percent":number("SNAPSHOT_MEM_AVAIL_PCT"),
   "memory_available_kb":number("SNAPSHOT_MEM_AVAILABLE_KB"),"memory_total_kb":number("SNAPSHOT_MEM_TOTAL_KB"),
   "swap_used_percent":number("SNAPSHOT_SWAP_PERCENT"),"load_1m":number("SNAPSHOT_LOAD1",True),
   "cpu_cores":number("SNAPSHOT_CORES"),"cpu_used_percent":number("SNAPSHOT_CPU_PERCENT"),
   "iowait_percent":number("SNAPSHOT_IOWAIT_PERCENT"),"uptime_seconds":number("SNAPSHOT_UPTIME_SEC"),
   "reboot_required": True if "required" in (text("SNAPSHOT_REBOOT_DETAIL") or "") and "no reboot" not in (text("SNAPSHOT_REBOOT_DETAIL") or "") else False},
 "application":{"status":status("SNAPSHOT_APP_STATUS"),"http_status":status("SNAPSHOT_HTTP_STATUS"),
   "http_code":number("SNAPSHOT_HTTP_CODE"),"http_latency_ms":number("SNAPSHOT_HTTP_MS"),
   "database_status":status("SNAPSHOT_DB_STATUS"),"redis_status":status("SNAPSHOT_REDIS_STATUS"),
   "workers_status":status("SNAPSHOT_WORKERS_STATUS"),"worker_count":number("SNAPSHOT_WORKERS_COUNT"),
   "scheduler_status":status("SNAPSHOT_SCHEDULER_STATUS"),"queue_status":status("SNAPSHOT_QUEUE_STATUS"),
   "queue_depth":number("SNAPSHOT_QUEUE_DEPTH")},
 "runtime":{"status":status("SNAPSHOT_RUNTIME_LAYER_STATUS"),"docker_running":number("SNAPSHOT_DOCKER_RUNNING"),
   "docker_total":number("SNAPSHOT_DOCKER_TOTAL"),"docker_max_restarts":number("SNAPSHOT_DOCKER_MAX_RESTARTS") if os.environ.get("SNAPSHOT_ENGINE")=="docker" else None},
 "protection":{"status":status("SNAPSHOT_PROTECTION_STATUS"),"https_status":status("SNAPSHOT_HTTPS_STATUS"),
   "certificate_days_remaining":number("SNAPSHOT_CERT_DAYS"),"firewall_status":status("SNAPSHOT_FIREWALL_STATUS"),
   "fail2ban_status":status("SNAPSHOT_FAIL2BAN_STATUS"),"integrity_status":status("SNAPSHOT_INTEGRITY_STATUS"),
   "backup":{"local_status":status("SNAPSHOT_BACKUP_STATUS"),"local_age_hours":number("SNAPSHOT_BACKUP_AGE"),
      "off_vm_status":status("SNAPSHOT_OFFVM_STATUS"),"object_status":status("SNAPSHOT_OBJECT_STATUS"),
      "restore_rehearsal_status":status("SNAPSHOT_REHEARSAL_STATUS")}},
 "healing":{"mode":os.environ.get("SNAPSHOT_HEALING_MODE","monitor"),"status":os.environ.get("SNAPSHOT_HEALING_STATE","observing"),"would_heal":None},
 "checks":{k:{"status":status(v[0]),"detail":text(v[1])} for k,v in checks.items()},
 "issues":issues}
sys.stdout.write(json.dumps(data,separators=(",",":"))+"\n")
PY
}

operations_api_normalized_config() {
  command python3 - "${CONFIG_FILE:-/etc/erpnext-dev/config.env}" "${LEGACY_CONFIG_FILE:-}" <<'PY'
import os,re,stat,sys
allowed={"CONFIG_SCHEMA","DEPLOYMENT_ENGINE","INSTALLATION_PROFILE","DEPLOYMENT_MODE","RUNTIME_MODE","DOCKER_MODE","SITE_NAME","PRODUCTION_DOMAIN"}
def read(path):
  if not path: return None
  try:
    st=os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_mode&0o022 or st.st_size>65536: return None
    fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0)); raw=os.read(fd,65537); after=os.fstat(fd); os.close(fd)
    if (st.st_ino,st.st_size,st.st_mtime_ns)!=(after.st_ino,after.st_size,after.st_mtime_ns): return None
    text=raw.decode("utf-8")
  except (OSError,UnicodeError): return None
  out={}
  for line in text.splitlines():
    if not line or line.lstrip().startswith("#"): continue
    m=re.fullmatch(r"([A-Z][A-Z0-9_]*)=(.*)",line)
    if not m or m.group(1) not in allowed: continue
    if m.group(1) in out or m.group(2)!=m.group(2).strip() or any(ord(c)<32 for c in m.group(2)): return None
    out[m.group(1)]=m.group(2)
  return out
values=read(sys.argv[1])
if values is None and not os.path.lexists(sys.argv[1]): values=read(sys.argv[2])
values=values or {}
engine=values.get("DEPLOYMENT_ENGINE",""); profile=values.get("INSTALLATION_PROFILE","")
if engine not in ("native","docker"): engine=""
if profile not in ("recommended","frappe-only","advanced"): profile=""
mode=values.get("DEPLOYMENT_MODE",""); runtime=values.get("RUNTIME_MODE",""); docker=values.get("DOCKER_MODE","")
if mode not in ("development","public-vm"): mode=""
if runtime not in ("dev","production"): runtime=""
if docker not in ("development","production") or engine!="docker": docker=""
def host(value): return value if re.fullmatch(r"(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?",value or "") else ""
for value in (engine,profile,mode,runtime,docker,host(values.get("SITE_NAME")),host(values.get("PRODUCTION_DOMAIN"))): print(value)
PY
}

run_operations_api_snapshot() {
  local command_name="${1:-${STABLE_API_ACTION:-dashboard}}" data output config_data
  local -a normalized=()
  if ! operations_api_valid_args; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS" invalid_arguments \
      "$command_name accepts only --json and --no-color."
    return $?
  fi
  operations_api_require_access "$command_name" || return $?
  api_encoder_available || { api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE" unavailable "The JSON encoder is unavailable."; return $?; }
  if config_data="$(operations_api_normalized_config 2>/dev/null)"; then
    mapfile -t normalized <<<"$config_data"
    [[ -n "${normalized[0]:-}" ]] && DEPLOYMENT_ENGINE="${normalized[0]}"
    [[ -n "${normalized[1]:-}" ]] && INSTALLATION_PROFILE="${normalized[1]}"
    [[ -n "${normalized[2]:-}" ]] && DEPLOYMENT_MODE="${normalized[2]}"
    [[ -n "${normalized[3]:-}" ]] && RUNTIME_MODE="${normalized[3]}"
    [[ -n "${normalized[4]:-}" ]] && DOCKER_MODE="${normalized[4]}"
    [[ -n "${normalized[5]:-}" ]] && SITE_NAME="${normalized[5]}"
    PRODUCTION_DOMAIN="${normalized[6]:-}"
    export DEPLOYMENT_ENGINE INSTALLATION_PROFILE DEPLOYMENT_MODE RUNTIME_MODE DOCKER_MODE SITE_NAME PRODUCTION_DOMAIN
  fi
  HEALTH_SNAPSHOT_STABLE_API=1
  export HEALTH_SNAPSHOT_STABLE_API
  set -a
  if ! health_snapshot_collect >/dev/null 2>&1; then
    set +a
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE" unavailable "Operational evidence could not be collected."
    return $?
  fi
  set +a
  if ! data="$(operations_api_snapshot_data 2>/dev/null)" || ! output="$(printf '%s\n' "$data" | api_encode operations "$command_name" 2>/dev/null)"; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_INTERNAL" internal_error "Operational response serialization failed."
    return $?
  fi
  printf '%s\n' "$output"
}

operations_api_incidents_data() {
  command python3 - "${HEALTH_LIB_DIR}/incidents" "${SCRIPT_VERSION}" <<'PY'
import datetime,json,os,re,stat,sys
root,version=sys.argv[1:]
issues=[]; records=[]; limit=20
allowed={"id","timestamp","previous_status","status","site","host","application","http","protection","would_heal"}
statuses={"HEALTHY","DEGRADED","CRITICAL","UNKNOWN"}
def reject(issue): issues.append(issue)
if os.path.isdir(root):
  try: names=sorted(os.listdir(root))
  except OSError: names=[]; reject("incident_directory_unreadable")
  for name in names:
    if name=="latest.json" or not re.fullmatch(r"[0-9A-Za-z._-]{1,128}\.json",name):
      if name!="latest.json": reject("incident_name_invalid")
      continue
    path=os.path.join(root,name)
    try:
      before=os.lstat(path)
      if not stat.S_ISREG(before.st_mode): reject("incident_not_regular"); continue
      if before.st_mode & 0o022: reject("incident_permissions_unsafe"); continue
      if before.st_size>65536: reject("incident_oversized"); continue
      fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0)); raw=os.read(fd,65537); after=os.fstat(fd); os.close(fd)
      if (before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_ino,after.st_size,after.st_mtime_ns): reject("incident_changed_during_read"); continue
      def pairs(items):
        out={}
        for k,v in items:
          if k in out: raise ValueError("duplicate")
          out[k]=v
        return out
      value=json.loads(raw.decode("utf-8"),object_pairs_hook=pairs)
      if not isinstance(value,dict) or not set(value)<=allowed: raise ValueError("shape")
      iid=value.get("id"); ts=value.get("timestamp")
      if iid!=name[:-5] or not re.fullmatch(r"[0-9A-Za-z._-]{1,128}",iid or ""): raise ValueError("id")
      datetime.datetime.strptime(ts,"%Y-%m-%dT%H:%M:%SZ")
      for key in ("previous_status","status","host","application","http","protection"):
        if value.get(key) not in statuses: raise ValueError("status")
      if not isinstance(value.get("site"),str) or len(value["site"])>253 or any(ord(c)<32 for c in value["site"]): raise ValueError("site")
      wh=value.get("would_heal")
      if not isinstance(wh,str) or len(wh)>64 or not re.fullmatch(r"[a-z0-9_-]+",wh): raise ValueError("would_heal")
      records.append({"id":iid,"timestamp":ts,"previous_status":value["previous_status"],"status":value["status"],"site":value["site"],
        "host_status":value["host"],"application_status":value["application"],"http_status":value["http"],"protection_status":value["protection"],"would_heal":wh})
    except (OSError,UnicodeError,ValueError,TypeError,KeyError): reject("incident_invalid")
records.sort(key=lambda x:(x["timestamp"],x["id"]),reverse=True)
truncated=len(records)>limit; records=records[:limit]
out={"toolkit_version":version,"limit":limit,"count":len(records),"truncated":truncated,"incidents":records,"issues":sorted(set(issues))}
sys.stdout.write(json.dumps(out,separators=(",",":"))+"\n")
PY
}

run_operations_api_incidents() {
  local data output command_name=incidents
  if ! operations_api_valid_args; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS" invalid_arguments "incidents accepts only --json and --no-color."
    return $?
  fi
  operations_api_require_access "$command_name" || return $?
  api_encoder_available || { api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE" unavailable "The JSON encoder is unavailable."; return $?; }
  if ! data="$(operations_api_incidents_data 2>/dev/null)" || ! output="$(printf '%s\n' "$data" | api_encode operations "$command_name" 2>/dev/null)"; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_INTERNAL" internal_error "Incident records could not be safely read."
    return $?
  fi
  printf '%s\n' "$output"
}
