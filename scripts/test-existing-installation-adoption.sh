#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
assertions=0
assert() {
  local label="$1"
  shift
  assertions=$((assertions + 1))
  if "$@"; then printf 'OK: %s\n' "$label"; else
    printf 'FAIL: %s\n' "$label"
    failures=$((failures + 1))
  fi
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  assert "$label" test "$expected" = "$actual"
}
assert_has() {
  local label="$1" file="$2" text="$3"
  assert "$label" grep -Fq -- "$text" "$file"
}

SUDO=""
CONFIG_FILE="$tmp/config"
LEGACY_CONFIG_FILE="$tmp/legacy"
OPERATION_STATE_DIR="$tmp/operations"
ADOPTION_RECOVERY_DIR="$tmp/recovery"
LOCK_FILE="$tmp/locks/toolkit.lock"
BENCH_PARENT="$tmp"
BENCH_NAME=default-bench
BENCH_DIR="$BENCH_PARENT/$BENCH_NAME"
FRAPPE_USER="$(id -un)"
DEPLOYMENT_ENGINE=native
DOCKER_MODE=development
INSTALLATION_PROFILE=existing
INSTALLATION_PROFILE_APPS=""
SITE_NAME=site.test
SITE_NAME_ENV_PROVIDED=1
SITE_NAME_SOURCE="test"
HOST_OS_ENV_PROVIDED=1
HOST_OS=linux
DOCKER_SITE_NAME=site.test
DOCKER_PROJECT_NAME=erpnext-dev
DOCKER_WORKDIR="$tmp/docker"
DOCTOR_FORMAT=human
ERPNEXT_DEV_INVENTORY_PROBE_TIMEOUT=2
ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1

# shellcheck source=../lib/common.sh
set +u
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/profile.sh
source "$ROOT_DIR/lib/profile.sh"
# shellcheck source=../lib/config.sh
source "$ROOT_DIR/lib/config.sh"
# shellcheck source=../lib/apps.sh
source "$ROOT_DIR/lib/apps.sh"
# shellcheck source=../lib/inventory.sh
source "$ROOT_DIR/lib/inventory.sh"
# shellcheck source=../lib/planner.sh
source "$ROOT_DIR/lib/planner.sh"
# shellcheck source=../lib/docker.sh
source "$ROOT_DIR/lib/docker.sh"
# shellcheck source=../lib/adoption.sh
source "$ROOT_DIR/lib/adoption.sh"
set -u
GREEN=""
RESET=""

make_native() {
  local bench="$1" site="$2" version="${3:-16.0.0}" remote="${4:-https://github.com/frappe/frappe.git}"
  mkdir -p "$bench/apps/frappe/frappe" "$bench/apps/custom_app" "$bench/sites/$site"
  printf '__version__ = "%s"\n' "$version" >"$bench/apps/frappe/frappe/__init__.py"
  printf 'frappe\ncustom_app\n' >"$bench/sites/$site/apps.txt"
  git -C "$bench/apps/frappe" init -q
  git -C "$bench/apps/frappe" config user.email test@example.invalid
  git -C "$bench/apps/frappe" config user.name Test
  git -C "$bench/apps/frappe" add .
  git -C "$bench/apps/frappe" commit -qm initial
  git -C "$bench/apps/frappe" remote add origin "$remote"
  printf 'custom\n' >"$bench/apps/custom_app/code.txt"
  git -C "$bench/apps/custom_app" init -q
  git -C "$bench/apps/custom_app" config user.email test@example.invalid
  git -C "$bench/apps/custom_app" config user.name Test
  git -C "$bench/apps/custom_app" add .
  git -C "$bench/apps/custom_app" commit -qm initial
  git -C "$bench/apps/custom_app" remote add origin https://example.invalid/custom_app.git
  chmod -R go-w "$bench"
}

make_custom_code() {
  local dir="$1"
  mkdir -p "$dir"
  printf 'code\n' >"$dir/code.txt"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name Test
  git -C "$dir" add .
  git -C "$dir" commit -qm initial
  git -C "$dir" remote add origin "https://example.invalid/${dir##*/}.git"
  chmod -R go-w "$dir"
}

ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$tmp/absent"
adoption_discover
assert_eq "zero candidates" 0 "${#ADOPTION_CANDIDATES[@]}"

native="$tmp/native-bench"
make_native "$native" site.test
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
adoption_discover
assert_eq "one Native candidate" 1 "${#ADOPTION_CANDIDATES[@]}"
record="${ADOPTION_CANDIDATES[0]}"
IFS='|' read -r engine mode id site compatibility major apps fingerprint <<<"$record"
selector="$engine:$id:$site"
assert_eq "Native engine" native "$engine"
assert_eq "Native environment" development "$mode"
assert_eq "exact site" site.test "$site"
assert_eq "supported major" 16 "$major"
assert_eq "compatible candidate" compatible "$compatibility"
assert "unknown app preserved" grep -Eq '(^|,)custom_app(,|$)' <<<"$apps"
assert "Frappe preserved" grep -Eq '(^|,)frappe(,|$)' <<<"$apps"
assert "sanitized identity" grep -Eq '^n-[a-f0-9]{20}$' <<<"$id"
assert "secret-free fingerprint" grep -Eq '^[a-f0-9]{64}$' <<<"$fingerprint"
assert "exact selector accepted" adoption_select_exact "$selector"
if adoption_select_exact '' 2>/dev/null; then
  failures=$((failures + 1))
  printf 'FAIL: implicit selector rejected\n'
