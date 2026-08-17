# shellcheck shell=bash
[[ -n "${_ERPNEXT_DEV_DEPLOYMENT_INFO_LOADED:-}" ]] && return 0
_ERPNEXT_DEV_DEPLOYMENT_INFO_LOADED=1

DEPLOYMENT_INFO_MAX_CONFIG_BYTES=65536

deployment_info_collect() {
	local curated_csv
	curated_csv="$(app_profile_list | LC_ALL=C sort | paste -sd, -)"
	command python3 - "$CONFIG_FILE" "$LEGACY_CONFIG_FILE" "$SCRIPT_VERSION" \
		"$DEPLOYMENT_INFO_MAX_CONFIG_BYTES" "$curated_csv" <<'PY'
import json, os, re, stat, sys, tempfile

primary, legacy, toolkit_version, max_bytes, curated_raw = sys.argv[1:]
max_bytes = int(max_bytes)
curated = set(filter(None, curated_raw.split(",")))
allowed = {"CONFIG_SCHEMA", "INSTALLATION_PROFILE", "INSTALLATION_PROFILE_APPS",
           "DEPLOYMENT_ENGINE", "DEPLOYMENT_MODE", "RUNTIME_MODE", "DOCKER_MODE",
           "SITE_NAME", "PRODUCTION_DOMAIN"}

def blank():
    return {"engine": None, "engine_source": None, "installation_profile": None,
            "profile_source": None, "requested_applications": [], "deployment_mode": None,
            "runtime_mode": None, "docker_mode": None, "site_name": None, "public_domain": None}

def snapshot(path, directory, label):
    try:
        before = os.lstat(path)
    except FileNotFoundError:
        return "missing", None
    except PermissionError:
        return "unreadable", None
    except OSError:
        return "unreadable", None
    if stat.S_ISLNK(before.st_mode) or not stat.S_ISREG(before.st_mode):
        return "unsafe", None
    if before.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        return "unsafe", None
    if not before.st_mode & (stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH):
        return "unreadable", None
    if before.st_size > max_bytes:
        return "unsafe", None
    flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        descriptor = os.open(path, flags)
    except PermissionError:
        return "unreadable", None
    except OSError:
        return "unsafe", None
    try:
        current = os.fstat(descriptor)
        if ((current.st_dev, current.st_ino) != (before.st_dev, before.st_ino)
                or not stat.S_ISREG(current.st_mode)
                or current.st_mode & (stat.S_IWGRP | stat.S_IWOTH)
                or current.st_size > max_bytes):
            return "unsafe", None
        chunks, total = [], 0
        while True:
            chunk = os.read(descriptor, min(8192, max_bytes + 1 - total))
            if not chunk:
                break
            chunks.append(chunk); total += len(chunk)
            if total > max_bytes:
                return "unsafe", None
        raw = b"".join(chunks)
    except OSError:
        return "unreadable", None
    finally:
        os.close(descriptor)
    target = os.path.join(directory, label)
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        view = memoryview(raw)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                raise OSError("short snapshot write")
            view = view[written:]
    finally:
        os.close(fd)
    return "snapshot", target

def hostname(value):
    if not value or len(value) > 253 or re.fullmatch(r"[0-9.]+", value):
        return False
    if any(c in value for c in "/:@") or "://" in value:
        return False
    labels = value.split(".")
    return len(labels) >= 2 and all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label) for label in labels)

def parse(path):
    try:
        text = open(path, "r", encoding="utf-8", errors="strict", newline="").read()
    except (OSError, UnicodeError):
        return None
    values = {}
    for raw_line in text.splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)=(.*)", raw_line)
        if not match:
            candidate = re.match(r"([A-Z][A-Z0-9_]*)", raw_line)
            if candidate and candidate.group(1) in allowed:
                return None
            continue
        key, value = match.groups()
        if key not in allowed:
            continue
        if key in values or value != value.strip() or any(ord(char) < 32 or ord(char) == 127 for char in value):
            return None
        values[key] = value
    schema = values.get("CONFIG_SCHEMA")
    if schema not in (None, "2"):
        return None
    legacy_schema = schema is None
    engine = values.get("DEPLOYMENT_ENGINE")
    profile = values.get("INSTALLATION_PROFILE")
    engine_source = "explicit" if engine else None
    profile_source = "explicit" if profile else None
    if legacy_schema:
        if not engine:
            engine, engine_source = "native", "legacy-default"
        if not profile:
            profile, profile_source = "recommended", "legacy-default"
    elif not engine or not profile:
        return None
    if engine not in ("native", "docker") or profile not in ("recommended", "frappe-only", "advanced"):
        return None
    apps_raw = values.get("INSTALLATION_PROFILE_APPS", "")
    apps = [] if not apps_raw else apps_raw.split(",")
    if profile == "advanced":
        if legacy_schema or not apps or apps != sorted(apps) or len(apps) != len(set(apps)):
            return None
        if any(not re.fullmatch(r"[a-z][a-z0-9_]*", app) or app not in curated for app in apps):
            return None
    elif apps:
        return None
    deployment_mode = values.get("DEPLOYMENT_MODE") or None
    runtime_mode = values.get("RUNTIME_MODE") or None
    docker_mode = values.get("DOCKER_MODE") or None
    if deployment_mode not in (None, "development", "public-vm"):
        return None
    if runtime_mode not in (None, "dev", "production"):
        return None
    if docker_mode not in (None, "development", "production"):
        return None
    if engine == "docker" and docker_mode is None:
        return None
    if engine == "native":
        docker_mode = None
    site_name = values.get("SITE_NAME") or None
    public_domain = values.get("PRODUCTION_DOMAIN") or None
    if site_name is not None and not hostname(site_name):
        return None
    if public_domain is not None and not hostname(public_domain):
        return None
    return {"schema_version": "legacy" if legacy_schema else "2",
            "legacy": legacy_schema,
            "deployment": {"engine": engine, "engine_source": engine_source,
                "installation_profile": profile, "profile_source": profile_source,
                "requested_applications": apps, "deployment_mode": deployment_mode,
                "runtime_mode": runtime_mode, "docker_mode": docker_mode,
                "site_name": site_name, "public_domain": public_domain}}

