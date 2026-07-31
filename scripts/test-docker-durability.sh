#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fixture="$(mktemp -d "${ROOT_DIR}/.erpnext-dev-docker-durability.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
failures=0
pass() { printf 'OK: %s\n' "$1"; }
fail_case() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
assert_has() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail_case "$1 (missing $3)"; fi; }
assert_not_has() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail_case "$1 (unexpected $3)"; fi; }

SUDO=""
RED="" GREEN="" YELLOW="" BLUE="" RESET=""
ASSUME_YES=1
INSTALLATION_PROFILE=recommended
DEPLOYMENT_ENGINE=docker
DOCKER_MODE=development
DOCKER_WORKDIR="$fixture/work"
DOCKER_CUSTOM_IMAGE_APPS_FILE="$DOCKER_WORKDIR/apps.json"
DOCKER_CUSTOM_IMAGE_PROFILES_FILE="$DOCKER_WORKDIR/profiles"
DOCKER_CUSTOM_IMAGE_CORE_FILE="$DOCKER_WORKDIR/core.env"
DOCKER_APP_MANIFEST_FILE="$DOCKER_WORKDIR/manifest.tsv"
DOCKER_APP_MANIFEST_CANDIDATE_FILE="$DOCKER_WORKDIR/manifest.candidate.tsv"
DOCKER_CUSTOM_IMAGE_STATE_FILE="$DOCKER_WORKDIR/image.env"
DOCKER_ERPNEXT_IMAGE="frappe/erpnext:v16.26.2"

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/profile.sh"
source "$ROOT_DIR/lib/apps.sh"
require_sudo() { :; }
effective_deployment_engine() { printf 'docker\n'; }
docker_is_production() { [[ "$DOCKER_MODE" == production ]]; }
source "$ROOT_DIR/lib/docker.sh"

# shellcheck disable=SC2218
docker_write_apps_json crm
manifest="$(cat "$DOCKER_APP_MANIFEST_CANDIDATE_FILE")"
assert_has "recommended manifest requires Frappe" "$manifest" $'APP\tfrappe\t'
assert_has "recommended manifest includes ERPNext" "$manifest" $'APP\terpnext\t'
assert_has "recommended manifest includes curated app" "$manifest" $'APP\tcrm\t'
docker_validate_app_manifest "$DOCKER_APP_MANIFEST_CANDIDATE_FILE" || fail_case "valid recommended manifest rejected"
pass "valid cumulative recommended manifest"

INSTALLATION_PROFILE=frappe-only
# shellcheck disable=SC2218
docker_write_apps_json crm
manifest="$(cat "$DOCKER_APP_MANIFEST_CANDIDATE_FILE")"
assert_has "Frappe-only manifest requires Frappe" "$manifest" $'APP\tfrappe\t'
assert_not_has "ERPNext optional in Frappe-only manifest" "$manifest" $'APP\terpnext\t'
assert_not_has "Frappe-only apps.json omits ERPNext" "$(cat "$DOCKER_CUSTOM_IMAGE_APPS_FILE")" 'frappe/erpnext'

docker_collect_installed_optional_profiles() { :; }
mapfile -t cumulative < <(docker_collect_desired_app_profiles helpdesk)
# shellcheck disable=SC2218
docker_write_apps_json "${cumulative[@]}"
manifest="$(cat "$DOCKER_APP_MANIFEST_CANDIDATE_FILE")"
assert_has "second app preserves first" "$manifest" $'APP\tcrm\t'
assert_has "dependency ordered before app" "$manifest" $'APP\ttelephony\t'
assert_has "second app added cumulatively" "$manifest" $'APP\thelpdesk\t'