else printf 'OK: implicit selector rejected\n'; fi
if adoption_select_exact 'native:n-00000000000000000000:site.test' 2>/dev/null; then
  failures=$((failures + 1))
  printf 'FAIL: stale selector rejected\n'
else printf 'OK: stale selector rejected\n'; fi
if adoption_select_exact $'native:n-00000000000000000000:bad\nsite' 2>/dev/null; then
  failures=$((failures + 1))
  printf 'FAIL: hostile selector rejected\n'
else printf 'OK: hostile selector rejected\n'; fi

DOCTOR_FORMAT=json
adoption_render_preview >"$tmp/preview.json"
assert_has "JSON preview schema" "$tmp/preview.json" '"schema_version":2'
assert_has "JSON preview read-only" "$tmp/preview.json" '"read_only":true'
assert_has "JSON preview non-mutation" "$tmp/preview.json" '"mutation":false'
assert_has "preview shows applications" "$tmp/preview.json" custom_app
assert_has "preview shows fingerprint" "$tmp/preview.json" "$fingerprint"
assert "preview writes no config" test ! -e "$CONFIG_FILE"
assert "preview creates no journal" test ! -e "$OPERATION_STATE_DIR"
assert "preview acquires no lock" test ! -e "$LOCK_FILE"

second="$tmp/second-bench"
make_native "$second" other.test
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native:$second"
adoption_discover
assert_eq "multiple benches remain multiple" 2 "${#ADOPTION_CANDIDATES[@]}"
first_order="$(printf '%s\n' "${ADOPTION_CANDIDATES[@]}")"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$second:$native"
adoption_discover
assert_eq "deterministic candidate ordering" "$first_order" "$(printf '%s\n' "${ADOPTION_CANDIDATES[@]}")"

ln -s "$native" "$tmp/symlink-bench"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$tmp/symlink-bench"
adoption_discover
assert_eq "symlinked Bench rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
chmod 777 "$second"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$second"
adoption_discover
assert_eq "unsafe permissions rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
chmod 755 "$second"

old="$tmp/old-bench"
make_native "$old" old.test 13.0.0
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$old"
adoption_discover
assert_eq "unsupported major rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
wrong="$tmp/wrong-bench"
make_native "$wrong" wrong.test 16.0.0 https://example.invalid/frappe.git
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$wrong"
adoption_discover
assert_eq "incorrect core remote rejected" 0 "${#ADOPTION_CANDIDATES[@]}"

git_attack="$tmp/git-attack-bench"
make_native "$git_attack" attack.test
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$git_attack"
git_config="$git_attack/apps/frappe/.git/config"
cp "$git_config" "$tmp/git-config.safe"
mv "$git_config" "$git_config.real"
ln -s "$tmp/git-config.safe" "$git_config"
adoption_discover
assert_eq "symlinked Git config rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
rm "$git_config"
mv "$git_config.real" "$git_config"
for git_proof in HEAD index; do
  mv "$git_attack/apps/frappe/.git/$git_proof" "$git_attack/apps/frappe/.git/$git_proof.real"
  ln -s "$git_attack/apps/frappe/.git/$git_proof.real" "$git_attack/apps/frappe/.git/$git_proof"
  adoption_discover
  assert_eq "symlinked Git $git_proof rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
  rm "$git_attack/apps/frappe/.git/$git_proof"
  mv "$git_attack/apps/frappe/.git/$git_proof.real" "$git_attack/apps/frappe/.git/$git_proof"
done
mv "$git_attack/apps/frappe/.git/refs" "$git_attack/apps/frappe/.git/refs.real"
ln -s "$git_attack/apps/frappe/.git/refs.real" "$git_attack/apps/frappe/.git/refs"
adoption_discover
assert_eq "symlinked Git refs rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
rm "$git_attack/apps/frappe/.git/refs"
mv "$git_attack/apps/frappe/.git/refs.real" "$git_attack/apps/frappe/.git/refs"
mv "$git_attack/apps/frappe/.git/info" "$git_attack/apps/frappe/.git/info.real"
ln -s "$git_attack/apps/frappe/.git/info.real" "$git_attack/apps/frappe/.git/info"
adoption_discover
assert_eq "symlinked Git info rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
rm "$git_attack/apps/frappe/.git/info"
mv "$git_attack/apps/frappe/.git/info.real" "$git_attack/apps/frappe/.git/info"
mkdir -p "$git_attack/apps/frappe/.git/objects/info"
printf '%s\n' "$tmp" >"$git_attack/apps/frappe/.git/objects/info/alternates"
adoption_discover
assert_eq "Git object alternates rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
rm "$git_attack/apps/frappe/.git/objects/info/alternates"
printf '../outside\n' >"$git_attack/apps/frappe/.git/commondir"
adoption_discover
assert_eq "Git commondir rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
rm "$git_attack/apps/frappe/.git/commondir"