def result(status, source=None, schema=None, deployment=None, issues=()):
    trusted = status in ("managed", "legacy-compatible")
    return {"toolkit_version": toolkit_version,
            "configuration": {"status": status, "source": source, "schema_version": schema},
            "deployment": deployment if deployment is not None else blank(),
            "observation": {"management_scope": "configuration-only" if trusted else "none",
                            "runtime_probed": False, "inventory_probed": False},
            "issues": sorted(set(issues))}

state_issue = {"missing": "configuration_missing", "unreadable": "configuration_unreadable",
               "unsafe": "configuration_unsafe", "invalid": "configuration_invalid"}
with tempfile.TemporaryDirectory(prefix="erpnext-dev-deployment-info-") as directory:
    os.chmod(directory, 0o700)
    p_state, p_snapshot = snapshot(primary, directory, "primary")
    l_state, l_snapshot = snapshot(legacy, directory, "legacy")
    if p_state != "missing":
        if p_state != "snapshot":
            output = result(p_state, issues=[state_issue[p_state]])
        else:
            p_data = parse(p_snapshot)
            if p_data is None:
                output = result("invalid", issues=["configuration_invalid"])
            else:
                l_data = parse(l_snapshot) if l_state == "snapshot" else None
                if l_data is not None and p_data["deployment"] != l_data["deployment"]:
                    output = result("conflict", issues=["configuration_conflict"])
                else:
                    status = "legacy-compatible" if p_data["legacy"] else "managed"
                    issues = ["legacy_configuration"] if p_data["legacy"] else []
                    output = result(status, "primary", p_data["schema_version"], p_data["deployment"], issues)
    elif l_state == "missing":
        output = result("missing", issues=["configuration_missing"])
    elif l_state != "snapshot":
        output = result(l_state, issues=[state_issue[l_state]])
    else:
        l_data = parse(l_snapshot)
        if l_data is None:
            output = result("invalid", issues=["configuration_invalid"])
        else:
            status = "legacy-compatible" if l_data["legacy"] else "managed"
            issues = ["legacy_configuration"] if l_data["legacy"] else []
            output = result(status, "legacy", l_data["schema_version"], l_data["deployment"], issues)
sys.stdout.write(json.dumps(output, separators=(",", ":")) + "\n")
PY
}

run_deployment_info() {
	if [[ "$STABLE_API_INVALID_ARGUMENTS" -eq 1 || -n "${ACTION_ARG:-}" || -n "${ACTION_ARG2:-}" ]]; then
		api_fail deployment-info "$ERPNEXT_DEV_API_EXIT_INVALID_ARGUMENTS" invalid_arguments \
			"deployment-info accepts only --json and --no-color."
		return $?
	fi
	local data output
	if ! api_encoder_available; then
		printf 'ERROR: required JSON encoder is unavailable.\n' >&2
		return "$ERPNEXT_DEV_API_EXIT_UNAVAILABLE"
	fi
	if ! data="$(deployment_info_collect 2>/dev/null)"; then
		api_fail deployment-info "$ERPNEXT_DEV_API_EXIT_INTERNAL" internal_error \
			"Deployment configuration could not be safely parsed."
		return $?
	fi
	if [[ "$STABLE_API_JSON" -eq 1 ]]; then
		if ! output="$(printf '%s\n' "$data" | api_encode deployment-info deployment-info 2>/dev/null)"; then
			api_fail deployment-info "$ERPNEXT_DEV_API_EXIT_INTERNAL" internal_error \
				"Deployment information serialization failed."
			return $?
		fi
		printf '%s\n' "$output"
	else
		printf '%s\n' "$data" | command python3 -c '
import json, sys
d = json.load(sys.stdin)
print("Configuration: " + d["configuration"]["status"])
print("Source: " + (d["configuration"]["source"] or "none"))
print("Engine: " + (d["deployment"]["engine"] or "unknown"))
print("Installation profile: " + (d["deployment"]["installation_profile"] or "unknown"))
print("Management scope: " + d["observation"]["management_scope"])
print("Runtime and inventory were not inspected; use status or health commands for observed state.")
'
	fi
}
