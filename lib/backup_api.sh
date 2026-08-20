# shellcheck shell=bash
[[ -n "${_ERPNEXT_DEV_BACKUP_API_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_BACKUP_API_LOADED=1

backup_api_valid_args() {
  [[ "$STABLE_API_JSON" -eq 1 && "$STABLE_API_INVALID_ARGUMENTS" -eq 0 &&
    -z "${ACTION_ARG:-}" && -z "${ACTION_ARG2:-}" ]]
}

backup_api_require_access() {
  if ((EUID != 0)) && [[ "${ERPNEXT_DEV_BACKUP_API_TEST_ALLOW_NONROOT:-0}" != 1 ]]; then
    api_fail "$1" "$ERPNEXT_DEV_API_EXIT_PERMISSION" permission_denied \
      "Protected backup evidence requires root access."
    return $?
  fi
}

backup_api_collect() {
  command python3 - "$1" "${SCRIPT_VERSION}" <<'PY'
import datetime, hashlib, json, os, pwd, re, stat, subprocess, sys

command, version = sys.argv[1:]
def permission_hook(kind,value,traceback):
    if issubclass(kind,PermissionError): raise SystemExit(77)
    sys.__excepthook__(kind,value,traceback)
sys.excepthook=permission_hook
now = datetime.datetime.now(datetime.timezone.utc)
issues = set()
LIMIT = 256
MAX = 65536
STATUS = {"HEALTHY", "DEGRADED", "CRITICAL", "UNKNOWN"}

def utc(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")

def timestamp(value):
    if not value: return None
    try:
        parsed=datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None: parsed=parsed.replace(tzinfo=datetime.timezone.utc)
        return parsed.astimezone(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    except (ValueError,TypeError): return None

def hostname(value):
    return value if isinstance(value,str) and re.fullmatch(r"(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?",value) else None

try: trusted_uids={0,pwd.getpwnam(os.environ.get("FRAPPE_USER","frappe")).pw_uid}
except KeyError: trusted_uids={0}
if os.environ.get("ERPNEXT_DEV_BACKUP_API_TEST_ALLOW_NONROOT")=="1": trusted_uids.add(os.geteuid())

def evidence(path, allowed, issue, required=False):
    if not path or not os.path.lexists(path): return None
    try:
        before=os.lstat(path)
        if not stat.S_ISREG(before.st_mode) or before.st_mode & 0o022 or before.st_size>MAX or before.st_uid not in trusted_uids:
            issues.add(issue); return False
        fd=os.open(path,os.O_RDONLY|getattr(os,"O_NOFOLLOW",0))
        try: raw=os.read(fd,MAX+1); after=os.fstat(fd)
        finally: os.close(fd)
        if len(raw)>MAX or (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns):
            issues.add("backup_evidence_changed" if required else issue); return False
        text=raw.decode("utf-8")
        if any(ord(c)<32 and c not in "\n\r\t" for c in text): raise ValueError()
        out={}
        for line in text.splitlines():
            if not line or line.lstrip().startswith("#"): continue
            match=re.fullmatch(r"([A-Z][A-Z0-9_]*)=(.*)",line)
            if not match or match.group(1) not in allowed or match.group(1) in out: raise ValueError()
            value=match.group(2)
            if value!=value.strip() or any(ord(c)<32 for c in value): raise ValueError()
            out[match.group(1)]=value
        return out
    except PermissionError: raise
    except (OSError,UnicodeError,ValueError): issues.add(issue); return False

config_allowed={"CONFIG_SCHEMA","DEPLOYMENT_ENGINE","SITE_NAME","PRODUCTION_DOMAIN"}
config_path=os.environ.get("CONFIG_FILE","/etc/erpnext-dev/config.env")
legacy=os.environ.get("LEGACY_CONFIG_FILE","")
config=evidence(config_path,config_allowed,"configuration_unavailable",True)
if config is None and legacy: config=evidence(legacy,config_allowed,"configuration_unavailable",True)
if config is False: config=None
config_trusted=config is not None
if config is None:
    testing=os.environ.get("ERPNEXT_DEV_BACKUP_API_TEST_ALLOW_NONROOT")=="1"
    env_engine=os.environ.get("BACKUP_API_ENGINE","") if testing else ""
    env_site=os.environ.get("BACKUP_API_SITE","") if testing else ""
    engine=env_engine if env_engine in ("native","docker") else None
    site=hostname(env_site)
    if not engine and not site: issues.add("configuration_unavailable")
else:
    engine=config.get("DEPLOYMENT_ENGINE") if config.get("DEPLOYMENT_ENGINE") in ("native","docker") else None
    site=hostname(config.get("SITE_NAME") or config.get("PRODUCTION_DOMAIN"))
deployment={"engine":engine,"site":site}

def safe_dir(path):
    try:
        st=os.lstat(path)
        return stat.S_ISDIR(st.st_mode) and not (st.st_mode&0o022) and st.st_uid in trusted_uids
    except PermissionError: raise
    except OSError: return False

def bounded_names(path,limit):
    names=[]; truncated=False
    with os.scandir(path) as entries:
        for entry in entries:
            if len(names)>=limit: truncated=True; break
            names.append(entry.name)
    return sorted(names),truncated

def component(p):
    try:
        st=os.lstat(p)
        ok=stat.S_ISREG(st.st_mode) and not(st.st_mode&0o022) and st.st_uid in trusted_uids
        return {"present":ok,"size_bytes":st.st_size if ok else None}, st if ok else None
    except PermissionError: raise
    except OSError: return {"present":False,"size_bytes":None},None

def classify_native(name):
    patterns=(("database",r"^(.*?)-database\.sql(?:\.gz)?$"),("private_files",r"^(.*?)-private-files\.tar(?:\.gz)?$"),
      ("public_files",r"^(.*?)-files\.tar(?:\.gz)?$"),("site_configuration",r"^(.*?)-site_config_backup\.json$"),
      ("checksum_manifest",r"^(.*?)-(?:SHA256SUMS|checksums\.sha256)$"))
    for kind,pat in patterns:
        m=re.fullmatch(pat,name)
        if m:return kind,m.group(1)
    m=re.fullmatch(r"(.*?)\.sql(?:\.gz)?$",name)
    if m:return "database",m.group(1)
    return None,None

root=os.environ.get("BACKUP_API_BACKUP_DIR","")
if not root:
    root=(os.path.join(os.environ.get("DOCKER_BACKUP_DIR","/var/backups/erpnext-dev/docker"),site or "") if engine=="docker"
          else os.path.join(os.environ.get("BENCH_DIR","/home/frappe/frappe/frappe-bench"),"sites",site or "","private","backups"))
sets={}; truncated=False
if not os.path.lexists(root): issues.add("backup_directory_missing")
elif not safe_dir(root): issues.add("backup_directory_unsafe")
else:
    try: names,root_truncated=bounded_names(root,LIMIT)
    except PermissionError: raise
    except OSError: names=[]; issues.add("backup_directory_unreadable")
    if 'root_truncated' in locals() and root_truncated: truncated=True; issues.add("backup_scan_truncated")
    if engine=="docker":
        for name in names:
            if not re.fullmatch(r"[A-Za-z0-9._-]{1,160}",name): continue
            directory=os.path.join(root,name)
            if not safe_dir(directory): continue
            try: children,child_truncated=bounded_names(directory,32)
            except OSError: continue
            if child_truncated: truncated=True; issues.add("backup_scan_truncated")
            rec=sets.setdefault(name,{})
            for child in children:
                low=child.lower(); p=os.path.join(directory,child)
                kind=("database" if re.search(r"database|\.sql",low) else "private_files" if "private-files" in low else
                  "public_files" if re.search(r"(^|-)files\.tar",low) else "site_configuration" if "site_config" in low else
                  "checksum_manifest" if child=="SHA256SUMS" else None)
                if kind: rec[kind]=(p,)
    else:
        for name in names:
            kind,key=classify_native(name)
            if kind and key: sets.setdefault(key,{})[kind]=(os.path.join(root,name),)

records=[]
for identity,parts in sets.items():
    comps={}; mtimes=[]; total=0
    for key in ("database","public_files","private_files","site_configuration","checksum_manifest"):
        c,st=component(parts.get(key,("",))[0]); comps[key]=c
        if st: mtimes.append(st.st_mtime); total+=st.st_size
    required=all(comps[k]["present"] for k in ("database","public_files","private_files","site_configuration"))
    completeness="complete" if required else "partial" if any(c["present"] for c in comps.values()) else "missing"
    created=max(mtimes) if mtimes else 0
    opaque=hashlib.sha256((str(engine)+"\0"+str(site)+"\0"+identity).encode()).hexdigest()
    records.append({"id":opaque,"created_at":utc(created) if created else None,"age_hours":max(0,int((now.timestamp()-created)//3600)) if created else None,
      "completeness":completeness,"total_size_bytes":total if mtimes else None,"components":comps,"_identity":identity,"_mtime":created})
records.sort(key=lambda x:(x["_mtime"],x["id"]),reverse=True)
latest=records[0] if records else None
if latest:
    latest.pop("_identity",None); latest.pop("_mtime",None)
    if latest["completeness"]!="complete": issues.add("backup_set_partial")
else: issues.add("backup_set_missing")
for item in records[1:]: item.pop("_identity",None); item.pop("_mtime",None)
complete=sum(r["completeness"]=="complete" for r in records)
local_status="HEALTHY" if latest and latest["completeness"]=="complete" and not truncated else "DEGRADED" if latest else "CRITICAL"
if "backup_directory_unsafe" in issues or "backup_directory_unreadable" in issues: local_status="UNKNOWN"
if not config_trusted: local_status="UNKNOWN"
local={"status":local_status,"storage_kind":"docker-host-artifact" if engine=="docker" else "native-site-directory" if engine=="native" else None,
 "scan_truncated":truncated,"total_observed_set_count":len(records) if safe_dir(root) else None,"complete_set_count":complete if safe_dir(root) else None,"latest_set":latest}

def state_summary(config_path,state_path,config_keys,prefix):
    cfg=evidence(config_path,config_keys,prefix+"_not_configured") if config_path else None
    configured=isinstance(cfg,dict) and bool(cfg)
    allowed={"LAST_STATUS","LAST_RUN_AT","LAST_DETAIL","LAST_TARGET"}
    state=evidence(state_path,allowed,prefix+"_last_run_failed") if state_path else None
    raw=state.get("LAST_STATUS","") if isinstance(state,dict) else ""
    last="success" if raw in ("OK","SUCCESS") else "failed" if raw in ("FAIL","FAILED","ERROR") else "unknown"
    if not configured: issues.add(prefix+"_not_configured")
    if last=="failed": issues.add(prefix+"_last_run_failed")
    status="HEALTHY" if configured and last=="success" else "CRITICAL" if last=="failed" else "DEGRADED"
    return {"status":status,"configured":configured,"last_result_status":last,"last_run_at":timestamp(state.get("LAST_RUN_AT")) if isinstance(state,dict) else None}

off_vm=state_summary(os.environ.get("OFF_VM_BACKUP_CONFIG_FILE","/etc/erpnext-dev/off-vm-backup.env"),os.environ.get("OFF_VM_BACKUP_STATE_FILE","/etc/erpnext-dev/off-vm-backup.state"),
 {"OFF_VM_BACKUP_TARGET","OFF_VM_BACKUP_SSH_IDENTITY","OFF_VM_BACKUP_RSYNC_DELETE","OFF_VM_STRICT_HOST_KEY","OFF_VM_KNOWN_HOSTS_FILE"},"off_vm")
obj=state_summary(os.environ.get("OBJECT_BACKUP_CONFIG_FILE","/etc/erpnext-dev/object-backup.env"),os.environ.get("OBJECT_BACKUP_STATE_FILE","/etc/erpnext-dev/object-backup.state"),
 {"OBJECT_RCLONE_REMOTE","OBJECT_BUCKET","OBJECT_PREFIX","OBJECT_BACKUP_ENABLED"},"object_storage")

enabled=active=None; next_run=None; supported=False
timer=os.environ.get("BACKUP_SCHEDULE_TIMER","erpnext-dev-backup.timer")
if re.fullmatch(r"erpnext-dev-backup\.timer",timer) and os.environ.get("BACKUP_API_NO_SYSTEMCTL","0")!="1":
    try:
        def query(*args): return subprocess.run(["systemctl",*args],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,timeout=2,check=False)
        e=query("is-enabled",timer); a=query("is-active",timer); supported=e.returncode not in (1,4) or a.returncode not in (1,4)
        enabled=e.returncode==0; active=a.returncode==0
        n=query("show",timer,"--property=NextElapseUSecRealtime","--value"); next_run=timestamp(n.stdout.strip()) if n.returncode==0 else None
    except (OSError,subprocess.TimeoutExpired): supported=False
if os.environ.get("BACKUP_API_SCHEDULE_ENABLED") in ("true","false"):
    supported=True; enabled=os.environ["BACKUP_API_SCHEDULE_ENABLED"]=="true"; active=os.environ.get("BACKUP_API_SCHEDULE_ACTIVE","false")=="true"; next_run=timestamp(os.environ.get("BACKUP_API_SCHEDULE_NEXT"))
configured=enabled is not None
if enabled is False: issues.add("schedule_disabled")
if active is False: issues.add("schedule_inactive")
schedule={"status":"HEALTHY" if enabled and active else "DEGRADED" if supported else "UNKNOWN","supported":supported,"configured":configured,"enabled":enabled,"active":active,"next_run_at":next_run}
keep=os.environ.get("BACKUP_RETENTION_KEEP_COMPLETE","14")
keep=int(keep) if keep.isdigit() and int(keep)>0 else 14
retention={"status":"HEALTHY" if complete and complete<=keep else "DEGRADED","configured_keep_count":keep,"complete_set_count":complete if safe_dir(root) else None,
 "cleanup_candidate_count":max(0,complete-keep) if safe_dir(root) else None,"backup_filesystem_used_percent":None}
if safe_dir(root):
    try:
        fs=os.statvfs(root); retention["backup_filesystem_used_percent"]=int(100*(fs.f_blocks-fs.f_bfree)/fs.f_blocks) if fs.f_blocks else 0
    except OSError: pass

if command=="backup-status":
    ranks={"HEALTHY":0,"DEGRADED":1,"CRITICAL":2,"UNKNOWN":3}
    overall=max((local_status,schedule["status"],off_vm["status"],obj["status"]),key=lambda s:ranks[s])
    if not config_trusted: overall="UNKNOWN"
    data={"toolkit_version":version,"observed_at":utc(now.timestamp()),"deployment":deployment,"overall_status":overall,"local":local,
      "schedule":schedule,"retention":retention,"off_vm":off_vm,"object_storage":obj,"issues":sorted(issues)}
else:
    rehearsal_path=os.environ.get("DOCKER_RESTORE_REHEARSAL_FILE","/etc/erpnext-dev/docker-restore-rehearsal.env") if engine=="docker" else os.environ.get("RESTORE_REHEARSAL_RECORD_FILE","/etc/erpnext-dev/restore-rehearsal.env")
    prefix="DOCKER_RESTORE_REHEARSAL_" if engine=="docker" else "RESTORE_REHEARSAL_"
    allowed={prefix+k for k in ("STATUS","RECORDED_AT","SITE","BACKUP_SET","LOGIN_VALIDATED","RESULT","MODE","TEMP_SITE","IMAGE","IMAGE_DIGEST","APPS","TOOLKIT_VERSION","TARGET_KIND","TARGET_LABEL","TARGET_IP","NOTES","RECORDED_BY_TOOLKIT_VERSION")}
    ev=evidence(rehearsal_path,allowed,"rehearsal_evidence_unsafe",True)
    recorded=isinstance(ev,dict) and bool(ev); successful=(ev.get(prefix+"STATUS")=="OK") if recorded else None
    ev_site=hostname(ev.get(prefix+"SITE")) if recorded else None; site_matches=(ev_site==site) if recorded and ev_site and site else None
    # Existing evidence stores the internal set identity; compare only by hashing it in memory.
    ev_set=ev.get(prefix+"BACKUP_SET") if recorded else None
    candidate_matches=(hashlib.sha256((str(engine)+"\0"+str(site)+"\0"+ev_set).encode()).hexdigest()==latest["id"]) if ev_set and latest else None
    login=None
    if recorded and prefix+"LOGIN_VALIDATED" in ev: login=ev[prefix+"LOGIN_VALIDATED"].lower() in ("true","yes","1")
    if not recorded and ev is not False: issues.add("rehearsal_missing")
    if successful is False: issues.add("rehearsal_failed")
    if site_matches is False: issues.add("rehearsal_site_mismatch")
    if candidate_matches is False: issues.add("rehearsal_candidate_mismatch")
    issues.add("deep_verification_not_performed")
    db=bool(latest and latest["components"]["database"]["present"]); full=bool(latest and latest["completeness"]=="complete")
    matching=bool(successful and site_matches is not False and candidate_matches is True)
    if successful is False or not db: overall="CRITICAL"
    elif full and matching: overall="HEALTHY"
    elif db: overall="DEGRADED"
    else: overall="UNKNOWN"
    if not config_trusted: overall="UNKNOWN"
    candidate={"available":db,"id":latest["id"] if latest else None,"created_at":latest["created_at"] if latest else None,"age_hours":latest["age_hours"] if latest else None,
      "completeness":latest["completeness"] if latest else "missing","database_available":db,
      "public_files_available":bool(latest and latest["components"]["public_files"]["present"]),"private_files_available":bool(latest and latest["components"]["private_files"]["present"]),
      "site_configuration_available":bool(latest and latest["components"]["site_configuration"]["present"]),"checksum_manifest_present":bool(latest and latest["components"]["checksum_manifest"]["present"]),"deep_verification_performed":False}
    rehearsal={"status":"HEALTHY" if matching else "CRITICAL" if successful is False else "DEGRADED" if recorded else "UNKNOWN","recorded":recorded,
      "recorded_at":timestamp(ev.get(prefix+"RECORDED_AT")) if recorded else None,"successful":successful,"site_matches":site_matches,"candidate_matches":candidate_matches,"login_validated":login}
    readiness={"database_restore_candidate":db,"full_restore_candidate":full,"matching_rehearsal_proven":matching,"deep_integrity_verified":False,"live_restore_performed":False}
    data={"toolkit_version":version,"observed_at":utc(now.timestamp()),"deployment":deployment,"overall_status":overall,"candidate":candidate,"rehearsal":rehearsal,"readiness":readiness,"issues":sorted(issues)}
sys.stdout.write(json.dumps(data,separators=(",",":"))+"\n")
PY
}

run_backup_restore_api() {
  local command_name="${1:-$STABLE_API_ACTION}" data output rc
  if ! backup_api_valid_args; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS" invalid_arguments \
      "$command_name accepts only --json and --no-color."
    return $?
  fi
  backup_api_require_access "$command_name" || return $?
  api_encoder_available || {
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE" unavailable "The JSON encoder is unavailable."
    return $?
  }
  set +e
  data="$(backup_api_collect "$command_name" 2>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 77 ]]; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_PERMISSION" permission_denied "Protected backup evidence could not be read."
    return $?
  fi
  if [[ "$rc" -ne 0 ]]; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE" unavailable "Backup evidence could not be safely observed."
    return $?
  fi
  if ! output="$(printf '%s\n' "$data" | api_encode operations "$command_name" 2>/dev/null)"; then
    api_fail "$command_name" "$ERPNEXT_DEV_API_EXIT_INTERNAL" internal_error "Backup response serialization failed."
    return $?
  fi
  printf '%s\n' "$output"
}