marker="$tmp/candidate-config-executed"
printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" >"$tmp/fsmonitor-marker"
chmod 755 "$tmp/fsmonitor-marker"
git -C "$git_attack/apps/frappe" config core.fsmonitor "$tmp/fsmonitor-marker"
git -C "$git_attack/apps/frappe" config core.hooksPath "$tmp/hostile-hooks"
mkdir -p "$tmp/hostile-hooks"
printf '#!/usr/bin/env bash\ntouch %q\n' "$marker" >"$tmp/hostile-hooks/post-index-change"
chmod 755 "$tmp/hostile-hooks/post-index-change"
adoption_discover
assert "repository execution-capable config is inert" test ! -e "$marker"
git -C "$git_attack/apps/frappe" config --unset core.fsmonitor
git -C "$git_attack/apps/frappe" config --unset core.hooksPath
printf '[include]\n\tpath = %s\n' "$tmp/outside-config" >>"$git_config"
adoption_discover
assert_eq "Git include configuration fails closed" 0 "${#ADOPTION_CANDIDATES[@]}"
cp "$tmp/git-config.safe" "$git_config"

filter_marker="$tmp/filter-executed"
printf '#!/usr/bin/env bash\ntouch %q\ncat\n' "$filter_marker" >"$tmp/filter-clean"
chmod 755 "$tmp/filter-clean"
printf 'tracked\n' >"$git_attack/apps/frappe/tracked.txt"
printf 'tracked.txt filter=hostile\n' >"$git_attack/apps/frappe/.gitattributes"
git -C "$git_attack/apps/frappe" add tracked.txt .gitattributes
git -C "$git_attack/apps/frappe" commit -qm filter-fixture
chmod -R go-w "$git_attack/apps/frappe/.git"
git -C "$git_attack/apps/frappe" config filter.hostile.clean "$tmp/filter-clean"
git -C "$git_attack/apps/frappe" config core.trustctime false
git -C "$git_attack/apps/frappe" config core.checkStat minimal
printf 'changed\n' >"$git_attack/apps/frappe/tracked.txt"
adoption_discover
assert_eq "candidate clean filter cannot execute" 0 "${#ADOPTION_CANDIDATES[@]}"
assert "candidate clean filter marker remains absent" test ! -e "$filter_marker"
git -C "$git_attack/apps/frappe" config --unset-all filter.hostile.clean
git -C "$git_attack/apps/frappe" config --unset core.trustctime
git -C "$git_attack/apps/frappe" config --unset core.checkStat
git -C "$git_attack/apps/frappe" checkout -q -- tracked.txt .gitattributes
chmod -R go-w "$git_attack/apps/frappe/.git"
printf '[core]\n\tworktree = %s\n' "$tmp/outside-worktree" >>"$git_config"
mkdir -p "$tmp/outside-worktree"
adoption_discover
assert_eq "external Git worktree rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
cp "$tmp/git-config.safe" "$git_config"

private_app="$tmp/private-app"
mkdir -p "$private_app"
printf 'VERSION=1.0\nBRANCH=main\nCOMMIT=%040d\nSOURCE=https://private-user:private-token@example.invalid/custom_app.git\nSTATE=clean\n' 1 >"$private_app/.inventory-meta"
INVENTORY_RECORDS=()
inventory_emit_app "native:$tmp" private_app "$private_app" 1
DOCTOR_FORMAT=json
private_json="$(inventory_emit_json)"
assert "private URL absent from inventory JSON" test "$private_json" != *private-token* -a "$private_json" != *private-user*
assert "private source digest retained" grep -Eq 'custom-source:[a-f0-9]{64}' <<<"$private_json"
DOCTOR_FORMAT=human

canonical_sites="$tmp/canonical-sites"
mkdir -p "$canonical_sites/prod.test"
printf 'frappe\nerpnext\n' >"$canonical_sites/apps.txt"
printf '{\n  "db_name": "prod_db",\n  "db_password": "host-only-secret"\n}\n' >"$canonical_sites/prod.test/site_config.json"
eval "$(declare -f inventory_run_probe | sed '1s/inventory_run_probe/inventory_run_probe_before_canonical/')"
inventory_run_probe() {
  [[ "${1:-}" == mariadb ]] && {
    printf '["frappe"]\n'
    return
  }
  inventory_run_probe_before_canonical "$@"
}
canonical_db_apps="$(inventory_docker_host_site_apps "$canonical_sites/prod.test" 172.30.0.10)"
assert_eq "canonical shared sites registry is host data" 'frappe' "$canonical_db_apps"
assert "canonical layout has no per-site apps registry" test ! -e "$canonical_sites/prod.test/apps.txt"
inventory_run_probe() { inventory_run_probe_before_canonical "$@"; }