cp "$DOCKER_APP_MANIFEST_CANDIDATE_FILE" "$fixture/duplicate"
sed -n '/^APP\tcrm\t/p' "$DOCKER_APP_MANIFEST_CANDIDATE_FILE" >>"$fixture/duplicate"
if docker_validate_app_manifest "$fixture/duplicate"; then fail_case "duplicate manifest app accepted"; else pass "duplicate manifest app rejected"; fi
printf 'FORMAT\t1\nPROFILE\trecommended\nAPP\tfrappe\thttps://evil.invalid/x\tversion-16\tfrappe\n' >"$fixture/tampered"
if docker_validate_app_manifest "$fixture/tampered"; then fail_case "tampered source accepted"; else pass "manifest source tampering rejected"; fi
printf 'FORMAT\t1\nPROFILE\trecommended\nAPP\tfrappe\thttps://github.com/frappe/frappe\tbad;ref\tfrappe\n' >"$fixture/bad-ref"
if docker_validate_app_manifest "$fixture/bad-ref"; then fail_case "malformed revision accepted"; else pass "malformed revision rejected"; fi
printf 'PROFILE\tfrappe-only\nAPP\tfrappe\thttps://github.com/frappe/frappe\tversion-16\tfrappe\nCREATED\t2026-07-31T00:00:00Z\n' >"$fixture/no-format"
if docker_validate_app_manifest "$fixture/no-format"; then fail_case "missing manifest format accepted"; else pass "missing manifest format rejected"; fi
printf 'FORMAT\t1\nFORMAT\t1\nPROFILE\tfrappe-only\nAPP\tfrappe\thttps://github.com/frappe/frappe\tversion-16\tfrappe\nCREATED\t2026-07-31T00:00:00Z\n' >"$fixture/duplicate-format"
if docker_validate_app_manifest "$fixture/duplicate-format"; then fail_case "duplicate manifest metadata accepted"; else pass "duplicate manifest metadata rejected"; fi

rm -f "$DOCKER_APP_MANIFEST_CANDIDATE_FILE"

INSTALLATION_PROFILE=frappe-only
# shellcheck disable=SC2218
docker_write_apps_json crm
printf 'last-known-good\n' >"$DOCKER_APP_MANIFEST_FILE"
assert_has "candidate build preserves last-known-good manifest" "$(cat "$DOCKER_APP_MANIFEST_FILE")" 'last-known-good'
docker_app_manifest_record_image replacement:test sha256:1111111111111111111111111111111111111111111111111111111111111111
docker_promote_app_manifest
assert_has "verified manifest promotion records digest" "$(cat "$DOCKER_APP_MANIFEST_FILE")" $'IMAGE\treplacement:test\tsha256:'
rm -f "$DOCKER_APP_MANIFEST_CANDIDATE_FILE"
ln -s "$fixture/tampered" "$DOCKER_APP_MANIFEST_CANDIDATE_FILE"
if docker_write_app_manifest crm; then fail_case "symlinked manifest accepted"; else pass "symlinked manifest rejected"; fi
rm -f "$DOCKER_APP_MANIFEST_CANDIDATE_FILE"

DOCKER_OVERRIDE_FILE="$fixture/override.yml"
docker_override_file() { printf '%s\n' "$DOCKER_OVERRIDE_FILE"; }
INSTALLATION_PROFILE=frappe-only
docker_write_override
assert_not_has "development Frappe-only site omits install-app ERPNext" "$(cat "$DOCKER_OVERRIDE_FILE")" '--install-app erpnext'
INSTALLATION_PROFILE=recommended
docker_write_override
assert_has "development recommended site installs ERPNext" "$(cat "$DOCKER_OVERRIDE_FILE")" '--install-app erpnext'

DOCKER_MODE=production
INSTALLATION_PROFILE=frappe-only
docker_custom_image_site_app_version() { [[ "$1" == frappe ]] && printf '16.26.2\n'; }
docker_custom_image_release_ref_exists() { return 0; }
docker_custom_image_capture_core_state
core="$(cat "$DOCKER_CUSTOM_IMAGE_CORE_FILE")"
assert_has "production Frappe-only pins Frappe" "$core" 'DOCKER_CUSTOM_IMAGE_FRAPPE_VERSION=16.26.2'
assert_has "production Frappe-only omits ERPNext version requirement" "$core" 'DOCKER_CUSTOM_IMAGE_ERPNEXT_VERSION='

docker_custom_image_image_app_version() { [[ "$2" == frappe ]] && printf '16.26.2\n'; }
docker_custom_image_verify_core_versions test-image >/dev/null || fail_case "valid Frappe-only image rejected"
pass "Frappe-only image verification"
docker_custom_image_image_app_version() { if [[ "$2" == frappe ]]; then printf '16.26.2\n'; else printf '16.26.2\n'; fi; }
if docker_custom_image_verify_core_versions test-image >/dev/null 2>&1; then fail_case "unexpected ERPNext accepted"; else pass "unexpected ERPNext rejected"; fi