git -C "$git_attack/apps/frappe" remote set-url origin local-untrusted-source
git -C "$git_attack/apps/frappe" config url.https://github.com/frappe/frappe.git.insteadOf local-untrusted-source
adoption_discover
assert_eq "URL rewrite cannot spoof raw source trust" 0 "${#ADOPTION_CANDIDATES[@]}"
git -C "$git_attack/apps/frappe" config --unset-all url.https://github.com/frappe/frappe.git.insteadOf
git -C "$git_attack/apps/frappe" remote set-url origin https://github.com/frappe/frappe.git
git -C "$git_attack/apps/frappe" remote add upstream https://example.invalid/conflict.git
adoption_discover
assert_eq "conflicting raw remotes rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
git -C "$git_attack/apps/frappe" remote remove upstream

global_marker="$tmp/global-config-executed"
printf '[core]\n\tfsmonitor = %s\n' "$tmp/fsmonitor-marker" >"$tmp/global.gitconfig"
GIT_CONFIG_GLOBAL="$tmp/global.gitconfig" GIT_CONFIG_SYSTEM="$tmp/global.gitconfig" adoption_discover
assert "global and system Git config are inert" test ! -e "$global_marker" -a ! -e "$marker"

adoption_discover
custom_source_fp="${ADOPTION_CANDIDATES[0]##*|}"
git -C "$git_attack/apps/custom_app" remote set-url origin https://private.example.invalid/second.git
adoption_discover
assert "custom raw source identity changes secret-free fingerprint" test "$custom_source_fp" != "${ADOPTION_CANDIDATES[0]##*|}"
printf '# dirty\n' >>"$native/apps/frappe/frappe/__init__.py"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
adoption_discover
assert_eq "dirty core rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
assert "dirty core outcome retained" grep -q '|dirty-unknown|' <<<"${ADOPTION_OUTCOMES[*]}"
git -C "$native/apps/frappe" checkout -q -- frappe/__init__.py
chmod go-w "$native/apps/frappe/frappe/__init__.py" "$native/apps/frappe/.git/index"
mv "$native/sites/site.test/apps.txt" "$native/sites/site.test/apps.missing"
adoption_discover
assert_eq "incomplete site inventory rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
assert "incomplete outcome retained" grep -q '|ambiguous|' <<<"${ADOPTION_OUTCOMES[*]}"
mv "$native/sites/site.test/apps.missing" "$native/sites/site.test/apps.txt"

mkdir -p "$native/sites/z.test"
adoption_discover
assert_eq "complete site followed by incomplete sibling publishes nothing" 0 "${#ADOPTION_CANDIDATES[@]}"
assert "partial-stack rejection remains visible" grep -q '|ambiguous|' <<<"${ADOPTION_OUTCOMES[*]}"
rmdir "$native/sites/z.test"

adoption_discover
base_fingerprint="${ADOPTION_CANDIDATES[0]##*|}"
git -C "$native/apps/frappe" commit --allow-empty -qm second-clean-commit
chmod -R go-w "$native/apps/frappe/.git"
adoption_discover
commit_fingerprint="${ADOPTION_CANDIDATES[0]##*|}"
assert "clean Frappe commit changes fingerprint" test "$base_fingerprint" != "$commit_fingerprint"
make_custom_code "$native/apps/sibling_app"
mkdir -p "$native/sites/sibling.test"
printf 'frappe\nsibling_app\n' >"$native/sites/sibling.test/apps.txt"
chmod -R go-w "$native/apps/sibling_app" "$native/sites/sibling.test"
adoption_discover
sibling_fingerprint="${ADOPTION_CANDIDATES[0]##*|}"
assert "sibling-site applications change selected-site fingerprint" test "$commit_fingerprint" != "$sibling_fingerprint"
rm -r "$native/apps/sibling_app" "$native/sites/sibling.test"

unsafe_parent="$tmp/unsafe-parent"
mkdir -p "$unsafe_parent/bench"
chmod 0777 "$unsafe_parent"
if adoption_path_safe "$unsafe_parent/bench"; then
  failures=$((failures + 1))
  printf 'FAIL: non-sticky writable parent rejected\n'
else printf 'OK: non-sticky writable parent rejected\n'; fi
assertions=$((assertions + 1))
chmod 0755 "$unsafe_parent"
proof_link="$native/sites/site.test/apps.txt"
mv "$proof_link" "$proof_link.real"
ln -s apps.txt.real "$proof_link"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
adoption_discover
assert_eq "symlinked proof file rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
rm "$proof_link"
mv "$proof_link.real" "$proof_link"
mv "$native/apps/custom_app/.git" "$native/apps/custom_app/.git.missing"
adoption_discover
assert_eq "missing application code record rejected" 0 "${#ADOPTION_CANDIDATES[@]}"
assert "missing code record is dirty or unknown" grep -q '|dirty-unknown|missing-code-record' <<<"${ADOPTION_OUTCOMES[*]}"
mv "$native/apps/custom_app/.git.missing" "$native/apps/custom_app/.git"

docker_dev="$tmp/docker-dev"
mkdir -p "$docker_dev"
touch "$docker_dev/compose.yaml"
printf 'ENGINE=docker\nMODE=development\nPROJECT=dev-project\nSITE=dev.test\nFRAPPE_MAJOR=16\nIMAGE_DIGEST=sha256:%064d\nAPPS=frappe,custom_app\nRECONSTRUCTIBLE=false\n' 0 >"$docker_dev/.toolkit-adoption-fixture"
chmod -R go-w "$docker_dev"
ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$docker_dev"
adoption_discover
assert_eq "one Docker development candidate" 1 "${#ADOPTION_CANDIDATES[@]}"
docker_prod="$tmp/docker-prod"
mkdir -p "$docker_prod"
touch "$docker_prod/compose.yaml"
printf 'ENGINE=docker\nMODE=production\nPROJECT=prod-project\nSITE=prod.test\nFRAPPE_MAJOR=16\nIMAGE_DIGEST=sha256:%064d\nAPPS=frappe,erpnext\nRECONSTRUCTIBLE=true\n' 1 >"$docker_prod/.toolkit-adoption-fixture"
chmod -R go-w "$docker_prod"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$docker_prod"
adoption_discover
assert_eq "one Docker production candidate" 1 "${#ADOPTION_CANDIDATES[@]}"
sed -i 's/RECONSTRUCTIBLE=true/RECONSTRUCTIBLE=false/' "$docker_prod/.toolkit-adoption-fixture"
adoption_discover
assert_eq "production reconstructibility required" 0 "${#ADOPTION_CANDIDATES[@]}"
unset ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES
adoption_discover
assert_eq "test descriptor disabled in production" 0 "${#ADOPTION_CANDIDATES[@]}"

# Exercise production discovery through deterministic Docker CLI stubs. The
# fixture describes only read-only inspect results; no Docker daemon is used.
docker_live_work="$tmp/docker-live"
docker_live_root="$docker_live_work/frappe_docker"
docker_live_sites="$docker_live_work/sites"
mkdir -p "$docker_live_root" "$docker_live_sites/prod.test" "$tmp/bin"
touch "$docker_live_root/compose.yaml"
printf 'frappe\nerpnext\n' >"$docker_live_sites/apps.txt"
printf 'frappe\n' >"$docker_live_sites/prod.test/apps.txt"
printf '#!/usr/bin/env bash\nexit 99\n' >"$tmp/bin/docker"
chmod 755 "$tmp/bin/docker"
chmod -R go-w "$docker_live_work"
PATH="$tmp/bin:$PATH"
docker_ids=(aaaaaaaaaaaa bbbbbbbbbbbb cccccccccccc dddddddddddd eeeeeeeeeeee ffffffffffff 111111111111 222222222222 333333333333)
docker_services=(backend frontend websocket queue-short queue-long scheduler db redis-cache redis-queue)
docker_project=prod-project
docker_mixed_project=0
docker_image_id=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
docker_image_ref=registry.example.invalid/toolkit:v16
docker_digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
docker_mount="$docker_live_sites"
eval "$(declare -f inventory_run_probe | sed '1s/inventory_run_probe/inventory_run_probe_original/')"
inventory_run_probe() {
  local id fmt i
  if [[ "$1 $2" == 'docker ps' ]]; then
    printf '%s\n' "${docker_ids[@]}"
    return
  fi
  if [[ "$1 $2" == 'docker inspect' ]]; then
    fmt="$4"
    id="$5"
    for i in "${!docker_ids[@]}"; do [[ "${docker_ids[$i]}" == "$id" ]] && break; done
    case "$fmt" in
      *compose.project\"*) if [[ "$docker_mixed_project" == 1 && "$i" == 8 ]]; then printf 'other-project\n'; else printf '%s\n' "$docker_project"; fi ;;
      *compose.service\"*) printf '%s\n' "${docker_services[$i]}" ;;
      '{{.Image}}') [[ $i -lt 6 ]] && printf '%s\n' "$docker_image_id" || printf 'sha256:%064d\n' "$i" ;;
      '{{.Config.Image}}') printf '%s\n' "$docker_image_ref" ;;
      *'.Mounts'*) printf '%s\n' "$docker_mount" ;;
      *'NetworkSettings.Networks'*) printf '172.30.0.10\n' ;;
      *) return 1 ;;
    esac
    return
  fi
  if [[ "$1 $2 $3" == 'docker image inspect' ]]; then
    fmt="$5"
    case "$fmt" in *RepoDigests*) printf '%s@%s\n' "$docker_image_ref" "$docker_digest" ;; *image.version*) printf 'v16.0.0\n' ;; *) return 1 ;; esac
    return
  fi
  return 1
}
docker_compose() {
  printf 'forbidden docker compose operation: %s\n' "$*" >&2
  return 97
}
inventory_docker_exec() {
  printf 'forbidden docker exec operation: %s\n' "$*" >&2
  return 97
}
printf 'FORMAT\t1\nPROFILE\tfrappe-only\nAPP\tfrappe\thttps://github.com/frappe/frappe\tversion-16\tfrappe\nCREATED\t2026-08-02T00:00:00Z\nIMAGE\t%s\t%s\n' \
  "$docker_image_ref" "$docker_digest" >"$docker_live_work/erpnext-dev.app-manifest.tsv"