# Exercise the Phase 3 journal's production adapter with Docker lifecycle mocks.
source "$ROOT_DIR/lib/inventory.sh"
source "$ROOT_DIR/lib/planner.sh"
PLAN_APP=erpnext
PLAN_SITE=one.test
PLAN_STACK=docker:test
PLAN_CURRENT_PROFILE=frappe-only
PLAN_RESULT_PROFILE=recommended
PLAN_INVENTORY_FINGERPRINT=stable
PLAN_SITE_STATE=not-installed
OPERATION_FILE="$fixture/operation.state"
OPERATION_STATUS=planned
OPERATION_CHECKPOINTS=planned
OPERATION_BACKUP_REFERENCE=""
OPERATION_PREVIOUS_IMAGE=""
OPERATION_REPLACEMENT_IMAGE=""
INSTALLATION_PROFILE=frappe-only
DOCKER_ERPNEXT_IMAGE=frappe-only:old
DOCKER_ERPNEXT_IMAGE_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
stage_fail=""
deployed=0
deploy_calls=0
planner_inventory_fingerprint() { printf 'stable\n'; }
inventory_collect() { :; }
inventory_records_sorted() { printf 'SITE|docker:test|one.test|known\n'; }
planner_checkpoint() {
  OPERATION_CHECKPOINTS="${OPERATION_CHECKPOINTS},$1"
  OPERATION_STATUS="${2:-$OPERATION_STATUS}"
}
planner_fail_record() {
  OPERATION_STATUS="${4:-failed}"
  OPERATION_FAILURE_STAGE="$1"
  OPERATION_FAILURE_REASON="$2"
  OPERATION_RECOVERY="$3"
}
docker_collect_desired_app_profiles() { :; }
docker_write_apps_json() { [[ "$stage_fail" != manifest ]]; }
docker_build_custom_image() { [[ "$stage_fail" != build ]]; }
docker_env_value() {
  case "$2" in
    DOCKER_CUSTOM_IMAGE) printf 'replacement:test\n' ;;
    DOCKER_CUSTOM_IMAGE_ID) [[ "$stage_fail" == digest ]] && printf 'unknown\n' || printf 'sha256:%064d\n' 1 ;;
  esac
}
planner_docker_backup_all() {
  [[ "$stage_fail" != backup ]] || return 1
  OPERATION_BACKUP_REFERENCE='one.test:verified'
}
docker_deploy_custom_image() {
  deploy_calls=$((deploy_calls + 1))
  [[ "$stage_fail" != deploy ]] || return 1
  deployed=1
}
planner_site_installed() { [[ "$deployed" -eq 1 ]]; }
docker_custom_image_verify_runtime() { [[ "$stage_fail" != health ]]; }
docker_custom_image_selected_app_names() { printf 'erpnext\n'; }
write_dev_config_file() { printf '%s\n' "$INSTALLATION_PROFILE" >"$fixture/profile"; }

stage_fail=build
set +e
planner_execute_docker_production
lifecycle_rc=$?
set -e
if [[ "$lifecycle_rc" -eq 31 && "$deploy_calls" -eq 0 ]]; then pass "build failure leaves deployment unchanged"; else fail_case "build failure mutated deployment"; fi
stage_fail=digest
set +e
planner_execute_docker_production
lifecycle_rc=$?
set -e
if [[ "$lifecycle_rc" -eq 32 && "$deploy_calls" -eq 0 ]]; then pass "digest verification blocks deployment"; else fail_case "unverified image deployed"; fi
stage_fail=backup
set +e
planner_execute_docker_production
lifecycle_rc=$?
set -e
if [[ "$lifecycle_rc" -eq 30 && "$deploy_calls" -eq 0 ]]; then pass "backup failure blocks deployment"; else fail_case "deployment followed backup failure"; fi
stage_fail=deploy
set +e
planner_execute_docker_production
lifecycle_rc=$?
set -e
assert_has "deployment failure retains previous image" "$OPERATION_RECOVERY" 'frappe-only:old@sha256:'
stage_fail=""
deployed=0
planner_execute_docker_production
if [[ "$OPERATION_STATUS" == completed && "$(cat "$fixture/profile")" == recommended ]]; then pass "ERPNext durable transition completes after verification"; else fail_case "durable profile transition failed"; fi
assert_has "replacement image digest recorded" "$OPERATION_REPLACEMENT_IMAGE" 'replacement:test@sha256:'

if grep -nE '\brg([[:space:]]|$)' "$0" >/dev/null; then fail_case "non-portable ripgrep dependency reintroduced"; else pass "portability correction preserved"; fi
if grep -Eq 'planner_checkpoint image-verified.*planner_docker_backup_all.*docker_deploy_custom_image' <(tr '\n' ' ' <"$ROOT_DIR/lib/planner.sh"); then
  pass "production lifecycle orders image verification before backup and deployment"
else
  fail_case "production lifecycle order regressed"
fi

if ((failures)); then
  printf 'docker-durability tests: %s failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'docker-durability tests: all checks passed\n'