chmod go-w "$docker_live_work/erpnext-dev.app-manifest.tsv"
ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1
ADOPTION_CANDIDATES=()
adoption_docker_probe_live "$docker_live_root"
assert_eq "canonical production manifest and complete topology accepted" 1 "${#ADOPTION_CANDIDATES[@]}"
assert "Docker exact site inventory is host-mounted" grep -Fxq frappe "$docker_live_sites/prod.test/apps.txt"
docker_live_fp="${ADOPTION_CANDIDATES[0]##*|}"
docker_mixed_project=1
if adoption_docker_probe_live "$docker_live_root" >/dev/null 2>&1; then
  failures=$((failures + 1))
  printf 'FAIL: mixed Docker project labels rejected\n'
else printf 'OK: mixed Docker project labels rejected\n'; fi
assertions=$((assertions + 1))
docker_mixed_project=0
tmp_service="${docker_services[0]}"
docker_services[0]="${docker_services[1]}"
docker_services[1]="$tmp_service"
ADOPTION_CANDIDATES=()
adoption_docker_probe_live "$docker_live_root"
assert "Docker service identity change changes fingerprint" test "$docker_live_fp" != "${ADOPTION_CANDIDATES[0]##*|}"
tmp_service="${docker_services[0]}"
docker_services[0]="${docker_services[1]}"
docker_services[1]="$tmp_service"
docker_services[8]=db
if adoption_docker_probe_live "$docker_live_root" >/dev/null 2>&1; then
  failures=$((failures + 1))
  printf 'FAIL: partial Docker topology rejected\n'
else printf 'OK: partial Docker topology rejected\n'; fi
assertions=$((assertions + 1))
docker_services[8]=redis-queue
docker_mount="$docker_live_work/other/sites"
mkdir -p "$docker_mount/prod.test"
cp "$docker_live_sites/prod.test/apps.txt" "$docker_mount/prod.test/apps.txt"
cp "$docker_live_sites/apps.txt" "$docker_mount/apps.txt"
chmod -R go-w "$docker_live_work/other"
ADOPTION_CANDIDATES=()
adoption_docker_probe_live "$docker_live_root"
assert "Docker mount change changes fingerprint" test "$docker_live_fp" != "${ADOPTION_CANDIDATES[0]##*|}"
docker_mount="$docker_live_sites"
docker_digest=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ADOPTION_CANDIDATES=()
if adoption_docker_probe_live "$docker_live_root" >/dev/null 2>&1; then
  failures=$((failures + 1))
  printf 'FAIL: production manifest digest mismatch rejected\n'
else printf 'OK: production manifest digest mismatch rejected\n'; fi
assertions=$((assertions + 1))
sed -i "s/sha256:b\{64\}/$docker_digest/" "$docker_live_work/erpnext-dev.app-manifest.tsv"
chmod go-w "$docker_live_work/erpnext-dev.app-manifest.tsv"
ADOPTION_CANDIDATES=()
adoption_docker_probe_live "$docker_live_root"
assert "Docker digest and manifest identity change fingerprint" test "$docker_live_fp" != "${ADOPTION_CANDIDATES[0]##*|}"
docker_digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf 'FORMAT\t1\nPROFILE\tfrappe-only\nAPP\tfrappe\thttps://github.com/frappe/frappe\tversion-16\tfrappe\nCREATED\t2026-08-02T00:00:00Z\nIMAGE\t%s\t%s\n' \
  "$docker_image_ref" "$docker_digest" >"$docker_live_work/erpnext-dev.app-manifest.tsv"
chmod go-w "$docker_live_work/erpnext-dev.app-manifest.tsv"

unset ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES
inventory_run_probe() { inventory_run_probe_original "$@"; }

printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=recommended\nKEEP_SETTING=value\nPASSWORD=must-not-copy\n' >"$CONFIG_FILE"
stage="$tmp/stage"
adoption_stage_config "$CONFIG_FILE" "$stage" native development n-00000000000000000000 site.test "$(printf x | sha256sum | awk '{print $1}')" "$native" "" ""
assert_has "schema-2 written" "$stage" CONFIG_SCHEMA=2
assert_has "existing intent written" "$stage" INSTALLATION_PROFILE=existing
assert_has "existing app intent empty" "$stage" INSTALLATION_PROFILE_APPS=
assert_has "unrelated setting preserved" "$stage" KEEP_SETTING=value
assert "secret setting absent" test "$(grep -c PASSWORD "$stage")" -eq 0
assert_has "exact Bench persisted" "$stage" "BENCH_DIR=$native"
assert_has "adoption target persisted" "$stage" ADOPTION_TARGET_ID=n-00000000000000000000
assert "candidate configuration is data" bash -c "sed -n '/^adoption_stage_config()/,/^}/p' '$ROOT_DIR/lib/adoption.sh' | grep -Eq '(^|[[:space:]])(source|\.)[[:space:]]' && exit 1 || exit 0"

cp "$stage" "$CONFIG_FILE"
read_installation_profile_metadata "$CONFIG_FILE"
assert_eq "adoption metadata valid" true "$PROFILE_METADATA_ADOPTION_VALID"
assert_eq "adoption metadata site" site.test "$PROFILE_METADATA_ADOPTION_SITE"
docker_stage="$tmp/docker-stage"
adoption_stage_config "$stage" "$docker_stage" docker production d-00000000000000000000 prod.test \
  "$(printf docker | sha256sum | awk '{print $1}')" "$docker_live_root" "$docker_live_work" prod-project
cp "$docker_stage" "$CONFIG_FILE"
DOCKER_WORKDIR=/wrong
DOCKER_PROJECT_NAME=wrong
DOCKER_WORKDIR_ENV_PROVIDED=0
DOCKER_PROJECT_NAME_ENV_PROVIDED=0
load_adopted_operational_routing_if_available
assert_eq "adopted Docker routing reloads exact workdir" "$docker_live_work" "$DOCKER_WORKDIR"
assert_eq "adopted Docker routing reloads exact project" prod-project "$DOCKER_PROJECT_NAME"
printf 'CONFIG_SCHEMA=99\nINSTALLATION_PROFILE=existing\n' >"$CONFIG_FILE"
if read_installation_profile_metadata "$CONFIG_FILE" >/dev/null 2>&1; then
  failures=$((failures + 1))
  printf 'FAIL: unknown schema fails closed\n'
else printf 'OK: unknown schema fails closed\n'; fi

# Exercise the real journal/config-only transaction with every protected path
# redirected into the hermetic fixture.
require_sudo() { :; }
lock_count=0
acquire_toolkit_lock() {
  lock_count=$((lock_count + 1))
  mkdir -p "$(dirname "$LOCK_FILE")"
  : >"$LOCK_FILE"
}
printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=recommended\nKEEP_SETTING=value\n' >"$CONFIG_FILE"
cp "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"
ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1
assert "version proof remains path-safe" adoption_path_safe "$native/apps/frappe/frappe/__init__.py" file "$native"
adoption_discover
native_selector="native:n-$(printf '%s' "$native" | sha256sum | cut -c1-20):site.test"
adoption_select_exact "$native_selector"
deployment_before="$(sha256sum "$native/sites/site.test/apps.txt" "$native/apps/frappe/frappe/__init__.py")"
adoption_transaction
assert_eq "lock acquired for confirmed transaction" 1 "$lock_count"
assert_has "transaction adopted existing profile" "$CONFIG_FILE" INSTALLATION_PROFILE=existing
assert "primary and legacy mirrors match" cmp -s "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"
assert "prior primary retained" test -n "$(find "$ADOPTION_RECOVERY_DIR" -name 'prior-*.conf' -type f -print -quit)"
assert "prior legacy retained" test -n "$(find "$ADOPTION_RECOVERY_DIR" -name '*.legacy' -type f -print -quit)"
assert "prior artifacts private" bash -c "find '$ADOPTION_RECOVERY_DIR' -type f ! -perm 600 | grep -q . && exit 1 || exit 0"
assert "adoption journal complete" grep -Rq '^status=complete$' "$OPERATION_STATE_DIR"
assert "journal operation type" grep -Rq '^operation_type=existing-adoption$' "$OPERATION_STATE_DIR"
assert "journal records config fingerprints" grep -Rq '^candidate_config_fingerprint=[a-f0-9]\{64\}$' "$OPERATION_STATE_DIR"
assert_eq "deployment inventory unchanged" "$deployment_before" "$(sha256sum "$native/sites/site.test/apps.txt" "$native/apps/frappe/frappe/__init__.py")"
config_after="$(sha256sum "$CONFIG_FILE")"
adoption_select_exact "$native_selector"
adoption_transaction
assert_eq "idempotent re-adoption does not rewrite" "$config_after" "$(sha256sum "$CONFIG_FILE")"

transaction_failure_case() (
  local kind="$1" case_dir="$tmp/failure-$1" rc
  mkdir -p "$case_dir"
  CONFIG_FILE="$case_dir/config"
  LEGACY_CONFIG_FILE="$case_dir/legacy"
  OPERATION_STATE_DIR="$case_dir/operations"
  ADOPTION_RECOVERY_DIR="$case_dir/recovery"
  LOCK_FILE="$case_dir/lock"
  OPERATION_ID_OVERRIDE="failure-$kind"
  printf 'CONFIG_SCHEMA=2\nINSTALLATION_PROFILE=recommended\nKEEP_SETTING=prior\n' >"$CONFIG_FILE"
  cp "$CONFIG_FILE" "$LEGACY_CONFIG_FILE"
  local before
  before="$(adoption_config_pair_fingerprint)"
  ERPNEXT_DEV_EXISTING_DISCOVERY_ROOTS="$native"
  ERPNEXT_DEV_HERMETIC_ADOPTION_FIXTURES=1
  adoption_discover
  adoption_select_exact "$native_selector"
  case "$kind" in
    concurrent)
      acquire_toolkit_lock() { printf 'CONCURRENT=1\n' >>"$CONFIG_FILE"; }
      adoption_transaction >/dev/null 2>&1 && return 1
      [[ ! -e "$OPERATION_STATE_DIR" ]]
      ;;
    replace)
      adoption_write_mirrors() { return 1; }
      if adoption_transaction >/dev/null 2>&1; then return 1; else rc=$?; fi
      [[ "$rc" == 31 && "$(adoption_config_pair_fingerprint)" == "$before" ]]
      grep -Rq '^status=failed-safe$' "$OPERATION_STATE_DIR"
      ;;
    rollback)
      adoption_write_mirrors() { return 3; }
      if adoption_transaction >/dev/null 2>&1; then return 1; else rc=$?; fi
      [[ "$rc" == 33 && "$(adoption_config_pair_fingerprint)" == "$before" ]]
      grep -Rq '^status=recovery-required$' "$OPERATION_STATE_DIR"
      ;;
    restore)
      eval "$(declare -f adoption_discover | sed '1s/adoption_discover/adoption_discover_real/')"
      local discoveries=0
      adoption_discover() {
        adoption_discover_real
        discoveries=$((discoveries + 1))
        ((discoveries < 2)) || ADOPTION_CANDIDATES=()
      }
      if adoption_transaction >/dev/null 2>&1; then return 1; else rc=$?; fi
      [[ "$rc" == 32 && "$(adoption_config_pair_fingerprint)" == "$before" ]]
      grep -Rq '^status=verification-failed$' "$OPERATION_STATE_DIR"
      ;;
    divergence)
      eval "$(declare -f adoption_write_mirrors | sed '1s/adoption_write_mirrors/adoption_write_mirrors_real/')"
      adoption_write_mirrors() {
        adoption_write_mirrors_real "$1" || return
        printf 'DIVERGED=1\n' >>"$LEGACY_CONFIG_FILE"
      }
      if adoption_transaction >/dev/null 2>&1; then return 1; else rc=$?; fi
      [[ "$rc" == 33 ]]
      grep -Rq '^status=recovery-required$' "$OPERATION_STATE_DIR"
      ;;
  esac
)
assert "concurrent configuration change stops before staging" transaction_failure_case concurrent
assert "replacement failure preserves proven prior mirrors" transaction_failure_case replace
assert "unprovable mirror rollback records recovery-required" transaction_failure_case rollback
assert "post-write verification failure safely restores prior mirrors" transaction_failure_case restore
assert "post-write mirror divergence cannot complete" transaction_failure_case divergence

make_custom_code "$native/apps/late_app"
mkdir -p "$native/sites/late.test"
printf 'frappe\nlate_app\n' >"$native/sites/late.test/apps.txt"
chmod -R go-w "$native/apps/late_app" "$native/sites/late.test"
adoption_discover
adoption_select_exact "$native_selector"
if adoption_transaction >/dev/null 2>&1; then
  failures=$((failures + 1))
  printf 'FAIL: changed complete fingerprint is not idempotent\n'
else printf 'OK: changed complete fingerprint is not idempotent\n'; fi
assertions=$((assertions + 1))
assert_eq "fingerprint conflict does not rewrite configuration" "$config_after" "$(sha256sum "$CONFIG_FILE")"
rm -r "$native/apps/late_app" "$native/sites/late.test"

BENCH_PARENT=/wrong
BENCH_NAME=wrong
BENCH_DIR=/wrong/bench
BENCH_PARENT_ENV_PROVIDED=0
BENCH_NAME_ENV_PROVIDED=0
load_adopted_operational_routing_if_available
assert_eq "adopted Native routing reloads exact Bench" "$native" "$BENCH_DIR"
read_installation_profile_metadata "$CONFIG_FILE"
PROFILE_METADATA_ADOPTION_ENGINE=docker
if adoption_metadata_matches_discovery; then
  failures=$((failures + 1))
  printf 'FAIL: wrong adopted engine is not a metadata match\n'
else printf 'OK: wrong adopted engine is not a metadata match\n'; fi
assertions=$((assertions + 1))

assert "no Bench mutation command" bash -c "! grep -Eq 'bench[[:space:]].*(install|migrate|new-site|uninstall|update)' '$ROOT_DIR/lib/adoption.sh'"
assert "no Docker mutation command" bash -c "! grep -Eq 'docker[[:space:]]+(pull|build|restart|stop|rm)|docker[[:space:]]+compose.*[[:space:]](up|down|restart|stop|rm)' '$ROOT_DIR/lib/adoption.sh'"
assert "no service mutation command" bash -c "! grep -Eq 'systemctl[[:space:]]+(start|stop|restart|enable|reload)' '$ROOT_DIR/lib/adoption.sh'"
assert "no package mutation command" bash -c "! grep -Eq '(apt|dnf|yum|pip|npm)[[:space:]].*(install|remove)' '$ROOT_DIR/lib/adoption.sh'"
assert "no candidate shell sourcing" bash -c "! grep -Eq '^[[:space:]]*(source|\.)[[:space:]].*\$' '$ROOT_DIR/lib/adoption.sh'"
assert "no deployment backup invocation" bash -c "! grep -Eq '(backup_site|docker_backup|run_backup)' '$ROOT_DIR/lib/adoption.sh'"

printf 'existing-installation adoption tests: %s assertions, %s failure(s)\n' "$assertions" "$failures"
((failures == 0))
